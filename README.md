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
| Bootstrap                 | Kickstart over HTTP or a CD-ROM              | cloud-init bootstrap data on the source VM            |
| Output                    | Template, content-library item, or OVF export | Published image in a content library (downloadable as OVA) |

Practically: there is no kickstart, no boot command, no HTTP server. You bring
a pre-built Oracle Linux 9 cloud image, the builder clones it, cloud-init seeds
the build user, Packer SSHes in to run provisioners, and the customized image
is published back to a content library.

## Repository layout

```
.
├── README.md
└── builds/
    └── linux/
        └── oracle/
            └── 9/
                ├── linux-oracle.pkr.hcl              # Builder + build blocks
                ├── linux-oracle.pkrvars.hcl.example  # Sample input values
                ├── variables.pkr.hcl                 # Variable declarations
                └── data/
                    └── cloud-init.pkrtpl.hcl         # cloud-init user-data template
```

## Prerequisites

You will need:

- A vSphere environment with **vSphere with Tanzu / Supervisor** enabled.
- A **Supervisor namespace** you can deploy into. You will need its name.
- A **VirtualMachineClass** that fits your hardware needs
  (`kubectl get virtualmachineclass`).
- A **StorageClass** assigned to your namespace
  (`kubectl get storageclass`).
- A **content library** linked to the Supervisor namespace that contains the
  Oracle Linux 9 source image. See [Preparing the source image](#preparing-the-source-image)
  below for how to get one in.
- A **target content library** the Supervisor namespace is allowed to publish
  to. This is where the finished image lands and where you download the OVA
  from.
- A **kubeconfig** that authenticates to the Supervisor cluster and is set to
  the namespace above as its current context. Verify with `kubectl get ns`.
- **Packer 1.15.0+** locally, with the `github.com/vmware/vsphere` plugin
  v2.1.1+ (Packer installs this for you on `packer init`).
- **Network access from your Packer host to the source VM over SSH.** The
  source VM is created inside the Supervisor namespace and Packer needs to
  reach its IP/SSH port directly. If the namespace network is not routable
  from your host, run Packer from a jump host that is.
- An **SHA-512 hashed password** for the build user. Generate one with:
  ```
  mkpasswd -m sha-512
  # or
  openssl passwd -6
  ```

## Preparing the source image

The `vsphere-supervisor` builder needs a **`VirtualMachineImage`** in the
Supervisor namespace's content library to deploy from. Because Oracle does
not publish a first-party OL9 OVA for vSphere, this repo uses a **custom
ISO with a kickstart baked in**:

```
Oracle Linux 9 DVD ISO  ──►  scripts/remaster-iso.sh  ──►  custom ISO in content library
                                                               │
                                                          packer build
                                                               │
                                                        Anaconda installs OL9
                                                        (kickstart, unattended)
                                                               │
                                                         VM reboots → SSH ready
                                                               │
                                                      Packer runs provisioners
                                                               │
                                                    VirtualMachinePublishRequest
                                                               │
                                                           OVF in library
```

### Step 1 — Find your writable content library

Each Supervisor namespace binds to one or more `ContentLibrary` objects.
Find them with:

```sh
kubectl get contentlibrary -n <your-namespace>
```

You need one that is **writable** from the namespace (check
`spec.writable: true` in the output). That library name goes into two
places:
- `GOVC_LIBRARY` in the remaster script (upload destination for the custom ISO)
- `publish_location_name` in your `*.pkrvars.hcl` (publish destination for the final image)

### Step 2 — Get the Oracle Linux 9 ISO URL

Browse [yum.oracle.com / Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html)
for the most recent OL9 x86_64 DVD.  As of this writing the latest is
Update 7:

```
https://yum.oracle.com/ISOS/OracleLinux/OL9/u7/x86_64/OracleLinux-R9-U7-x86_64-dvd.iso
```

Copy the matching SHA-256 from that page — you can pass it to the
remaster script for verification.

### Step 3 — Run `scripts/remaster-iso.sh`

The script is generic — it takes any RHEL-family install ISO, injects a
rendered kickstart, patches the EFI and BIOS bootloaders, and writes a
custom ISO file. It does **not** upload to vSphere; Packer handles that
via `import_source_url` in the next step.

**Required tools** (`brew install xorriso gettext && brew link --force gettext`):
`curl`, `xorriso`, `envsubst`

```sh
# Kickstart credentials — must match build_* in your *.pkrvars.hcl
export BUILD_USERNAME="packer"
export BUILD_PASSWORD_ENCRYPTED='$6$rounds=4096$...'   # from: mkpasswd -m sha-512
export BUILD_PUBLIC_KEY=""          # optional SSH public key

# Guest locale baked into the kickstart
export VM_GUEST_OS_LANGUAGE="en_US"
export VM_GUEST_OS_KEYBOARD="us"
export VM_GUEST_OS_TIMEZONE="UTC"

# Source ISO
export SOURCE_ISO_URL="https://yum.oracle.com/ISOS/OracleLinux/OL9/u7/x86_64/OracleLinux-R9-U7-x86_64-dvd.iso"
export SOURCE_ISO_SHA256="<sha256-from-yum.oracle.com>"  # leave empty to skip

# Path to the kickstart template for this build
export KS_FILE="builds/linux/oracle/9/data/ks.cfg.tpl"

# Where to write the remastered ISO (defaults to .build/<iso-name>-ks.iso)
export OUTPUT_ISO=".build/oraclelinux-9-ks.iso"

./scripts/remaster-iso.sh
```

The downloaded vendor ISO is cached in `.cache/` — re-runs skip the download.

### Step 4 — Host the custom ISO and configure `import_source_url`

Packer's `vsphere-supervisor` builder will fetch the ISO and import it into
the content library automatically using `import_source_url`. That URL must
be reachable by the **Supervisor cluster** (not just the Packer host).

Host `.build/oraclelinux-9-ks.iso` somewhere the cluster can reach — an
internal web server, an S3 bucket, etc. — then set these vars in your
`linux-oracle.pkrvars.hcl`:

```hcl
import_source_url           = "https://your-server.example.com/isos/oraclelinux-9-ks.iso"
import_target_location_name = "oracle-linux-source"   # writable ContentLibrary name
import_target_image_type    = "iso"
import_target_image_name    = "oraclelinux-9-ks"
image_name                  = "oraclelinux-9-ks"      # must match import_target_image_name
```

On first run Packer creates a `ContentLibraryItemImportRequest` in your
namespace and waits for it to complete before deploying the source VM. On
subsequent runs with `clean_imported_image = false` the import is skipped
if the item already exists and `import_source_url` can be left empty (set
only `image_name`).

### Step 5 — Verify the image is visible to your namespace

After the first `packer build` completes the import step:

```sh
kubectl get virtualmachineimage -n <your-namespace>
```

You should see an entry matching `import_target_image_name`.

### Updating to a newer Oracle Linux 9 release

Update `SOURCE_ISO_URL` and `SOURCE_ISO_SHA256`, re-run
`scripts/remaster-iso.sh`, re-host the new ISO, update
`import_source_url`, and run `packer build`.

## Usage

1. **Clone and enter the build directory:**

   ```sh
   cd builds/linux/oracle/9
   ```

2. **Copy the example variables file and edit it:**

   ```sh
   cp linux-oracle.pkrvars.hcl.example linux-oracle.pkrvars.hcl
   ```

   Open `linux-oracle.pkrvars.hcl` and set at least:
   - `supervisor_namespace`
   - `image_name` (the source `VirtualMachineImage`)
   - `class_name` (a `VirtualMachineClass`)
   - `storage_class` (a `StorageClass`)
   - `publish_location_name` (a content library to publish to)
   - `build_username` / `build_password` / `build_password_encrypted`

3. **Point Packer at your kubeconfig:**

   Either set `kubeconfig_path` in the vars file, or:

   ```sh
   export KUBECONFIG=$HOME/.kube/config
   ```

   The current context's namespace will be used if `supervisor_namespace`
   is left empty.

4. **Initialize plugins:**

   ```sh
   packer init .
   ```

5. **Validate:**

   ```sh
   packer validate -var-file=linux-oracle.pkrvars.hcl .
   ```

6. **Build:**

   ```sh
   packer build -var-file=linux-oracle.pkrvars.hcl .
   ```

   What happens during the build:
   1. Packer renders `data/cloud-init.pkrtpl.hcl` to a local file under
      `.bootstrap/`.
   2. The builder creates a `VirtualMachine` in your Supervisor namespace
      using `image_name`, `class_name`, and `storage_class`, attaching the
      cloud-init bootstrap data.
   3. cloud-init creates the build user, sets the SSH key/password, and
      installs `open-vm-tools`.
   4. Packer SSHes into the VM and runs the provisioners (a `dnf update`
      and a `vm-build-info` stamp by default — replace these with your own).
   5. The customized VM is published to `publish_location_name` as an OVF
      template. You can then download it from that content library as an
      OVA via the vSphere Client or `govc`.

## Getting an OVA out

The `vsphere-supervisor` builder publishes the resulting image into a
content library; it does not write an OVA file to your local disk
directly. To get an OVA on disk, download the published item from the
target content library, e.g. with `govc`:

```sh
govc library.export "/<library-name>/<published-image-name>" ./oraclelinux-9.ova
```

(Replace `<library-name>` with your `publish_location_name` and
`<published-image-name>` with the value of `publish_image_name` —
or the auto-generated name printed at the end of the build.)

## Customizing what gets installed

- **cloud-init seed:** edit `data/cloud-init.pkrtpl.hcl`. This is what
  shapes the source VM at first boot (user, SSH key, packages,
  hostname, locale).
- **In-guest provisioning:** edit the `provisioner "shell"` block in
  `linux-oracle.pkr.hcl`. To use Ansible instead, replace it with a
  `provisioner "ansible"` block — the upstream
  [example's `ansible/`](https://github.com/vmware/packer-examples-for-vsphere/tree/develop/ansible)
  directory drops in unchanged.
- **Extra packages:** add to `additional_packages` in your
  `*.pkrvars.hcl` file. They are appended to the cloud-init `packages`
  list.

## Variable reference

See `builds/linux/oracle/9/variables.pkr.hcl` for the full set, with
descriptions. The most important ones:

| Variable                  | Required | Notes                                                                  |
| ------------------------- | :------: | ---------------------------------------------------------------------- |
| `supervisor_namespace`    | (1)      | Falls back to current kubeconfig context's namespace                   |
| `kubeconfig_path`         | no       | Falls back to `$KUBECONFIG`, then `$HOME/.kube/config`                 |
| `image_name`              | yes      | Source `VirtualMachineImage` name                                      |
| `class_name`              | yes      | `VirtualMachineClass` name                                             |
| `storage_class`           | yes      | `StorageClass` name                                                    |
| `publish_location_name`   | (2)      | Target ContentLibrary; leave empty to skip publishing                  |
| `bootstrap_provider`      | no       | `CloudInit` (default), `Sysprep`, or `vAppConfig`                      |
| `build_username`          | yes      | Created by cloud-init; used for SSH                                    |
| `build_password`          | yes      | Plaintext, used for SSH                                                |
| `build_password_encrypted`| yes      | SHA-512 hash, seeded into cloud-init                                   |

(1) Optional only if your kubeconfig context already targets the right
namespace. (2) Required to actually publish the resulting image.

## Troubleshooting

- **`packer validate` complains about an unknown plugin or builder:**
  run `packer init .` first.
- **Build times out waiting for the source VM:** check
  `kubectl describe vm -n <namespace> <source_name>`. Common causes are
  invalid `class_name`, `storage_class`, or `image_name` values.
- **Packer cannot SSH:** the Supervisor namespace network must be
  reachable from where Packer runs. Verify with
  `kubectl get vm -n <namespace> <source_name> -o jsonpath='{.status.network.primaryIP4}'`
  and try to SSH from the same host.
- **cloud-init didn't apply your config:** confirm the source image
  ships with cloud-init enabled (most cloud images do; some "OVA from
  ISO install" images do not). Check
  `/var/log/cloud-init.log` on the source VM.
- **Publishing fails:** the namespace must be permitted to publish to
  the named content library. Check
  `kubectl describe contentlibrary` and the namespace's
  `ContentSourceBinding` / library publish permissions in vSphere.

## References

- Builder docs: <https://developer.hashicorp.com/packer/integrations/vmware/vsphere/latest/components/builder/vsphere-supervisor>
- Upstream `vsphere-iso` example this is modeled after:
  <https://github.com/vmware/packer-examples-for-vsphere/tree/develop/builds/linux/oracle/9>
