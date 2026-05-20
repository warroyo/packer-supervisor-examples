/*
    DESCRIPTION:
    Oracle Linux 9 input variables.
    Packer Plugin for VMware vSphere: 'vsphere-supervisor' builder.
    Shared across remaster, upload, Stage 1 (base), and Stage 2 (provision).
*/

//  BLOCK: variable
//  Defines the input variables.

// govc Connection (used by the upload-iso build stage)

variable "govc_url" {
  type        = string
  description = "vCenter URL for govc (e.g. https://vcenter.example.com). Used by the upload-iso build stage."
  default     = ""
  sensitive   = true
}

variable "govc_username" {
  type        = string
  description = "vCenter username for govc."
  default     = ""
  sensitive   = true
}

variable "govc_password" {
  type        = string
  description = "vCenter password for govc."
  default     = ""
  sensitive   = true
}

variable "govc_insecure" {
  type        = bool
  description = "Skip TLS verification for the govc connection. Set to true when using a self-signed certificate."
  default     = false
}

variable "upload_overwrite" {
  type        = string
  description = "Set to \"true\" to delete the existing content library item before uploading. Required when the item already exists and needs to be replaced."
  default     = "false"
}

// Supervisor Connection

variable "kubeconfig_path" {
  type        = string
  description = "Path to the kubeconfig file used to authenticate to the Supervisor cluster. Defaults to $KUBECONFIG or $HOME/.kube/config when unset."
  default     = ""
}

variable "supervisor_namespace" {
  type        = string
  description = "The Supervisor namespace in which to create the source VirtualMachine. Defaults to the current kubeconfig context's namespace when unset."
  default     = ""
}

// Source ISO (used by the remaster-iso build stage)

variable "source_iso_url" {
  type        = string
  description = "URL of the upstream Oracle Linux 9 install ISO passed to scripts/remaster-iso.sh."
}

variable "source_iso_sha256" {
  type        = string
  description = "Expected SHA-256 of the upstream ISO. Cache is validated on each run and re-downloaded on mismatch. Leave empty to skip checksum verification."
  default     = ""
}

// Source Virtual Machine (shared across stages)

variable "image_name" {
  type        = string
  description = "Name of the VirtualMachineImage resource for the ISO (Stage 1 source). This is the resource name reported by `kubectl get virtualmachineimage -n <namespace>` after the ISO has been uploaded."
}

variable "source_name" {
  type        = string
  description = "Name to give the source VirtualMachine object. Maximum 15 characters. Auto-generated per stage when unset (s1-TIMESTAMP / s2-TIMESTAMP)."
  default     = ""
}

variable "class_name" {
  type        = string
  description = "Name of the VirtualMachineClass that describes virtual hardware for the source VM (CPU/memory profile)."
}

variable "storage_class" {
  type        = string
  description = "Name of the StorageClass used by the source VM."
}

variable "guest_os_type" {
  type        = string
  description = "Guest operating system identifier on the resulting VM."
  default     = "oracleLinux9_64Guest"
}

variable "iso_boot_disk_size" {
  type        = string
  description = "Size of the boot PVC for the Stage 1 source VM."
  default     = "40Gi"
}

variable "keep_input_artifact" {
  type        = bool
  description = "Preserve the source VirtualMachine and related cluster objects after the build completes."
  default     = false
}

variable "watch_source_timeout_sec" {
  type        = number
  description = "Number of seconds to wait for the source VM to be ready. Stage 1 (ISO boot + Anaconda install + poweroff) needs at least 3600s. Stage 2 (cloud-init boot) typically needs less."
  default     = 3600
}

// Source Image Importing (Stage 1 only, optional — off by default)

variable "import_source_url" {
  type        = string
  description = "Optional remote URL hosting an OVF/ISO image to import into a content library before the build runs. Leave empty to skip import."
  default     = ""
}

variable "import_source_ssl_certificate" {
  type        = string
  description = "PEM-encoded certificate for HTTPS endpoints used by the import source URL."
  default     = ""
}

variable "import_target_location_name" {
  type        = string
  description = "Target ContentLibrary name to receive the imported image."
  default     = ""
}

variable "import_target_image_type" {
  type        = string
  description = "Image type to import. One of ovf or iso. Defaults to the URL suffix when unset."
  default     = ""
}

variable "import_target_image_name" {
  type        = string
  description = "Friendly name to assign to the item in the content library. Used by the remaster and upload stages to name the local ISO file (.build/<name>.iso) and the library item."
  default     = ""
}

variable "import_request_name" {
  type        = string
  description = "Name of the import request object. Auto-generated when unset."
  default     = ""
}

variable "watch_import_timeout_sec" {
  type        = number
  description = "Number of seconds to wait for the import request to complete."
  default     = 600
}

variable "keep_import_request" {
  type        = bool
  description = "Preserve the import request object after the build completes."
  default     = false
}

variable "clean_imported_image" {
  type        = bool
  description = "Delete the imported image at the end of the build."
  default     = false
}

// Stage 1: Publishing the base OVF template

variable "stage1_publish_library_name" {
  type        = string
  description = "Human-readable name of the content library for Stage 1 output. Used by resolve.pkr.hcl to auto-resolve stage1_publish_location_name via kubectl."
  default     = ""
}

variable "stage1_publish_location_name" {
  type        = string
  description = "ContentLibrary CRD name (cl-xxxx form) from the Supervisor namespace into which Stage 1 publishes the base OVF template. Find it with `kubectl get contentlibrary -n <namespace>`."
  default     = ""
}

variable "stage1_publish_image_name" {
  type        = string
  description = "Name to assign to the Stage 1 published base image. Auto-assigned when unset."
  default     = ""
}

// Stage 2: Source image and publishing the final golden image

variable "stage2_publish_library_name" {
  type        = string
  description = "Human-readable name of the production content library for Stage 2 output. Used by resolve.pkr.hcl to auto-resolve stage2_publish_location_name via kubectl."
  default     = ""
}

variable "stage2_image_name" {
  type        = string
  description = "Name of the VirtualMachineImage resource for the base OVF (Stage 1 output). This is the image_name Stage 2 clones from. Find it with `kubectl get virtualmachineimage -n <namespace>` after Stage 1 publishes."
  default     = ""
}

variable "stage2_publish_location_name" {
  type        = string
  description = "ContentLibrary CRD name (cl-xxxx form) for the production content library. Stage 2 publishes the final golden image here."
  default     = ""
}

variable "stage2_publish_image_name" {
  type        = string
  description = "Name to assign to the Stage 2 published golden image. Auto-assigned when unset."
  default     = ""
}

variable "watch_publish_timeout_sec" {
  type        = number
  description = "Number of seconds to wait for publishing to complete (used by both stages)."
  default     = 600
}

// Guest Operating System Metadata (used in naming and bootstrap)

variable "vm_guest_os_family" {
  type        = string
  description = "Guest operating system family. Used for naming."
  default     = "linux"
}

variable "vm_guest_os_name" {
  type        = string
  description = "Guest operating system name. Used for naming."
}

variable "vm_guest_os_version" {
  type        = string
  description = "Guest operating system version. Used for naming."
}

variable "vm_guest_os_language" {
  type        = string
  description = "Guest operating system language."
  default     = "en_US.UTF-8"
}

variable "vm_guest_os_keyboard" {
  type        = string
  description = "Guest operating system keyboard layout."
  default     = "us"
}

variable "vm_guest_os_timezone" {
  type        = string
  description = "Guest operating system timezone."
  default     = "UTC"
}

// Communicator (SSH) Settings and Credentials (Stage 2)

variable "build_username" {
  type        = string
  description = "Username to create on, and login to, the source VM."
  sensitive   = true
}

variable "build_password" {
  type        = string
  description = "Plaintext password for the build user. Used by SSH and seeded into cloud-init."
  sensitive   = true
}

variable "build_password_encrypted" {
  type        = string
  description = "SHA-512 hashed password for the build user (e.g. produced by mkpasswd -m sha-512). Seeded into cloud-init."
  sensitive   = true
}

variable "build_key" {
  type        = string
  description = "SSH public key authorized for the build user. Seeded into cloud-init."
  sensitive   = true
  default     = ""
}

variable "communicator_port" {
  type        = number
  description = "SSH port on the source VM."
  default     = 22
}

variable "communicator_timeout" {
  type        = string
  description = "SSH connection timeout."
  default     = "30m"
}

// Additional Settings

variable "additional_packages" {
  type        = list(string)
  description = "Additional packages installed via cloud-init / provisioners."
  default     = []
}
