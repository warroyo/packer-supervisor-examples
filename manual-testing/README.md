# Manual Testing

End-to-end workflow for manually building an Oracle Linux 9 base image on vSphere Supervisor. Mirrors what Packer does, broken into discrete steps so each can be inspected and re-run independently.

## Prerequisites

- `kubectl` pointed at your Supervisor cluster
- `govc` (for the ISO import fallback script)
- Go 1.21+ (for the keyboard tool)
- `GOVMOMI_URL` env var set to your vCenter URL with credentials (`https://user:pass@vcenter/sdk`)

Run `make help` from `manual-testing/` to see all available targets.

---

## Step 1 — Import the ISO

**Option A: Kubernetes CR (preferred)**

Fill in the `checksum.value` field in `01-iso-import.yaml` with the ISO SHA256, then:

```bash
make apply-iso
kubectl get contentlibraryitemimportrequest oraclelinux-9-dvd-iso -n production-c5b8n -w
```

**Option B: govc (use if the CR times out)**

```bash
export GOVC_URL="https://vcenter.example.com"
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_PASSWORD="..."
export GOVC_INSECURE=true
bash import-iso-govc.sh
```

---

## Step 2 — Start the kickstart server

Edit the `ks.cfg` in the ConfigMap to set the packer user password hash, then:

```bash
make apply-kickstart
make kickstart-ip   # prints the ClusterIP you'll use in the boot command
```

---

## Step 3 — Create the Stage 1 VM

Update the `cdrom.image.name` field in `03-stage1-vm.yaml` with the `VirtualMachineImage` name from Step 1:

```bash
kubectl get vmi -n production-c5b8n | grep oraclelinux
```

Then apply:

```bash
make apply-vm
make watch-vm   # streams power state changes
```

Open the VM console in vSphere. Use the keyboard tool (Step 3a) to send the boot command, or manually edit the GRUB line as described in the file's comments.

### Step 3a — Send the boot command with the keyboard tool

**Build:**

```bash
make build
```

**Create a boot config JSON** (adjust IPs to match your environment):

```json
{
  "vm_name": "ol9-stage1",
  "boot_command": [
    "<tab><wait>",
    " quiet ip=<VM-IP>::<GATEWAY>:<NETMASK>:<HOSTNAME>:ens192:none nameserver=<DNS>",
    " inst.ks=http://<KS-IP>/ks.cfg<enter>"
  ]
}
```

| Placeholder  | Description                                    |
|--------------|------------------------------------------------|
| `<VM-IP>`    | Free IP on the workload network (install only) |
| `<GATEWAY>`  | Workload network default gateway               |
| `<NETMASK>`  | e.g. `255.255.255.0`                           |
| `<HOSTNAME>` | Any short name                                 |
| `<DNS>`      | Nameserver on the workload network             |
| `<KS-IP>`    | ClusterIP from `make kickstart-ip`             |

**Run:**

```bash
export GOVMOMI_URL="https://user:pass@vcenter/sdk"
./virtual-keyboard-hack/vkbd --config boot.json
# override VM name without editing the file
./virtual-keyboard-hack/vkbd --config boot.json --vm ol9-stage1
```

The tool connects to vCenter, finds the VM by name, and replays each character and special key (`<tab>`, `<enter>`, `<wait>`, etc.) as native USB HID scan codes — the same mechanism Packer uses.

---

## Step 4 — Publish the template

Wait for the kickstart install to complete and the VM to power off:

```bash
make watch-vm
```

Then publish:

```bash
make apply-publish
make watch-publish
```

The published OVF template (`ol9-base-template`) lands in `cl-production-images` and is ready for Packer or VM Operator to clone from.

---

## Cleanup

```bash
make clean
# optionally remove the ISO from the content library
govc library.rm /cl-production-images/oraclelinux-9-dvd-iso
```
