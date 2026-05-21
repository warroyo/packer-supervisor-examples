NAMESPACE      := production-c5b8n
VKBD_DIR       := virtual-keyboard-hack
VKBD_BIN       := $(VKBD_DIR)/vkbd

.PHONY: help build apply-iso apply-kickstart apply-vm apply-publish \
        kickstart-ip watch-vm watch-publish up clean

help:
	@echo "Targets:"
	@echo "  build            Build the virtual keyboard tool"
	@echo "  apply-iso        Step 1 — import ISO via ContentLibraryItemImportRequest"
	@echo "  apply-kickstart  Step 2 — deploy kickstart ConfigMap + server"
	@echo "  apply-vm         Step 3 — create Stage 1 VM + PVC"
	@echo "  apply-publish    Step 4 — publish VM to content library"
	@echo "  up               Apply steps 1-3 in order"
	@echo "  kickstart-ip     Print ClusterIP of kickstart-service"
	@echo "  watch-vm         Watch Stage 1 VM power state"
	@echo "  watch-publish    Watch publish request status"
	@echo "  clean            Delete all resources created by this workflow"

## Build

build: $(VKBD_BIN)

$(VKBD_BIN): $(VKBD_DIR)/main.go $(VKBD_DIR)/go.mod
	cd $(VKBD_DIR) && go build -o vkbd .

## Apply steps

apply-iso:
	kubectl apply -f 01-iso-import.yaml

apply-kickstart:
	kubectl apply -f 02-kickstart-server.yaml

apply-vm:
	kubectl apply -f 03-stage1-vm.yaml

apply-publish:
	kubectl apply -f 04-publish-vm.yaml

up: apply-iso apply-kickstart apply-vm

## Inspect

kickstart-ip:
	@kubectl get svc kickstart-service -n $(NAMESPACE) -o jsonpath='{.spec.clusterIP}' && echo

watch-vm:
	kubectl get vm ol9-stage1 -n $(NAMESPACE) -w

watch-publish:
	kubectl get vmpublishrequest ol9-stage1-publish -n $(NAMESPACE) -w

## Cleanup

clean:
	-kubectl delete -f 04-publish-vm.yaml --ignore-not-found
	-kubectl delete -f 03-stage1-vm.yaml --ignore-not-found
	-kubectl delete -f 02-kickstart-server.yaml --ignore-not-found
	-kubectl delete -f 01-iso-import.yaml --ignore-not-found
