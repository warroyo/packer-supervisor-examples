/*
    DESCRIPTION:
    Oracle Linux 9 input variables.
    Packer Plugin for VMware vSphere: 'vsphere-supervisor' builder.
*/

//  BLOCK: variable
//  Defines the input variables.

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

// Source Virtual Machine

variable "image_name" {
  type        = string
  description = "Name of the source VM image (VirtualMachineImage) available to the Supervisor namespace. This is the pre-built Oracle Linux 9 cloud image you have published to a content library that the Supervisor namespace consumes."
}

variable "source_name" {
  type        = string
  description = "Name to give the source VirtualMachine object created during the build. Maximum 15 characters. Defaults to a generated name when unset."
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
  description = "Size of the boot PVC for the source VM."
  default     = "40Gi"
}

variable "bootstrap_provider" {
  type        = string
  description = "Bootstrap provider used to seed the source VM. One of CloudInit, Sysprep, vAppConfig."
  default     = "CloudInit"
}

variable "keep_input_artifact" {
  type        = bool
  description = "Preserve the source VirtualMachine and related cluster objects after the build completes."
  default     = false
}

variable "watch_source_timeout_sec" {
  type        = number
  description = "Number of seconds to wait for the source VM to be ready (SSH reachable). When booting from an install ISO this must cover ISO boot + Anaconda install + first reboot — allow at least 3600s."
  default     = 3600
}

// Source Image Importing (optional, off by default)

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
  description = "Name to assign to the imported image."
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

// Source Image Publishing

variable "publish_location_name" {
  type        = string
  description = "Target ContentLibrary name into which the customized image will be published. Leave empty to skip publishing."
  default     = ""
}

variable "publish_image_name" {
  type        = string
  description = "Name to assign to the published image. Auto-assigned when unset."
  default     = ""
}

variable "watch_publish_timeout_sec" {
  type        = number
  description = "Number of seconds to wait for publishing to complete."
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

// Communicator (SSH) Settings and Credentials

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
