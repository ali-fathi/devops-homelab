#!/usr/bin/env bash
#
# install-tools.sh — Reproducible operator workstation tool installer
#
# Installs the CLI toolkit required to operate the homelab from a fresh machine.
# Detects the OS, uses package managers where possible, and falls back to
# GitHub releases for tools that are too new for system repos.
#
# USAGE:
#   ./scripts/install-tools.sh                 # Install everything
#   ./scripts/install-tools.sh --check         # Check installed versions only
#   ./scripts/install-tools.sh --tool helm     # Install a single tool
#   ./scripts/install-tools.sh -h              # Help
#
# ENVIRONMENT OVERRIDES:
#   KUBECTL_VERSION, HELM_VERSION, TERRAFORM_VERSION, ARGOCD_VERSION,
#   KUSTOMIZE_VERSION, KUBESEAL_VERSION, K9S_VERSION, YQ_VERSION
#
# PREREQUISITES:
#   - macOS: Homebrew (brew)
#   - Linux: apt (Debian/Ubuntu) or download from GitHub
#
# LEARNING NOTES:
#   - Idempotency: running twice must be safe (skip if already installed)
#   - OS detection: uname -s returns Darwin (macOS) or Linux
#   - Version pinning: default versions in CONFIG, override via env vars
#   - Fallback strategy: brew/apt first, GitHub releases as fallback

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────
# Default versions (pin these for reproducibility)
# Override any via environment variables, e.g. KUBECTL_VERSION=v1.30.3

KUBECTL_VERSION="${KUBECTL_VERSION:-v1.30.3}"
HELM_VERSION="${HELM_VERSION:-v3.15.4}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.9.8}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.12.3}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.4.3}"
KUBESEAL_VERSION="${KUBESEAL_VERSION:-v0.27.1}"
K9S_VERSION="${K9S_VERSION:-v0.32.7}"
YQ_VERSION="${YQ_VERSION:-v4.44.3}"

# Where standalone binaries go (if not using package manager)
LOCAL_BIN="${HOME}/.local/bin"

# ─── Colors ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Helper Functions ───────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

check_command() {
  command -v "$1" &>/dev/null
}

# ─── OS / Package Manager Detection ────────────────────────────────────

detect_os() {
  if is_macos; then
    echo "macos"
  elif is_linux; then
    echo "linux"
  else
    log_error "Unsupported OS: $(uname -s)"
    exit 1
  fi
}

ensure_pkg_manager() {
  local os="$1"

  if [[ "$os" == "macos" ]]; then
    if ! check_command brew; then
      log_error "Homebrew not found. Install it: https://brew.sh"
      log_info "Or run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      exit 1
    fi
    log_ok "Package manager: Homebrew ($(brew --version | head -1))"
  else
    if ! check_command apt-get; then
      log_error "apt-get not found. This script currently supports Debian/Ubuntu."
      exit 1
    fi
    log_ok "Package manager: apt ($(apt-get --version | head -1))"
  fi
}

# ─── Installer: brew (macOS) ───────────────────────────────────────────

install_with_brew() {
  local formula="$1"
  if check_command "$formula"; then
    local v
    v=$("$formula" --version 2>/dev/null | head -1) || v="installed"
    log_ok "$formula already installed: $v"
    return 0
  fi
  log_info "Installing $formula via Homebrew..."
  brew install "$formula"
  log_ok "$formula installed"
}

# ─── Installer: apt (Linux) ────────────────────────────────────────────

install_with_apt() {
  local package="$1"
  local binary="${2:-$1}"
  if check_command "$binary"; then
    log_ok "$binary already installed"
    return 0
  fi
  log_info "Installing $package via apt..."
  sudo apt-get update -qq
  sudo apt-get install -y "$package"
  log_ok "$package installed"
}

# ─── Installer: GitHub release download ────────────────────────────────

# Generic GitHub release binary installer
install_github_release() {
  local name="$1"
  local version="$2"
  local binary="$3"
  local asset_url="$4"

  if check_command "$binary"; then
    local v
    v=$("$binary" version 2>/dev/null | head -1) || v="installed"
    log_ok "$name already installed: $v"
    return 0
  fi

  log_info "Installing $name $version from GitHub..."
  mkdir -p "$LOCAL_BIN"

  local tmpdir
  tmpdir=$(mktemp -d)
  local archive="${tmpdir}/archive"

  # Download the asset
  log_info "Downloading: $asset_url"
  if ! curl -fsSL -o "$archive" "$asset_url"; then
    log_error "Download failed for $name"
    rm -rf "$tmpdir"
    return 1
  fi

  # Extract depending on archive type
  case "$asset_url" in
    *.tar.gz)
      tar -xzf "$archive" -C "$tmpdir"
      ;;
    *.zip)
      unzip -q "$archive" -d "$tmpdir"
      ;;
    *)
      # Assume it's a raw binary
      chmod +x "$archive"
      mv "$archive" "${LOCAL_BIN}/${binary}"
      rm -rf "$tmpdir"
      log_ok "$name installed to ${LOCAL_BIN}/${binary}"
      return 0
      ;;
  esac

  # Find the binary in extracted files
  find "$tmpdir" -type f -name "$binary" -exec chmod +x {} \; \
    -exec mv {} "${LOCAL_BIN}/${binary}" \;
  rm -rf "$tmpdir"

  log_ok "$name installed to ${LOCAL_BIN}/${binary}"
}

# ─── Tool-specific installers ──────────────────────────────────────────

install_kubectl() {
  local os="$1"
  local version="$KUBECTL_VERSION"

  if [[ "$os" == "macos" ]]; then
    install_with_brew "kubernetes-cli"
  else
    local arch
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "aarch64" ]] && arch="arm64"
    install_github_release "kubectl" "$version" "kubectl" \
      "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
  fi
}

install_helm() {
  local os="$1"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "helm"
  else
    install_github_release "helm" "$HELM_VERSION" "helm" \
      "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  fi
}

install_terraform() {
  local os="$1"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "terraform"
  else
    local arch
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "aarch64" ]] && arch="arm64"
    install_github_release "terraform" "$TERRAFORM_VERSION" "terraform" \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION#v}/terraform_${TERRAFORM_VERSION#v}_linux_${arch}.zip"
  fi
}

install_ansible() {
  local os="$1"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "ansible"
  else
    install_with_apt "ansible"
  fi
}

install_argocd() {
  local os="$1"
  local version="$ARGOCD_VERSION"
  if [[ "$os" == "macos" ]]; then
    install_github_release "argocd" "$version" "argocd" \
      "https://github.com/argoproj/argo-cd/releases/download/${version}/argocd-darwin-amd64"
  else
    install_github_release "argocd" "$version" "argocd" \
      "https://github.com/argoproj/argo-cd/releases/download/${version}/argocd-linux-amd64"
  fi
}

install_kustomize() {
  local os="$1"
  local version="$KUSTOMIZE_VERSION"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "kustomize"
  else
    install_github_release "kustomize" "$version" "kustomize" \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${version}/kustomize_${version}_linux_amd64.tar.gz"
  fi
}

install_kubeseal() {
  local os="$1"
  local version="$KUBESEAL_VERSION"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "kubeseal"
  else
    install_github_release "kubeseal" "$version" "kubeseal" \
      "https://github.com/bitnami-labs/sealed-secrets/releases/download/${version}/kubeseal-${version#v}-linux-amd64.tar.gz"
  fi
}

install_k9s() {
  local os="$1"
  local version="$K9S_VERSION"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "k9s"
  else
    install_github_release "k9s" "$version" "k9s" \
      "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_amd64.tar.gz"
  fi
}

install_yq() {
  local os="$1"
  local version="$YQ_VERSION"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "yq"
  else
    install_github_release "yq" "$version" "yq" \
      "https://github.com/mikefarah/yq/releases/download/${version}/yq_linux_amd64"
  fi
}

install_age() {
  local os="$1"
  if [[ "$os" == "macos" ]]; then
    install_with_brew "age"
  else
    install_with_apt "age"
  fi
}

# ─── Verification ───────────────────────────────────────────────────────

verify_tool() {
  local name="$1"
  local cmd="$2"
  local version_flag="${3:---version}"

  if check_command "$cmd"; then
    local v=""
    v=$("$cmd" $version_flag 2>/dev/null | head -1) || v="installed (version check returned non-zero)"
    if [[ -z "$v" ]]; then
      v="installed"
    fi
    log_ok "${name}: ${v}"
  else
    log_warn "${name}: NOT INSTALLED"
  fi
}

check_all_versions() {
  log_info "Checking installed tool versions..."
  verify_tool "kubectl" "kubectl" "version --client"
  verify_tool "helm" "helm" "version --short"
  verify_tool "terraform" "terraform" "version"
  verify_tool "ansible" "ansible" "--version"
  verify_tool "argocd" "argocd" "version --client"
  verify_tool "kustomize" "kustomize" "version"
  verify_tool "kubeseal" "kubeseal" "--version"
  verify_tool "k9s" "k9s" "version"
  verify_tool "yq" "yq" "--version"
  verify_tool "age" "age" "--version"
}

# ─── Main ───────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Reproducible operator workstation tool installer.

Options:
  --check        Check installed versions only (no installation)
  --tool NAME    Install only one tool (kubectl, helm, terraform, ansible,
                 argocd, kustomize, kubeseal, k9s, yq, age)
  -h, --help     Show this help

Examples:
  $(basename "$0")               Install all tools
  $(basename "$0") --check       Verify installed versions
  $(basename "$0") --tool helm   Install only helm
EOF
}

main() {
  local os
  local check_only=false
  local single_tool=""

  os=$(detect_os)

  while [[ $# -gt 0 ]]; do
    case $1 in
      --check)      check_only=true; shift ;;
      --tool)       single_tool="$2"; shift 2 ;;
      -h|--help)    usage; exit 0 ;;
      *)            log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  log_info "Operating system: $os"
  log_info "Local bin directory: $LOCAL_BIN"

  # If --check, verify only and exit
  if [[ "$check_only" == true ]]; then
    check_all_versions
    exit 0
  fi

  ensure_pkg_manager "$os"

  # Build the list of tools to install
  local -a tools=(
    "kubectl" "helm" "terraform" "ansible"
    "argocd" "kustomize" "kubeseal" "k9s" "yq" "age"
  )

  # Filter to single tool if requested
  if [[ -n "$single_tool" ]]; then
    tools=("$single_tool")
  fi

  # Install each tool
  for tool in "${tools[@]}"; do
    case "$tool" in
      kubectl)   install_kubectl "$os" ;;
      helm)      install_helm "$os" ;;
      terraform) install_terraform "$os" ;;
      ansible)   install_ansible "$os" ;;
      argocd)    install_argocd "$os" ;;
      kustomize) install_kustomize "$os" ;;
      kubeseal)  install_kubeseal "$os" ;;
      k9s)       install_k9s "$os" ;;
      yq)        install_yq "$os" ;;
      age)       install_age "$os" ;;
      *)         log_error "Unknown tool: $tool" ;;
    esac
  done

  log_ok "Installation complete. Verifying versions..."
  check_all_versions

  # Reminder if local bin used
  if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    log_warn "$LOCAL_BIN is not in your PATH."
    log_info "Add this line to ~/.zshrc (or ~/.bashrc):"
    log_info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

main "$@"