#!/usr/bin/env bash
# scripts/upload-iso.sh
#
# Uploads the remastered ISO to a vSphere content library via govc.
# Invoked by Packer as a shell-local provisioner (see upload.pkr.hcl).
# All inputs come from environment variables set by Packer.

set -euo pipefail

if [ "${UPLOAD_OVERWRITE}" = "true" ]; then
  govc library.rm "/${IMPORT_LIBRARY}/${IMPORT_IMAGE_NAME}" || true
fi

govc library.import -n "${IMPORT_IMAGE_NAME}" "${IMPORT_LIBRARY}" "${LOCAL_ISO_PATH}"
