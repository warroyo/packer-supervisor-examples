/*
    DESCRIPTION:
    Upload-ISO build stage.
    Uploads the locally remastered ISO to a vSphere content library using govc.
    Run this stage after `make remaster` and before `make build` when using
    the local-upload path:
      make all-local   # remaster → upload → build
    Or directly:
      packer build -only="upload-iso.null.upload" -var-file=<vars> builds/linux/oracle/9/

    Requires govc_url, govc_username, and govc_password in the vars file.
    After the first upload set import_source_url="" — Packer will use the
    already-present library item via image_name on subsequent runs.
*/

packer {
  required_version = ">= 1.15.0"
}

source "null" "upload" {
  communicator = "none"
}

build {
  name    = "upload-iso"
  sources = ["source.null.upload"]

  provisioner "shell-local" {
    environment_vars = [
      "GOVC_URL=${var.govc_url}",
      "GOVC_USERNAME=${var.govc_username}",
      "GOVC_PASSWORD=${var.govc_password}",
      "GOVC_INSECURE=${var.govc_insecure}",
      "IMPORT_LIBRARY=${var.import_target_location_name}",
      "IMPORT_IMAGE_NAME=${var.import_target_image_name}",
      "LOCAL_ISO_PATH=${path.root}/../../../../.build/${var.import_target_image_name}.iso",
      "UPLOAD_OVERWRITE=${var.upload_overwrite}",
    ]
    inline = [
      "if [ \"$UPLOAD_OVERWRITE\" = 'true' ]; then govc library.item.rm -l \"$IMPORT_LIBRARY\" \"$IMPORT_IMAGE_NAME\" 2>/dev/null || true; fi",
      "govc library.import -n \"$IMPORT_IMAGE_NAME\" \"$IMPORT_LIBRARY\" \"$LOCAL_ISO_PATH\""
    ]
  }
}
