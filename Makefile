PACKER_DIR     := builds/linux/oracle/9
VAR_FILE       := $(PACKER_DIR)/linux-oracle.pkrvars.hcl
LOCAL_ISO_PATH := .build/oraclelinux-9-ks.iso

# Read content-library values from the pkrvars file so the upload target
# doesn't need them duplicated on the command line. Override with make
# upload IMPORT_LIBRARY=mylib IMPORT_IMAGE_NAME=myiso if needed.
IMPORT_LIBRARY    ?= $(shell grep 'import_target_location_name' $(VAR_FILE) 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/')
IMPORT_IMAGE_NAME ?= $(shell grep 'import_target_image_name'    $(VAR_FILE) 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/')

.PHONY: init remaster upload build all-url all-local clean

init:
	packer init $(PACKER_DIR)

## Build the remastered ISO locally (downloads vendor ISO once; reuses cache on checksum match).
remaster: init
	packer build \
	  -only="remaster-iso.null.remaster" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Upload the remastered ISO to the content library using govc.
## Requires GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD (and optionally GOVC_INSECURE=true).
## After first upload: set import_source_url="" in your vars file so Packer
## skips re-importing and uses the already-present library item via image_name.
upload: remaster
	@test -n "$(IMPORT_LIBRARY)"    || { echo "ERROR: import_target_location_name not set in $(VAR_FILE)"; exit 1; }
	@test -n "$(IMPORT_IMAGE_NAME)" || { echo "ERROR: import_target_image_name not set in $(VAR_FILE)"; exit 1; }
	@test -f "$(LOCAL_ISO_PATH)"    || { echo "ERROR: $(LOCAL_ISO_PATH) not found — run 'make remaster' first"; exit 1; }
	govc library.import -n "$(IMPORT_IMAGE_NAME)" "$(IMPORT_LIBRARY)" "$(LOCAL_ISO_PATH)"

## Run the vsphere-supervisor packer build.
build: init
	packer build \
	  -only="linux-oracle-9.vsphere-supervisor.linux-oracle" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

## Full URL-import path: remaster locally → host ISO externally → Packer imports from import_source_url.
## Requires import_source_url to be set in the vars file.
all-url: remaster build

## Full local-upload path: remaster locally → upload via govc → Packer builds from the library item.
## Requires GOVC_* env vars. Set import_source_url="" in vars file after first upload.
all-local: upload build

clean:
	rm -rf .cache .build
