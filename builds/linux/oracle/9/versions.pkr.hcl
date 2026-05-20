packer {
  required_version = ">= 1.15.0"
  required_plugins {
    vsphere = {
      source  = "github.com/vmware/vsphere"
      version = ">= 2.1.1"
    }
  }
}
