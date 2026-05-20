/*
    DESCRIPTION:
    Resolve-vars build stage.
    Queries the Supervisor cluster via kubectl to discover Kubernetes resource
    names (VirtualMachineImage, ContentLibrary) and writes them to
    .build/resolved.pkrvars.hcl.  Subsequent stage1/stage2 builds load this
    file automatically via the Makefile.

    This stage is optional — run it when you want auto-resolution:
      packer build -only="resolve-vars.null.resolve" -var-file=<vars> builds/linux/oracle/9/
    Or use the Makefile:
      make resolve
*/

packer {
  required_version = ">= 1.15.0"
}

source "null" "resolve" {
  communicator = "none"
}

build {
  name    = "resolve-vars"
  sources = ["source.null.resolve"]

  provisioner "shell-local" {
    environment_vars = [
      "NAMESPACE=${var.supervisor_namespace}",
      "IMPORT_IMAGE_NAME=${var.import_target_image_name}",
      "STAGE1_PUBLISH_NAME=${var.stage1_publish_image_name}",
      "PUBLISH_LIBRARY_NAME=${var.publish_library_name}",
      "OUTPUT_FILE=${path.root}/../../../../.build/resolved.pkrvars.hcl",
    ]
    script = "${path.root}/../../../../scripts/resolve-vars.sh"
  }
}
