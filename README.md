# Packer for Oracle Linux 9 on vSphere Supervisor

A 2-stage Packer image factory that builds Oracle Linux 9 golden images for
VMware vSphere using the [`vsphere-supervisor`](https://developer.hashicorp.com/packer/integrations/vmware/vsphere/latest/components/builder/vsphere-supervisor)
builder.

## Why two stages?

The `packer-plugin-vsphere` has a hard limitation: when the `vsphere-supervisor`
builder boots from a raw ISO, it strips the `spec.bootstrap` / `cloudInit` block
from the Kubernetes `VirtualMachine` manifest (`step_create_source.go`).
This prevents the VM Operator from injecting `guestinfo` network metadata,
causing SSH-based builds to fail with a `NoBootstrapStatus` error.

The workaround is a two-stage pipeline:

| Stage | Source | Communicator | Bootstrap | Output |
|-------|--------|-------------|-----------|--------|
| **Stage 1** — Base OS Install | Remastered ISO (kickstart) | `none` | Stripped by plugin (expected) | Base OVF template |
| **Stage 2** — Provisioning | Base OVF from Stage 1 | `ssh` | `CloudInit` (preserved for image sources) | Final golden image |

Stage 1 installs the OS entirely offline — no network needed. Stage 2 clones
the base OVF; because the source is an image (not an ISO), the plugin preserves
the bootstrap block, cloud-init brings the network up, and Packer SSHes in for
provisioning.

## Repository layout

```
.
├── Makefile
├── README.md
├── builds/
│   └── linux/
│       └── oracle/
│           └── 9/
│               ├── stage1-base.pkr.hcl              # Stage 1: ISO → base OVF (communicator=none)
│               ├── stage2-provision.pkr.hcl          # Stage 2: base OVF → golden image (communicator=ssh)
│               ├── resolve.pkr.hcl                   # Optional: auto-resolve resource names via kubectl
│               ├── remaster.pkr.hcl                  # Remaster-ISO build stage (null + shell-local)
│               ├── upload.pkr.hcl                    # Upload ISO via govc (null + shell-local)
│               ├── cleanup-playbook.yml              # Ansible playbook for image sealing (Stage 2)
│               ├── variables.pkr.hcl                 # Variable declarations (shared across stages)
│               ├── linux-oracle.pkrvars.hcl.example  # Sample input values — copy and edit
│               └── data/
│                   ├── ks.cfg.tpl                    # Kickstart template (rendered by remaster-iso.sh)
│                   └── stage2-userdata.yaml           # Cloud-init userdata for Stage 2 bootstrap
└── scripts/
    ├── remaster-iso.sh                               # ISO remastering script
    └── resolve-vars.sh                               # Resource name resolution (invoked by resolve.pkr.hcl)
```

## Prerequisites

- A vSphere environment with **vSphere Supervisor** enabled.
- A **Supervisor namespace** you can deploy into.
- A **VirtualMachineClass** (`kubectl get virtualmachineclass`).
- A **StorageClass** assigned to your namespace (`kubectl get storageclass`).
- A **writable content library** linked to the namespace — used to hold the
  custom ISO during import and to publish the finished image. You may use a
  single library or separate libraries for staging and production.
- A **kubeconfig** targeting the Supervisor cluster and namespace.
  Verify with `kubectl get ns`.
- **Packer 1.15.0+** with the `github.com/vmware/vsphere` plugin v2.1.1+
  (installed automatically by `packer init` / `make init`).
- **Ansible** (required for the Stage 2 cleanup playbook):
  ```sh
  apt-get install ansible
  ```
- **Remaster tools** (required to build the custom ISO):
  ```sh
  # macOS
  brew install xorriso gettext && brew link --force gettext
  # Linux
  dnf install xorriso gettext   # or apt-get install xorriso gettext
  ```
- **Optional — for auto-resolution** (`make resolve`): `jq`
  ```sh
  # macOS
  brew install jq
  # Linux
  dnf install jq   # or apt-get install jq
  ```
- **Network access from your Packer host to the source VM over SSH** (Stage 2
  only). The VM is created inside the Supervisor namespace; if the namespace
  network is not routable from your host, run Packer from a jump host that is.
- An **SHA-512 hashed password** for the build user:
  ```sh
  mkpasswd -m sha-512   # or: openssl passwd -6
  ```

## How it works

```
Oracle Linux 9 DVD ISO
        │
   (cached in .cache/ — skipped when SHA-256 matches)
        │
scripts/remaster-iso.sh  ←── kickstart rendered from data/ks.cfg.tpl
        │
  .build/oraclelinux-9-ks.iso
        │
  govc library.import  (or host at URL for cluster-side import)
        │
  ┌─────────────────── STAGE 1 (communicator=none) ───────────────────┐
  │                                                                    │
  │  VirtualMachine created, boots from ISO                            │
  │       │                                                            │
  │  Anaconda runs kickstart (offline OL9 install + build user + SSH   │
  │  + cloud-init + open-vm-tools + VMware datasource config)         │
  │       │                                                            │
  │  VM powers off → VirtualMachinePublishRequest                      │
  │       │                                                            │
  │  Base OVF template in content library                              │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
        │
  ┌─────────────────── STAGE 2 (communicator=ssh) ────────────────────┐
  │                                                                    │
  │  VirtualMachine cloned from base OVF                               │
  │       │                                                            │
  │  CloudInit bootstrap → VM Operator injects guestinfo metadata      │
  │       │                                                            │
  │  cloud-init brings network up → SSH ready                          │
  │       │                                                            │
  │  Provisioners run (dnf update, custom scripts, …)                  │
  │       │                                                            │
  │  Ansible cleanup playbook seals the image:                         │
  │    • cloud-init clean                                              │
  │    • wipe NM connections, machine-id, logs, temp files, history    │
  │       │                                                            │
  │  VirtualMachinePublishRequest                                      │
  │       │                                                            │
  │  Golden image in production content library  ──► downloadable OVA  │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
```

## Configuring a writable content library

The Supervisor namespace must have at least one content library configured as
writable before Packer or govc can import or publish images. This is a one-time
setup step done with DCLI.

### Find the content library ID

```sh
dcli +i
```

Inside the interactive session:

```
namespaces instances get --namespace <your-namespace>
```

Look for the `content_libraries` array in the output. Each entry has a
`content_library` field — that value is the content library ID (a UUID).

### Enable write access

Still inside the DCLI interactive session, pass the ID from the previous step:

```
namespaces instances update --namespace <your-namespace> \
  --content-libraries '[{"content_library": "<library-id>", "writable": true}]'
```

This updates the namespace binding for that library to allow write operations.
Repeat for each library that needs to be writable (source ISO library, stage 1
output library, and production library if they differ).

After this you can confirm the library is visible to the namespace with:

```sh
kubectl get contentlibrary -n <your-namespace>
```

## Quickstart

### 1 — Copy and edit the variables file

```sh
cp builds/linux/oracle/9/linux-oracle.pkrvars.hcl.example \
   builds/linux/oracle/9/linux-oracle.pkrvars.hcl
```

Open `linux-oracle.pkrvars.hcl` and set at minimum:

| Variable                    | Notes                                                              |
| --------------------------- | ------------------------------------------------------------------ |
| `source_iso_url`            | URL of the upstream OL9 DVD ISO (see [Finding the ISO](#finding-the-iso)) |
| `supervisor_namespace`      | Your Supervisor namespace name                                     |
| `import_target_location_name` | Writable content library name (used by upload)                   |
| `import_target_image_name`  | Friendly label for the ISO in the content library                  |
| `class_name`                | VirtualMachineClass name                                           |
| `storage_class`             | StorageClass name                                                  |
| `build_username`            | Build user created by the kickstart                                |
| `build_password`            | Plaintext — used by Packer SSH                                     |
| `build_password_encrypted`  | SHA-512 hash — baked into the kickstart                            |

For auto-resolution of resource names, also set:

| Variable                       | Notes                                                           |
| ------------------------------ | --------------------------------------------------------------- |
| `publish_library_name`         | Human-readable name of the content library (used by both stages) |
| `stage1_publish_image_name`    | Name to assign to the base OVF (for `stage2_image_name` resolution) |

Or set the CRD names manually (skip `make resolve`):

| Variable                       | Notes                                                           |
| ------------------------------ | --------------------------------------------------------------- |
| `image_name`                   | VirtualMachineImage resource name for the ISO                   |
| `stage1_publish_location_name` | ContentLibrary CRD name (`cl-xxxx`) for Stage 1 output         |
| `stage2_image_name`            | VirtualMachineImage resource name for the base OVF              |
| `stage2_publish_location_name` | ContentLibrary CRD name (`cl-xxxx`) for production              |

### 2 — Point Packer at your kubeconfig

```sh
export KUBECONFIG=$HOME/.kube/config
```

Or set `kubeconfig_path` in the vars file.

### 3 — Build the remastered ISO

```sh
make remaster
```

This runs `scripts/remaster-iso.sh` via Packer's `null` builder + `shell-local`
provisioner. The vendor ISO is downloaded once and cached in `.cache/`. On
subsequent runs the cache is validated against `source_iso_sha256`.

### 4 — Get the ISO into the content library

Two paths are supported. Choose one:

#### Option A — Upload locally with govc (recommended)

Set the govc connection vars in `linux-oracle.pkrvars.hcl`:

```hcl
govc_url      = "https://vcenter.example.com"
govc_username = "administrator@vsphere.local"
govc_password = ""      # or export PKR_VAR_govc_password="..."
govc_insecure = false   # set true for self-signed certs
```

Then run:

```sh
make upload
```

#### Option B — Import from a hosted URL

Host the ISO at an HTTPS endpoint reachable by the Supervisor cluster, then set:

```hcl
import_source_url = "https://your-server.example.com/isos/oraclelinux-9-ks.iso"
```

Packer will submit a `ContentLibraryItemImportRequest` on first run.

### 5 — Resolve resource names (optional)

```sh
make resolve
```

This runs a Packer `null` build stage that queries `kubectl` to auto-discover:

- `image_name` — matched from `import_target_image_name`
- `stage1_publish_location_name` — matched from `publish_library_name`
- `stage2_publish_location_name` — matched from `publish_library_name`

Results are written to `.build/resolved.pkrvars.hcl`, which the Makefile
automatically loads as a second `-var-file` (overriding empty defaults).

If you prefer manual resolution, skip this step and set `image_name` directly:

```sh
kubectl get virtualmachineimage -n <your-namespace>
```

### 6 — Run Stage 1 (Base OS Install)

```sh
make stage1
```

What happens:

1. A `VirtualMachine` is created booting from the ISO.
2. Anaconda runs the kickstart — installs OL9, creates the build user,
   configures cloud-init with VMware datasource, enables `vmtoolsd`.
3. The VM powers off; Packer publishes the disk as a base OVF template.

### 7 — Resolve Stage 2 image name

After Stage 1 publishes, re-run resolve to discover the base OVF's resource name:

```sh
make resolve
```

This updates `.build/resolved.pkrvars.hcl` with `stage2_image_name`.

Or set it manually:

```sh
kubectl get virtualmachineimage -n <your-namespace>
# Find the entry for the base OVF and set stage2_image_name in your vars file
```

### 8 — Run Stage 2 (Software Provisioning)

```sh
make stage2
```

What happens:

1. A `VirtualMachine` is cloned from the base OVF template.
2. `CloudInit` bootstrap is injected — the VM Operator sets `guestinfo`
   network metadata.
3. `cloud-init` configures the network; Packer connects over SSH.
4. Provisioners run (dnf update, custom scripts — edit `stage2-provision.pkr.hcl`).
5. The Ansible cleanup playbook seals the image (cloud-init clean, wipe NM
   connections, machine-id, logs, temp files, shell history).
6. The VM is published to the production content library as a golden image.

### All-in-one

```sh
# Full local-upload path: remaster → upload → stage1 → stage2
make all-local

# Full URL-import path: remaster → stage1 → stage2
make all-url
```

> **Note:** `all-local` and `all-url` do not run `make resolve` between stages.
> For fully automated pipelines, either pre-populate the CRD names manually or
> run `make resolve` between upload/stage1/stage2 as shown above.

## Finding the ISO

Browse [yum.oracle.com — Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html)
for the latest OL9 x86_64 DVD ISO and its SHA-256. Set both in your vars file:

```hcl
source_iso_url    = "https://yum.oracle.com/ISOS/OracleLinux/OL9/u5/x86_64/OracleLinux-R9-U5-x86_64-dvd.iso"
source_iso_sha256 = "<sha256-from-the-page>"
```

## Getting an OVA out

The builder publishes to a content library — it does not write an OVA file
locally. Download the published item with `govc`:

```sh
govc library.export "/<library-name>/<published-image-name>" ./oraclelinux-9.ova
```

## Customizing the build

- **Kickstart:** edit `builds/linux/oracle/9/data/ks.cfg.tpl`. Variables
  substituted at remaster time: `BUILD_USERNAME`, `BUILD_PASSWORD_ENCRYPTED`,
  `BUILD_PUBLIC_KEY`, `VM_GUEST_OS_LANGUAGE`, `VM_GUEST_OS_KEYBOARD`,
  `VM_GUEST_OS_TIMEZONE`. Run `make remaster` after changes.
- **Stage 2 provisioning:** edit the first `provisioner "shell"` block in
  `stage2-provision.pkr.hcl`. Add shell, file, or Ansible provisioner blocks
  for corporate packages, Docker, security agents, etc.
- **Image sealing:** edit `cleanup-playbook.yml` to add or remove cleanup
  tasks. The playbook runs as the final provisioner in Stage 2.
- **Cloud-init userdata:** edit `data/stage2-userdata.yaml` to customize the
  cloud-init configuration used during Stage 2 bootstrap.

## Updating to a newer Oracle Linux 9 release

1. Update `source_iso_url` and `source_iso_sha256` in your vars file.
2. Run `make remaster` — the cached ISO is replaced when the checksum changes.
3. Run `make upload` (or re-host the ISO if using the URL import path).
4. Run `make resolve` to pick up the new `image_name`.
5. Run `make stage1` then `make resolve` then `make stage2`.

## Makefile targets

| Target           | What it does                                                                |
| ---------------- | --------------------------------------------------------------------------- |
| `make init`      | `packer init` — downloads plugins                                           |
| `make remaster`  | Builds the remastered ISO (downloads vendor ISO if cache miss)              |
| `make upload`    | Uploads the remastered ISO to the content library via govc                  |
| `make resolve`   | Queries kubectl, writes `.build/resolved.pkrvars.hcl` (optional)           |
| `make stage1`    | Stage 1: ISO → base OVF template (`communicator=none`)                     |
| `make stage2`    | Stage 2: base OVF → golden image (`communicator=ssh`)                      |
| `make build`     | Runs `stage1` then `stage2`                                                 |
| `make all-local` | `remaster` → `upload` → `stage1` → `stage2`                               |
| `make all-url`   | `remaster` → `stage1` → `stage2` (Packer imports from `import_source_url`) |
| `make clean`     | Removes `.cache/` and `.build/`                                             |

The default `VAR_FILE` is `builds/linux/oracle/9/linux-oracle.pkrvars.hcl`.
Override on the command line: `make stage1 VAR_FILE=path/to/other.pkrvars.hcl`.

When `.build/resolved.pkrvars.hcl` exists, `stage1` and `stage2` load it as a
second `-var-file` (overrides values from the primary var file).

## Variable reference

See `builds/linux/oracle/9/variables.pkr.hcl` for the full set with
descriptions. Key variables:

### Shared

| Variable                    | Required | Notes                                                           |
| --------------------------- | :------: | --------------------------------------------------------------- |
| `source_iso_url`            | yes      | Upstream OL9 DVD ISO URL; passed to `remaster-iso.sh`          |
| `source_iso_sha256`         | no       | Expected SHA-256; enables smart cache validation                |
| `supervisor_namespace`      | (1)      | Falls back to current kubeconfig context's namespace            |
| `kubeconfig_path`           | no       | Falls back to `$KUBECONFIG`, then `$HOME/.kube/config`          |
| `class_name`                | yes      | `VirtualMachineClass` name                                      |
| `storage_class`             | yes      | `StorageClass` name                                             |
| `build_username`            | yes      | Created by kickstart; used for SSH in Stage 2                   |
| `build_password`            | yes      | Plaintext — used by Packer SSH                                  |
| `build_password_encrypted`  | yes      | SHA-512 hash — baked into the kickstart                         |
| `build_key`                 | no       | SSH public key injected into the kickstart                      |
| `watch_source_timeout_sec`  | no       | Default 3600s — Stage 1 needs full install time; Stage 2 needs less |

### Stage 1 — Base OS Install

| Variable                       | Required | Notes                                                        |
| ------------------------------ | :------: | ------------------------------------------------------------ |
| `image_name`                   | yes      | VirtualMachineImage resource name for the ISO (auto-resolved by `make resolve`) |
| `import_target_location_name`  | (2)      | Writable content library for ISO import                      |
| `import_target_image_name`     | (2)      | Friendly label for the ISO in the content library            |
| `import_source_url`            | (2)      | URL for cluster-side import; leave empty for govc path       |
| `publish_library_name`         | no       | Human-readable library name for auto-resolution (both stages) |
| `stage1_publish_location_name` | (3)      | ContentLibrary CRD name (`cl-xxxx`) — auto-resolved or manual |
| `stage1_publish_image_name`    | no       | Name for the base OVF; auto-generated if unset               |
| `guest_os_type`                | no       | Default `oracleLinux9_64Guest`                               |
| `iso_boot_disk_size`           | no       | Default `40Gi`                                               |

### Stage 2 — Software Provisioning

| Variable                       | Required | Notes                                                        |
| ------------------------------ | :------: | ------------------------------------------------------------ |
| `stage2_image_name`            | yes      | VirtualMachineImage for the base OVF (auto-resolved by `make resolve`) |
| `publish_library_name`         | no       | Human-readable library name for auto-resolution (both stages) |
| `stage2_publish_location_name` | (3)      | ContentLibrary CRD name (`cl-xxxx`) — auto-resolved or manual |
| `stage2_publish_image_name`    | no       | Name for the golden image; auto-generated if unset           |
| `communicator_port`            | no       | Default `22`                                                 |
| `communicator_timeout`         | no       | Default `30m`                                                |

(1) Optional only if your kubeconfig context already targets the right namespace.
(2) Required on first run; leave empty once the ISO is in the library.
(3) Required to publish. Can be auto-resolved via `make resolve`.

## Troubleshooting

### General

- **`packer validate` complains about an unknown plugin:** run `make init` first.
- **Build times out waiting for the source VM:** check
  `kubectl describe vm -n <namespace> <source_name>`. Common causes: invalid
  `class_name`, `storage_class`, or `image_name`; ISO import not yet complete.
- **SSH credentials rejected:** `build_password` and `build_password_encrypted`
  must be consistent (same password, different forms). Regenerate with
  `mkpasswd -m sha-512` and update both vars, then re-run `make remaster`.
- **Import times out:** increase `watch_import_timeout_sec`. Large ISOs over a
  slow link may need several minutes.

### Stage 1

- **Anaconda fails or VM never powers off:** the kickstart may have an error.
  Attach to the VM console in vSphere Client and check the Anaconda log.
  The kickstart uses `poweroff --eject` — if the VM stays running, Anaconda
  is likely hung (check for `--activate` on the network line causing a DHCP
  hang).
- **Stage 1 build completes but no OVF in the library:** verify
  `stage1_publish_location_name` is set to a valid, writable ContentLibrary
  CRD name. Check with `kubectl get contentlibrary -n <namespace>`.

### Stage 2

- **NoBootstrapStatus / network never comes up:** this means the bootstrap
  block was stripped. Verify the `stage2_image_name` points to an OVF image
  (Stage 1 output), not a raw ISO.
- **Packer cannot SSH:** the Supervisor namespace network must be reachable
  from the Packer host. Check the VM IP with
  `kubectl get vm -n <namespace> -o jsonpath='{.status.network.primaryIP4}'`
  and try to SSH manually.
- **Ansible cleanup playbook fails:** ensure `ansible-playbook` is installed
  on the Packer host. The Ansible provisioner runs locally, not on the target.
- **Publishing fails:** the namespace must have publish permission on the target
  content library. Check `kubectl describe contentlibrary` and the library
  publish permissions in vSphere.

### Auto-resolution (`make resolve`)

- **"Missing required tools: jq":** install jq (`brew install jq` / `dnf install jq`).
- **"No VirtualMachineImage matching ...":** the Supervisor may not have synced
  yet. Wait a minute and re-run `make resolve`. Also check that
  `import_target_image_name` or `stage1_publish_image_name` matches what the
  Supervisor assigned.
- **"No ContentLibrary matching ...":** the match checks `.status.name`,
  `.spec.name`, and `.metadata.name`. Run
  `kubectl get contentlibrary -n <namespace> -o yaml` to see available fields
  and adjust `publish_library_name`.

## References

- Builder docs: <https://developer.hashicorp.com/packer/integrations/vmware/vsphere/latest/components/builder/vsphere-supervisor>
- Upstream `vsphere-iso` example this is modeled after:
  <https://github.com/vmware/packer-examples-for-vsphere/tree/develop/builds/linux/oracle/9>
