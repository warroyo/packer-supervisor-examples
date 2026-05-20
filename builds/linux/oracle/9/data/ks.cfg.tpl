# Oracle Linux 9 Kickstart
# Rendered by scripts/remaster-iso.sh using envsubst.
# Variables substituted at render time: BUILD_USERNAME, BUILD_PASSWORD_ENCRYPTED,
# BUILD_PUBLIC_KEY, VM_GUEST_OS_LANGUAGE, VM_GUEST_OS_KEYBOARD, VM_GUEST_OS_TIMEZONE.

### Install from the attached CD-ROM.
cdrom

### Text mode installation.
text

### Accept the EULA.
eula --agreed

### Language / keyboard / timezone.
lang ${VM_GUEST_OS_LANGUAGE}
keyboard ${VM_GUEST_OS_KEYBOARD}
timezone ${VM_GUEST_OS_TIMEZONE} --isUtc

### Network — DHCP on all interfaces; SSH firewall rule enabled.
### OMIT --activate so Anaconda does not hang searching for DHCP during offline install.
network --bootproto=dhcp --onboot=yes
firewall --enabled --ssh

### Lock root, create build user with wheel membership.
rootpw --lock
user --name=${BUILD_USERNAME} --iscrypted --password=${BUILD_PASSWORD_ENCRYPTED} --groups=wheel

### Authentication.
authselect select sssd

### SELinux enforcing.
selinux --enforcing

### Bootloader.
bootloader --location=mbr --append="crashkernel=auto"

### Disk partitioning — LVM auto layout, wipe all existing partitions.
clearpart --all --initlabel
autopart --type=lvm

### Do not configure a graphical interface.
skipx

### Services to enable on the installed system.
services --enabled=NetworkManager,sshd

### Package selection.
%packages --ignoremissing --excludedocs
@core
open-vm-tools
cloud-init
sudo
perl
-iwl*firmware
%end

### Post-install commands.
%post --erroronfail
# Passwordless sudo for the build user.
echo "${BUILD_USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${BUILD_USERNAME}
chmod 440 /etc/sudoers.d/${BUILD_USERNAME}
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers

# Inject SSH public key when one was provided at remaster time.
if [ -n "${BUILD_PUBLIC_KEY}" ]; then
  BUILD_HOME=$(getent passwd "${BUILD_USERNAME}" | cut -d: -f6)
  mkdir -p "${BUILD_HOME}/.ssh"
  chmod 700 "${BUILD_HOME}/.ssh"
  printf '%s\n' "${BUILD_PUBLIC_KEY}" >> "${BUILD_HOME}/.ssh/authorized_keys"
  chmod 600 "${BUILD_HOME}/.ssh/authorized_keys"
  chown -R "${BUILD_USERNAME}:${BUILD_USERNAME}" "${BUILD_HOME}/.ssh"
fi

# Allow password authentication so Packer can SSH in with build_password.
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Clear temporary network files created by Anaconda.
rm -f /etc/NetworkManager/system-connections/*.nmconnection

# Configure cloud-init to use VMware backdoor datasource exclusively.
cat > /etc/cloud/cloud.cfg.d/99-vmware-datasource.cfg <<CLOUDCFG
datasource_list: [ VMware, OVF, None ]
CLOUDCFG

# Enable vmtoolsd and cloud-init services.
systemctl enable vmtoolsd
systemctl enable cloud-init

# Wipe machine ID for clean template cloning.
truncate -s 0 /etc/machine-id
%end

### Power off when install is complete so Packer detects build completion.
poweroff
