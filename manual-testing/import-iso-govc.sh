#!/usr/bin/env bash
# manual-testing/import-iso-govc.sh
#
# Imports the Oracle Linux 9 DVD ISO into a vSphere content library using govc.
# Use this instead of ContentLibraryItemImportRequest when the CR times out.
#
# Usage:
#   export GOVC_URL="https://vcenter.example.com"
#   export GOVC_USERNAME="administrator@vsphere.local"
#   export GOVC_PASSWORD="..."
#   export GOVC_INSECURE=true   # set if using self-signed cert
#   bash manual-testing/import-iso-govc.sh
#
# Or override defaults inline:
#   LIBRARY=my-library ITEM_NAME=my-iso bash manual-testing/import-iso-govc.sh

set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

ISO_URL="${ISO_URL:-https://yum.oracle.com/ISOS/OracleLinux/OL9/u5/x86_64/OracleLinux-R9-U5-x86_64-dvd.iso}"
LIBRARY="${LIBRARY:-cl-production-images}"
ITEM_NAME="${ITEM_NAME:-oraclelinux-9-dvd-iso}"
OVERWRITE="${OVERWRITE:-false}"

[[ -n "${GOVC_URL:-}"      ]] || die "GOVC_URL is not set"
[[ -n "${GOVC_USERNAME:-}" ]] || die "GOVC_USERNAME is not set"
[[ -n "${GOVC_PASSWORD:-}" ]] || die "GOVC_PASSWORD is not set"

command -v govc >/dev/null 2>&1 || die "govc not found — install with: make install-prereqs INSTALL_GOVC=true"

if [[ "${OVERWRITE}" == "true" ]]; then
  log "Removing existing item ${LIBRARY}/${ITEM_NAME} ..."
  govc library.rm "/${LIBRARY}/${ITEM_NAME}" || true
fi

log "Importing ${ITEM_NAME} into library ${LIBRARY} ..."
log "Source: ${ISO_URL}"
govc library.import -n "${ITEM_NAME}" "${LIBRARY}" "${ISO_URL}"

log "Done. Verify with:"
echo "  govc library.ls /${LIBRARY}/"
