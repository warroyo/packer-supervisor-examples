# Packer for Oracle Linux 9 on vSphere Supervisor

A sample Packer configuration that builds an Oracle Linux 9 image for VMware
vSphere using the [`vsphere-supervisor`](https://developer.hashicorp.com/packer/integrations/vmware/vsphere/latest/components/builder/vsphere-supervisor)
builder.

The structure mirrors the upstream
[vmware/packer-examples-for-vsphere](https://github.com/vmware/packer-examples-for-vsphere/tree/develop/builds/linux/oracle/9)
example, but the `vsphere-iso` builder has been replaced with
`vsphere-supervisor`.

## How this differs from the `vsphere-iso` example

The two builders take fundamentally different approaches:

| Concern                   | `vsphere-iso`                                | `vsphere-supervisor`                                  |
| ------------------------- | -------------------------------------------- | ----------------------------------------------------- |
| Install method            | Boots an ISO and runs a kickstart            | Deploys an existing VM image from a content library   |
| Authentication            | vCenter username/password                    | A kubeconfig pointing at the Supervisor cluster       |
| Placement                 | datacenter / cluster / host / datastore      | Supervisor namespace + VM class + StorageClass        |
| Source media              | ISO file on a datastore or content library   | A `VirtualMachineImage` published to the namespace    |
| Bootstrap                 | Kickstart over HTTP or a CD-ROM              | Kickstart baked into a remastered ISO                 |
| Output                    | Template, content-library item, or OVF export | Published image in a content library (downloadable as OVA) |

There is no cloud-init bootstrap, no HTTP server, no boot command. A custom
ISO with the kickstart baked in is built locally, imported into a content
library by Packer, and used to install OL9 unattended. After the first reboot
Packer SSHes in and runs provisioners, then publishes the result.

## Repository layout

```
.
├── Makefile                                          # Build orchestration
├── README.md
├── builds/
│   └── linux/
│       └── oracle/
│           └── 9/
│               ├── linux-oracle.pkr.hcl              # vsphere-supervisor builder + build block
│               ├── remaster.pkr.hcl                  # Remaster-ISO build stage (null + shell-local)
│               ├── linux-oracle.pkrvars.hcl.example  # Sample input values — copy and edit
│               ├── variables.pkr.hcl                 # Variable declarations
│               └── data/
│                   └── ks.cfg.tpl                    # Kickstart template (rendered by remaster-iso.sh)
└── scripts/
    └── remaster-iso.sh                               # ISO remastering script
```

## Prerequisites

- A vSphere environment with **vSphere with Tanzu / Supervisor** enabled.
- A **Supervisor namespace** you can deploy into.
- A **VirtualMachineClass** (`kubectl get virtualmachineclass`).
- A **StorageClass** assigned to your namespace (`kubectl get storageclass`).
- A **writable content library** linked to the namespace — used to hold the
  custom ISO during import and to publish the finished image.
- A **kubeconfig** targeting the Supervisor cluster and namespace.
  Verify with `kubectl get ns`.
- **Packer 1.15.0+** with the `github.com/vmware/vsphere` plugin v2.1.1+
  (installed automatically by `packer init` / `make init`).
- **Remaster tools** (required to build the custom ISO):
  ```sh
  # macOS
  brew install xorriso gettext && brew link --force gettext
  # Linux
  dnf install xorriso gettext   # or apt install xorriso gettext
  ```
- **Network access from your Packer host to the source VM over SSH.** The VM
  is created inside the Supervisor namespace; if the namespace network is not
  routable from your host, run Packer from a jump host that is.
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
  host at a URL reachable by the Supervisor cluster
        │
  packer build  (vsphere-supervisor)
        │
  ContentLibraryItemImportRequest  ── imports ISO into content library
        │
  VirtualMachine created, boots from ISO
        │
  Anaconda runs kickstart (unattended OL9 install + build user + SSH)
        │
  VM reboots → SSH ready
        │
  Packer provisioners run (dnf update, build info stamp, …)
        │
  VirtualMachinePublishRequest
        │
  OVF template in content library  ──► downloadable as OVA
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
| `source_iso_sha256`         | SHA-256 of the ISO (optional but recommended)                      |
| `supervisor_namespace`      | Your Supervisor namespace name                                     |
| `image_name`                | Must match `import_target_image_name`                              |
| `import_target_location_name` | Writable content library for the ISO import                      |
| `import_target_image_name`  | Name for the imported ISO library item                             |
| `import_source_url`         | URL where you host `.build/oraclelinux-9-ks.iso` (see [Hosting the ISO](#hosting-the-iso)) |
| `class_name`                | VirtualMachineClass name                                           |
| `storage_class`             | StorageClass name                                                  |
| `publish_location_name`     | Target content library for the finished image                      |
| `build_username`            | Build user created by the kickstart                                |
| `build_password`            | Plaintext — used by Packer SSH                                     |
| `build_password_encrypted`  | SHA-512 hash — baked into the kickstart                            |

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
provisioner.  The vendor ISO is downloaded once and cached in `.cache/`.  On
subsequent runs the cache is validated against `source_iso_sha256` — the
download is skipped when the checksum matches and automatically re-triggered on
mismatch (or when `source_iso_sha256` is unset).

The remastered ISO is written to `.build/oraclelinux-9-ks.iso`.

### 4 — Host the custom ISO {#hosting-the-iso}

The Supervisor cluster (not just the Packer host) must be able to fetch the
ISO. Serve `.build/oraclelinux-9-ks.iso` from an internal web server, object
storage bucket, or any HTTPS endpoint the cluster can reach, then set
`import_source_url` in your vars file to that URL.

### 5 — Run the full build

```sh
make build
```

Or build both stages in one command:

```sh
make all   # runs: make remaster && make build
```

What happens during `make build`:

1. Packer validates the plugin (`packer init`).
2. The builder submits a `ContentLibraryItemImportRequest` in your namespace
   to import the ISO from `import_source_url` into the content library.
3. A `VirtualMachine` is created booting from the imported ISO.
4. Anaconda runs the embedded kickstart — installs OL9, creates the build user
   with the encrypted password and optional SSH key, enables SSH.
5. The VM reboots; Packer waits up to `watch_source_timeout_sec` for SSH.
6. Provisioners run (`dnf update`, write `/etc/vm-build-info`, …).
7. A `VirtualMachinePublishRequest` publishes the VM to `publish_location_name`
   as an OVF template.

### 6 — Verify the source image (first run only)

After the first build's import step completes:

```sh
kubectl get virtualmachineimage -n <your-namespace>
```

You should see an entry matching `import_target_image_name`. On subsequent runs
with `clean_imported_image = false` Packer skips the import when the item
already exists — you can then leave `import_source_url` empty and set only
`image_name`.

## Finding the ISO

Browse [yum.oracle.com — Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html)
for the latest OL9 x86_64 DVD ISO and its SHA-256.  Set both in your vars file:

```hcl
source_iso_url    = "https://yum.oracle.com/ISOS/OracleLinux/OL9/u5/x86_64/OracleLinux-R9-U5-x86_64-dvd.iso"
source_iso_sha256 = "<sha256-from-the-page>"
```

## Getting an OVA out

The builder publishes to a content library — it does not write an OVA file
locally. Download the published item with `govc`:

```sh
govc library.export "/<publish_location_name>/<published-image-name>" ./oraclelinux-9.ova
```

`published-image-name` is `publish_image_name` from your vars file, or the
auto-generated name printed at the end of the build.

## Customizing the build

- **Kickstart:** edit `builds/linux/oracle/9/data/ks.cfg.tpl`. Variables
  substituted at remaster time: `BUILD_USERNAME`, `BUILD_PASSWORD_ENCRYPTED`,
  `BUILD_PUBLIC_KEY`, `VM_GUEST_OS_LANGUAGE`, `VM_GUEST_OS_KEYBOARD`,
  `VM_GUEST_OS_TIMEZONE`. Run `make remaster` after changes.
- **In-guest provisioning:** edit the `provisioner "shell"` block in
  `linux-oracle.pkr.hcl`. Replace or extend with Ansible, file, or other
  provisioner blocks.

## Updating to a newer Oracle Linux 9 release

1. Update `source_iso_url` and `source_iso_sha256` in your vars file.
2. Run `make remaster` — the cached ISO is replaced when the checksum changes.
3. Re-host `.build/oraclelinux-9-ks.iso` (if the path/URL changed, update `import_source_url`).
4. Run `make build`.

## Makefile targets

| Target         | What it does                                                    |
| -------------- | --------------------------------------------------------------- |
| `make init`    | `packer init` — downloads plugins                               |
| `make remaster`| Builds the remastered ISO via the `remaster-iso` packer build   |
| `make build`   | Runs the `vsphere-supervisor` packer build                      |
| `make all`     | `make remaster` then `make build`                               |
| `make clean`   | Removes `.cache/` and `.build/`                                 |

The default `VAR_FILE` is `builds/linux/oracle/9/linux-oracle.pkrvars.hcl`.
Override with `make build VAR_FILE=path/to/other.pkrvars.hcl`.

## Variable reference

See `builds/linux/oracle/9/variables.pkr.hcl` for the full set with
descriptions. Key variables:

| Variable                    | Required | Notes                                                           |
| --------------------------- | :------: | --------------------------------------------------------------- |
| `source_iso_url`            | yes      | Upstream OL9 DVD ISO URL; passed to `remaster-iso.sh`          |
| `source_iso_sha256`         | no       | Expected SHA-256; enables smart cache validation                |
| `supervisor_namespace`      | (1)      | Falls back to current kubeconfig context's namespace            |
| `kubeconfig_path`           | no       | Falls back to `$KUBECONFIG`, then `$HOME/.kube/config`          |
| `image_name`                | yes      | Source `VirtualMachineImage` name (match `import_target_image_name`) |
| `class_name`                | yes      | `VirtualMachineClass` name                                      |
| `storage_class`             | yes      | `StorageClass` name                                             |
| `import_source_url`         | (2)      | URL serving the remastered ISO; leave empty after first import  |
| `import_target_location_name` | (2)   | Writable ContentLibrary for ISO import                          |
| `import_target_image_name`  | (2)      | Name for the imported ISO item                                  |
| `publish_location_name`     | (3)      | Target ContentLibrary for the finished image; skip if empty     |
| `build_username`            | yes      | Created by kickstart; used for SSH                              |
| `build_password`            | yes      | Plaintext — used by Packer SSH                                  |
| `build_password_encrypted`  | yes      | SHA-512 hash — baked into the kickstart                         |
| `build_key`                 | no       | SSH public key injected into the kickstart                      |
| `watch_source_timeout_sec`  | no       | Seconds to wait for SSH (ISO boot + install + reboot; default 3600) |

(1) Optional only if your kubeconfig context already targets the right namespace.
(2) Required on first run; leave empty once the image is in the library.
(3) Required to publish the finished image.

## Troubleshooting

- **`packer validate` complains about an unknown plugin:** run `make init` first.
- **Build times out waiting for the source VM:** check
  `kubectl describe vm -n <namespace> <source_name>`. Common causes: invalid
  `class_name`, `storage_class`, or `image_name`; ISO import not yet complete.
- **Packer cannot SSH:** the Supervisor namespace network must be reachable
  from the Packer host. Check the VM IP with
  `kubectl get vm -n <namespace> <source_name> -o jsonpath='{.status.network.primaryIP4}'`
  and try to SSH manually.
- **Anaconda fails or VM reboots without installing:** the kickstart may have
  an error. Attach to the VM console in vSphere Client and check the Anaconda
  log or the error screen.
- **SSH credentials rejected:** `build_password` and `build_password_encrypted`
  must be consistent (same password, different forms). Regenerate with
  `mkpasswd -m sha-512` and update both vars, then re-run `make remaster`.
- **Import times out:** increase `watch_import_timeout_sec`. Large ISOs over a
  slow link may need several minutes.
- **Publishing fails:** the namespace must have publish permission on the target
  content library. Check `kubectl describe contentlibrary` and the library
  publish permissions in vSphere.

## References

- Builder docs: <https://developer.hashicorp.com/packer/integrations/vmware/vsphere/latest/components/builder/vsphere-supervisor>
- Upstream `vsphere-iso` example this is modeled after:
  <https://github.com/vmware/packer-examples-for-vsphere/tree/develop/builds/linux/oracle/9>
