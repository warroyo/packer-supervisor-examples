#!/usr/bin/env bash
# scripts/remaster-iso.sh
#
# Generic RHEL-family ISO remastering script.
# Downloads a vendor install ISO, injects a pre-rendered kickstart file,
# patches the EFI and BIOS bootloaders to use it automatically, and writes
# the result to an output ISO file.
#
# Uses xorriso's in-place modification mode — only the files that need
# changing are extracted and re-injected.  The full ISO contents are never
# unpacked to disk.
#
# Usage:
#   Export the variables below (or source a .env file), then:
#     ./scripts/remaster-iso.sh
#
# Required tools: curl, xorriso, envsubst
#   macOS: brew install xorriso gettext && brew link --force gettext
#   Linux: dnf/apt install xorriso gettext

set -euo pipefail

# ── Source ISO ────────────────────────────────────────────────────────────────
SOURCE_ISO_URL="${SOURCE_ISO_URL:?SOURCE_ISO_URL is required}"
SOURCE_ISO_SHA256="${SOURCE_ISO_SHA256:-}"

# ── Kickstart ─────────────────────────────────────────────────────────────────
# Path to a kickstart file (ks.cfg) or a *.tpl template rendered via envsubst.
KS_FILE="${KS_FILE:?KS_FILE is required (path to kickstart or *.tpl)}"

# ── Output ────────────────────────────────────────────────────────────────────
OUTPUT_ISO="${OUTPUT_ISO:-}"

# ── Local work directories ────────────────────────────────────────────────────
CACHE_DIR="${CACHE_DIR:-.cache}"
BUILD_DIR="${BUILD_DIR:-.build}"

# ── Kickstart template variables (used only when KS_FILE is a *.tpl) ─────────
BUILD_USERNAME="${BUILD_USERNAME:-packer}"
BUILD_PASSWORD_ENCRYPTED="${BUILD_PASSWORD_ENCRYPTED:-}"
BUILD_PUBLIC_KEY="${BUILD_PUBLIC_KEY:-}"
VM_GUEST_OS_LANGUAGE="${VM_GUEST_OS_LANGUAGE:-en_US}"
VM_GUEST_OS_KEYBOARD="${VM_GUEST_OS_KEYBOARD:-us}"
VM_GUEST_OS_TIMEZONE="${VM_GUEST_OS_TIMEZONE:-UTC}"

# ─────────────────────────────────────────────────────────────────────────────

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

check_deps() {
  local missing=()
  for cmd in curl xorriso envsubst; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    err "Missing required tools: ${missing[*]}"
    echo "  macOS: brew install xorriso gettext && brew link --force gettext" >&2
    echo "  Linux: install xorriso gettext via your package manager" >&2
    exit 1
  fi
}

compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

download_iso() {
  local dest="${CACHE_DIR}/$(basename "${SOURCE_ISO_URL}")"
  mkdir -p "${CACHE_DIR}"

  if [[ -f "${dest}" ]]; then
    if [[ -n "${SOURCE_ISO_SHA256}" ]]; then
      log "Verifying cached ISO checksum ..."
      local actual
      actual="$(compute_sha256 "${dest}")"
      if [[ "${actual}" == "${SOURCE_ISO_SHA256}" ]]; then
        log "Cache hit (SHA-256 OK): ${dest}"
        echo "${dest}"
        return 0
      fi
      log "Checksum mismatch on cached file — re-downloading ..."
      rm -f "${dest}"
    else
      log "Using cached ISO (no checksum configured): ${dest}"
      echo "${dest}"
      return 0
    fi
  fi

  log "Downloading ${SOURCE_ISO_URL} ..."
  curl -fL --progress-bar -o "${dest}" "${SOURCE_ISO_URL}"

  if [[ -n "${SOURCE_ISO_SHA256}" ]]; then
    log "Verifying SHA-256 ..."
    local actual
    actual="$(compute_sha256 "${dest}")"
    [[ "${actual}" == "${SOURCE_ISO_SHA256}" ]] \
      || die "SHA-256 mismatch\n  expected: ${SOURCE_ISO_SHA256}\n  actual:   ${actual}"
    log "SHA-256 OK"
  fi

  echo "${dest}"
}

render_kickstart() {
  local src="$1" dest="$2"

  if [[ "${src}" == *.tpl ]]; then
    log "Rendering kickstart template: ${src}"
    export BUILD_USERNAME BUILD_PASSWORD_ENCRYPTED BUILD_PUBLIC_KEY \
           VM_GUEST_OS_LANGUAGE VM_GUEST_OS_KEYBOARD VM_GUEST_OS_TIMEZONE
    envsubst '${BUILD_USERNAME} ${BUILD_PASSWORD_ENCRYPTED} ${BUILD_PUBLIC_KEY}
              ${VM_GUEST_OS_LANGUAGE} ${VM_GUEST_OS_KEYBOARD} ${VM_GUEST_OS_TIMEZONE}' \
      < "${src}" > "${dest}"
  else
    log "Using pre-rendered kickstart: ${src}"
    cp "${src}" "${dest}"
  fi
}

# Extract a single file from the ISO.  Returns 1 if the path doesn't exist.
iso_extract_file() {
  local iso="$1" iso_path="$2" dest="$3"
  mkdir -p "$(dirname "${dest}")"
  xorriso -osirrox on -indev "${iso}" \
    -extract "${iso_path}" "${dest}" \
    -commit_eject all 2>/dev/null
}

patch_grub_cfg() {
    local f="$1"
    [[ -f "${f}" ]] || return 1
    log "Patching EFI grub.cfg ..."
    perl -pi -e '
    s|(linuxefi\s+/images/pxeboot/vmlinuz\b[^\n]*)(\s*\n)|$1 inst.ks=cdrom:/ks.cfg inst.text inst.cmdline$2|;
    s/\s*rd\.live\.check//g;
    s/^set timeout=\d+/set timeout=1/;
    s/^set default="1"/set default="0"/;
    ' "${f}"
}

patch_isolinux_cfg() {
    local f="$1"
    [[ -f "${f}" ]] || return 1
    log "Patching BIOS isolinux.cfg ..."
    perl -pi -e '
    s|(^\s*append\b[^\n]*?initrd=initrd\.img\b[^\n]*)(\s*\n)|$1 inst.ks=cdrom:/ks.cfg inst.text$2|;
    s/\s*rd\.live\.check//g;
    s/^timeout \d+/timeout 10/;
    ' "${f}"
}
remaster() {
  local source_iso="$1" ks_file="$2" output_iso="$3"
  local patch_dir="${BUILD_DIR}/patches"
  rm -rf "${patch_dir}"
  mkdir -p "${patch_dir}"

  # ── Extract only the boot configs we need to patch ──────────────────────
  local grub_cfg="${patch_dir}/grub.cfg"
  local isolinux_cfg="${patch_dir}/isolinux.cfg"

  local xorriso_maps=()

  # Kickstart is always injected.
  xorriso_maps+=(-map "${ks_file}" /ks.cfg)

  # Patch EFI bootloader if present.
  if iso_extract_file "${source_iso}" /EFI/BOOT/grub.cfg "${grub_cfg}"; then
    patch_grub_cfg "${grub_cfg}"
    xorriso_maps+=(-map "${grub_cfg}" /EFI/BOOT/grub.cfg)
  else
    log "(No EFI/BOOT/grub.cfg found — skipping EFI patch)"
  fi

  # Patch BIOS bootloader if present.
  if iso_extract_file "${source_iso}" /isolinux/isolinux.cfg "${isolinux_cfg}"; then
    patch_isolinux_cfg "${isolinux_cfg}"
    xorriso_maps+=(-map "${isolinux_cfg}" /isolinux/isolinux.cfg)
  else
    log "(No isolinux/isolinux.cfg found — skipping BIOS patch)"
  fi

  # ── Build the modified ISO in a single pass ─────────────────────────────
  # Remove any previous output so xorriso always writes a fresh file.
  # xorriso errors when indev != outdev and the outdev already exists.
  rm -f "${output_iso}"
  log "Building modified ISO → ${output_iso} ..."
  xorriso \
    -indev  "${source_iso}" \
    -outdev "${output_iso}" \
    -overwrite on \
    "${xorriso_maps[@]}" \
    -boot_image any replay

  log "Done: ${output_iso}"
}

main() {
  check_deps
  mkdir -p "${BUILD_DIR}"

  local cached_iso
  cached_iso="$(download_iso)"

  local rendered_ks="${BUILD_DIR}/ks.cfg"
  render_kickstart "${KS_FILE}" "${rendered_ks}"

  local output_iso="${OUTPUT_ISO:-${BUILD_DIR}/$(basename "${SOURCE_ISO_URL}" .iso)-ks.iso}"
  remaster "${cached_iso}" "${rendered_ks}" "${output_iso}"
}

main "$@"
