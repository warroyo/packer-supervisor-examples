PACKER_DIR := builds/linux/oracle/9
VAR_FILE   := $(PACKER_DIR)/linux-oracle.pkrvars.hcl

.PHONY: init remaster upload build all-url all-local clean

init:
	packer init $(PACKER_DIR)

## Build the remastered ISO locally (downloads vendor ISO once; reuses cache on checksum match).
remaster: init
	packer build \
	  -only="remaster-iso.null.remaster" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Upload the remastered ISO to the content library via govc.
## Set govc_url, govc_username, govc_password in the vars file.
## After first upload set import_source_url="" so Packer skips re-importing.
upload: init
	packer build \
	  -only="upload-iso.null.upload" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Run the vsphere-supervisor packer build.
build: init
	packer build \
	  -only="linux-oracle-9.vsphere-supervisor.linux-oracle" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Full local-upload path: remaster → upload via govc → build.
all-local: remaster upload build

## Full URL-import path: remaster → build (Packer imports from import_source_url).
all-url: remaster build

clean:
	rm -rf .cache .build
