/*
    DESCRIPTION:
    Stage 1: Base OS Installation (ISO to OVF Template).
    Oracle Linux 9 — Packer Plugin for VMware vSphere: 'vsphere-supervisor' builder.

    Boots a remastered installer ISO with a baked-in kickstart.  The kickstart
    performs an entirely offline OS install (no network required) and powers off
    when finished.  Packer publishes the resulting disk as an OVF template to a
    content library for use as the Stage 2 source image.

    communicator = "none" — the vsphere-supervisor plugin strips the bootstrap
    block from the Kubernetes VirtualMachine manifest when the source is a raw
    ISO, which prevents cloud-init network injection and makes SSH unreachable.
*/

packer {
  required_version = ">= 1.15.0"
  required_plugins {
    vsphere = {
      source  = "github.com/vmware/vsphere"
      version = ">= 2.1.1"
    }
  }
}

locals {
  stage1_source_name = var.source_name != "" ? var.source_name : substr(
    replace("s1-${formatdate("MMDDhhmm", timestamp())}", ".", ""), 0, 15
  )
  stage1_publish_name = var.stage1_publish_image_name != "" ? var.stage1_publish_image_name : (
    "${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}-base-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  )
}

source "vsphere-supervisor" "stage1-base" {
  kubeconfig_path      = var.kubeconfig_path
  supervisor_namespace = var.supervisor_namespace

  import_source_url             = var.import_source_url
  import_source_ssl_certificate = var.import_source_ssl_certificate
  import_target_location_name   = var.import_target_location_name
  import_target_image_type      = var.import_target_image_type
  import_target_image_name      = var.import_target_image_name
  import_request_name           = var.import_request_name
  watch_import_timeout_sec      = var.watch_import_timeout_sec
  keep_import_request           = var.keep_import_request
  clean_imported_image          = var.clean_imported_image

  image_name          = var.image_name
  source_name         = local.stage1_source_name
  class_name          = var.class_name
  storage_class       = var.storage_class
  guest_os_type       = var.guest_os_type
  iso_boot_disk_size  = var.iso_boot_disk_size
  keep_input_artifact = var.keep_input_artifact

  watch_source_timeout_sec = var.watch_source_timeout_sec

  publish_location_name     = var.stage1_publish_location_name
  publish_image_name        = local.stage1_publish_name
  watch_publish_timeout_sec = var.watch_publish_timeout_sec

  communicator = "none"
}

build {
  name    = "stage1-base"
  sources = ["source.vsphere-supervisor.stage1-base"]
}
