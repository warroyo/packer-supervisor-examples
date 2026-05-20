PACKER_DIR    := builds/linux/oracle/9
VAR_FILE      := $(PACKER_DIR)/linux-oracle.pkrvars.hcl
RESOLVED_FILE := .build/resolved.pkrvars.hcl

.PHONY: init remaster upload resolve stage1 stage2 build all-url all-local clean

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
upload: init
	packer build \
	  -only="upload-iso.null.upload" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Resolve Supervisor resource names via kubectl and write .build/resolved.pkrvars.hcl.
## Optional — run after upload and/or stage1 to auto-discover image_name, stage2_image_name,
## and content library CRD names. Requires kubectl access to the Supervisor namespace.
resolve: init
	packer build \
	  -only="resolve-vars.null.resolve" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Stage 1: Base OS Installation — ISO to OVF template (communicator=none).
## Loads .build/resolved.pkrvars.hcl if present (overrides var-file values).
stage1: init
	packer build \
	  -only="stage1-base.vsphere-supervisor.stage1-base" \
	  -var-file=$(VAR_FILE) \
	  $$([ -f $(RESOLVED_FILE) ] && echo "-var-file=$(RESOLVED_FILE)") \
	  $(PACKER_DIR)

## Stage 2: Software Provisioning — OVF template to final golden image (communicator=ssh).
## Loads .build/resolved.pkrvars.hcl if present (overrides var-file values).
stage2: init
	packer build \
	  -only="stage2-provision.vsphere-supervisor.stage2-provision" \
	  -var-file=$(VAR_FILE) \
	  $$([ -f $(RESOLVED_FILE) ] && echo "-var-file=$(RESOLVED_FILE)") \
	  $(PACKER_DIR)

## Run both build stages sequentially.
build: stage1 stage2

## Full local-upload path: remaster → upload via govc → stage1 → stage2.
all-local: remaster upload build

## Full URL-import path: remaster → stage1 (Packer imports from import_source_url) → stage2.
all-url: remaster build

clean:
	rm -rf .cache .build
