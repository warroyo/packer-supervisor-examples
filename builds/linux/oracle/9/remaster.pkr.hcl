/*
    DESCRIPTION:
    Remaster-ISO build stage.
    Downloads the upstream Oracle Linux 9 install ISO (only when the cached
    copy is absent or its SHA-256 does not match source_iso_sha256), injects
    the rendered kickstart, and writes the result to .build/.

    Run this build stage before the main vsphere-supervisor build:
      packer build -only="remaster-iso.null.remaster" -var-file=<vars> builds/linux/oracle/9/
    Or use the Makefile at the repo root:
      make remaster
      make all
*/

packer {
  required_version = ">= 1.15.0"
}

source "null" "remaster" {
  communicator = "none"
}

build {
  name    = "remaster-iso"
  sources = ["source.null.remaster"]

  provisioner "shell-local" {
    environment_vars = [
      "SOURCE_ISO_URL=${var.source_iso_url}",
      "SOURCE_ISO_SHA256=${var.source_iso_sha256}",
      "KS_FILE=${path.root}/data/ks.cfg.tpl",
      "CACHE_DIR=${path.root}/../../../../.cache",
      "BUILD_DIR=${path.root}/../../../../.build",
      "OUTPUT_ISO=${path.root}/../../../../.build/${var.import_target_image_name}.iso",
      "BUILD_USERNAME=${var.build_username}",
      "BUILD_PASSWORD_ENCRYPTED=${var.build_password_encrypted}",
      "BUILD_PUBLIC_KEY=${var.build_key}",
      "VM_GUEST_OS_LANGUAGE=${var.vm_guest_os_language}",
      "VM_GUEST_OS_KEYBOARD=${var.vm_guest_os_keyboard}",
      "VM_GUEST_OS_TIMEZONE=${var.vm_guest_os_timezone}",
    ]
    script = "${path.root}/../../../../scripts/remaster-iso.sh"
  }
}
