/*
    DESCRIPTION:
    Oracle Linux 9 build definition.
    Packer Plugin for VMware vSphere: 'vsphere-supervisor' builder.

    The source image is a custom Oracle Linux 9 ISO with a kickstart baked in.
    Run scripts/remaster-iso.sh once to build and upload that ISO to the
    content library, then run `packer build` to deploy a VM from it, run
    in-guest provisioners, and publish the resulting image back to a content
    library as an OVF template (downloadable as OVA).

    Because the kickstart handles user/SSH setup, this build does not use
    a cloud-init bootstrap_data_file.  Set bootstrap_provider = "CloudInit"
    only if you also want cloud-init to run post-install (e.g. for additional
    per-boot configuration); for a plain kickstart-to-SSH pipeline leave
    bootstrap_provider empty or omit bootstrap_data_file.
*/

//  BLOCK: packer
//  The Packer configuration.

packer {
  required_version = ">= 1.15.0"
  required_plugins {
    vsphere = {
      source  = "github.com/vmware/vsphere"
      version = ">= 2.1.1"
    }
  }
}

//  BLOCK: locals
//  Defines the local variables.

locals {
  build_by          = "Built by: HashiCorp Packer ${packer.version}"
  build_date        = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
  build_description = "Built on: ${local.build_date}\n${local.build_by}"

  vm_name = "${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}"

  // Supervisor source VM names are limited to 15 characters.
  source_vm_name = var.source_name != "" ? var.source_name : substr(
    replace("ol9-${formatdate("MMDDhhmm", timestamp())}", ".", ""), 0, 15
  )

  // Published image name defaults to a stable, descriptive value when not overridden.
  published_image_name = var.publish_image_name != "" ? var.publish_image_name : (
    "${local.vm_name}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  )
}

//  BLOCK: source
//  Defines the builder configuration block.

source "vsphere-supervisor" "linux-oracle" {

  // Supervisor connection.
  // When kubeconfig_path or supervisor_namespace are empty strings the builder
  // falls back to $KUBECONFIG / $HOME/.kube/config and the current context's
  // namespace, respectively.
  kubeconfig_path      = var.kubeconfig_path
  supervisor_namespace = var.supervisor_namespace

  // Source image importing (optional).
  // Set import_source_url to a URL serving the custom ISO produced by
  // scripts/remaster-iso.sh that is reachable by the Supervisor cluster.
  // Leave empty if the image_name item is already in the content library.
  import_source_url           = var.import_source_url
  import_source_ssl_certificate = var.import_source_ssl_certificate
  import_target_location_name = var.import_target_location_name
  import_target_image_type    = var.import_target_image_type
  import_target_image_name    = var.import_target_image_name
  import_request_name         = var.import_request_name
  watch_import_timeout_sec    = var.watch_import_timeout_sec
  keep_import_request         = var.keep_import_request
  clean_imported_image        = var.clean_imported_image

  // Source VirtualMachine creation.
  // image_name must match import_target_image_name when using the import path,
  // or the name of a pre-existing library item when skipping import.
  image_name          = var.image_name
  source_name         = local.source_vm_name
  class_name          = var.class_name
  storage_class       = var.storage_class
  guest_os_type       = var.guest_os_type
  iso_boot_disk_size  = var.iso_boot_disk_size
  keep_input_artifact = var.keep_input_artifact

  // No bootstrap_data_file — the kickstart inside the ISO handles user/SSH setup.

  // Source VM readiness watching.
  // This timeout must cover ISO boot + Anaconda install + first reboot.
  watch_source_timeout_sec = var.watch_source_timeout_sec

  // Publishing the customized image back to a content library.
  publish_location_name     = var.publish_location_name
  publish_image_name        = local.published_image_name
  watch_publish_timeout_sec = var.watch_publish_timeout_sec

  // Communicator (SSH).
  // Credentials must match what was rendered into the kickstart by remaster-iso.sh.
  communicator = "ssh"
  ssh_username = var.build_username
  ssh_password = var.build_password
  ssh_port     = var.communicator_port
  ssh_timeout  = var.communicator_timeout
}

//  BLOCK: build
//  Defines the builders to run, provisioners, and post-processors.

build {
  name    = "linux-oracle-9"
  sources = ["source.vsphere-supervisor.linux-oracle"]

  // In-guest customization.  The kickstart already installed OL9 and created the
  // build user; these provisioners run after Packer SSHes into the live system.
  // Replace or extend with your own shell or ansible blocks as needed.
  provisioner "shell" {
    execute_command = "echo '${var.build_password}' | sudo -S -E bash '{{ .Path }}'"
    inline = [
      "echo '${local.build_description}' > /etc/vm-build-info",
      "dnf -y update",
      "dnf -y clean all",
    ]
  }
}
