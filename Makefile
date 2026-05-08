PACKER_DIR := builds/linux/oracle/9
VAR_FILE   := $(PACKER_DIR)/linux-oracle.pkrvars.hcl

.PHONY: init remaster build all clean

init:
	packer init $(PACKER_DIR)

remaster: init
	packer build \
	  -only="remaster-iso.null.remaster" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

build: init
	packer build \
	  -only="linux-oracle-9.vsphere-supervisor.linux-oracle" \
	  -var-file=$(VAR_FILE) \
	  $(PACKER_DIR)

all: remaster build

clean:
	rm -rf .cache .build
