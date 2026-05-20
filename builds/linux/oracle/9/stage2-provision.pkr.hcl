/*
    DESCRIPTION:
    Stage 2: Software Provisioning (OVF Template to Final Golden Image).
    Oracle Linux 9 — Packer Plugin for VMware vSphere: 'vsphere-supervisor' builder.

    Clones the base OVF template produced by Stage 1.  Because the source is an
    image (not a raw ISO), the plugin preserves the bootstrap block in the
    Kubernetes VirtualMachine manifest, allowing the Tanzu VM Operator to inject
    guestinfo network metadata via cloud-init.  This brings the network up
    automatically, enabling SSH-based provisioning.

    The build ends with a mandatory seal provisioner that resets cloud-init,
    clears network state, and wipes the machine ID so each clone boots clean.
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
  build_by          = "Built by: HashiCorp Packer ${packer.version}"
  build_date        = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  build_description = "Built on: ${local.build_date}\n${local.build_by}"

  stage2_source_name = var.source_name != "" ? var.source_name : substr(
    replace("s2-${formatdate("MMDDhhmm", timestamp())}", ".", ""), 0, 15
  )
  stage2_publish_name = var.stage2_publish_image_name != "" ? var.stage2_publish_image_name : (
    "${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  )
}

source "vsphere-supervisor" "stage2-provision" {
  kubeconfig_path      = var.kubeconfig_path
  supervisor_namespace = var.supervisor_namespace

  image_name          = var.stage2_image_name
  source_name         = local.stage2_source_name
  class_name          = var.class_name
  storage_class       = var.storage_class
  keep_input_artifact = var.keep_input_artifact

  bootstrap_provider  = "CloudInit"
  bootstrap_data_file = "${path.root}/data/stage2-userdata.yaml"

  watch_source_timeout_sec = var.watch_source_timeout_sec

  publish_location_name     = var.stage2_publish_location_name
  publish_image_name        = local.stage2_publish_name
  watch_publish_timeout_sec = var.watch_publish_timeout_sec

  communicator = "ssh"
  ssh_username = var.build_username
  ssh_password = var.build_password
  ssh_port     = var.communicator_port
  ssh_timeout  = var.communicator_timeout
}

build {
  name    = "stage2-provision"
  sources = ["source.vsphere-supervisor.stage2-provision"]

  // Placeholder: add custom provisioning (corporate packages, Docker, etc.)
  provisioner "shell" {
    execute_command = "echo '${var.build_password}' | sudo -S -E bash '{{ .Path }}'"
    inline = [
      "echo '${local.build_description}' > /etc/vm-build-info",
      "dnf -y update",
      "dnf -y clean all",
    ]
  }

  // Seal the image before capture — MUST be the last provisioner.
  provisioner "ansible" {
    playbook_file = "${path.root}/cleanup-playbook.yml"
  }
}
