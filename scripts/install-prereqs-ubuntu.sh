#!/usr/bin/env bash
# scripts/install-prereqs-ubuntu.sh
#
# Installs all tools required to run the packer-supervisor build pipeline
# on Ubuntu (22.04 / 24.04).
#
# Run as a user with sudo access:
#   bash scripts/install-prereqs-ubuntu.sh
#
# What gets installed:
#   Required:  packer, ansible, xorriso, gettext, kubectl, jq
#   Optional:  govc  (set INSTALL_GOVC=true to include)
#
# Environment variables:
#   PACKER_VERSION   Override Packer version (default: latest from HashiCorp repo)
#   GOVC_VERSION     Override govc version    (default: latest GitHub release)
#   INSTALL_GOVC     Set to "true" to install govc (default: false)

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || die "This script targets Linux (Ubuntu). Use Homebrew on macOS."

INSTALL_GOVC="${INSTALL_GOVC:-false}"
GOVC_VERSION="${GOVC_VERSION:-}"

# ── apt prerequisites ─────────────────────────────────────────────────────────

log "Updating apt cache..."
sudo apt-get update -qq

log "Installing required packages: gnupg curl software-properties-common xorriso gettext-base jq..."
sudo apt-get install -y -qq \
  gnupg \
  curl \
  software-properties-common \
  xorriso \
  gettext-base \
  jq

# ── Ansible (official PPA) ────────────────────────────────────────────────────

if command -v ansible >/dev/null 2>&1; then
  log "Ansible already installed: $(ansible --version | head -1). Skipping."
else
  log "Adding Ansible PPA..."
  sudo add-apt-repository -y ppa:ansible/ansible
  sudo apt-get update -qq
  log "Installing Ansible..."
  sudo apt-get install -y -qq ansible
fi

# ── Packer (HashiCorp apt repo) ───────────────────────────────────────────────

if command -v packer >/dev/null 2>&1 && [[ -z "${PACKER_VERSION:-}" ]]; then
  log "Packer already installed: $(packer version | head -1). Skipping."
else
  log "Adding HashiCorp apt repository..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  sudo apt-get update -qq

  if [[ -n "${PACKER_VERSION:-}" ]]; then
    log "Installing Packer ${PACKER_VERSION}..."
    sudo apt-get install -y -qq "packer=${PACKER_VERSION}"
  else
    log "Installing latest Packer..."
    sudo apt-get install -y -qq packer
  fi
fi

# ── kubectl ───────────────────────────────────────────────────────────────────

if command -v kubectl >/dev/null 2>&1; then
  log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client). Skipping."
else
  log "Adding Kubernetes apt repository..."
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

  sudo apt-get update -qq
  log "Installing kubectl..."
  sudo apt-get install -y -qq kubectl
fi

# ── govc (optional) ───────────────────────────────────────────────────────────

if [[ "${INSTALL_GOVC}" == "true" ]]; then
  if command -v govc >/dev/null 2>&1 && [[ -z "${GOVC_VERSION:-}" ]]; then
    log "govc already installed: $(govc version). Skipping."
  else
    if [[ -z "${GOVC_VERSION:-}" ]]; then
      log "Fetching latest govc release tag..."
      GOVC_VERSION=$(curl -fsSL \
        https://api.github.com/repos/vmware/govmomi/releases/latest \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
    fi
    log "Installing govc ${GOVC_VERSION}..."
    curl -fsSL \
      "https://github.com/vmware/govmomi/releases/download/v${GOVC_VERSION}/govc_Linux_x86_64.tar.gz" \
      | sudo tar -xz -C /usr/local/bin govc
    sudo chmod +x /usr/local/bin/govc
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

log "All prerequisites installed."
echo ""
echo "  packer:    $(packer version | head -1)"
echo "  ansible:   $(ansible --version | head -1)"
echo "  xorriso:   $(xorriso --version 2>&1 | head -1)"
echo "  jq:        $(jq --version)"
echo "  kubectl:   $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1)"
if [[ "${INSTALL_GOVC}" == "true" ]] && command -v govc >/dev/null 2>&1; then
  echo "  govc:      $(govc version)"
fi
echo ""
echo "Next: run 'make init' to download Packer plugins."
