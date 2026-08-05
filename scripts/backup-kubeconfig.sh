#!/usr/bin/env bash
#
# backup-kubeconfig.sh — Securely backup Kubernetes kubeconfig
#
# Encrypts your kubeconfig using Age encryption and stores it with a timestamp.
# Optionally uploads to Azure Key Vault for off-site backup.
#
# USAGE:
#   ./scripts/backup-kubeconfig.sh                    # Default: ~/.kube/k3s-config
#   ./scripts/backup-kubeconfig.sh -f /path/to/config # Custom kubeconfig path
#   ./scripts/backup-kubeconfig.sh -u                 # Also upload to Azure Key Vault
#   ./scripts/backup-kubeconfig.sh -h                 # Show help
#
# PREREQUISITES:
#   - age (encryption tool): https://github.com/FiloSottile/age
#   - Age public key file (~/.config/age/age-key.txt.pub) generated with:
#     age-keygen -o ~/.config/age/age-key.txt
#   - Azure CLI (az) for Key Vault upload (optional, requires -u flag)
#
# LEARNING NOTES:
#   - set -euo pipefail: Fail fast on errors, undefined vars, and pipe failures
#   - Age encryption: modern public-key encryption; encrypt with public key,
#     decrypt with private key
#   - File permissions: 600 (owner read/write) for keys, 644 for encrypted files
#   - Timestamp format: ISO 8601 UTC for sortable unique filenames
#   - Never commit kubeconfig or keys to git

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────
DEFAULT_KUBECONFIG="${HOME}/.kube/k3s-config"
DEFAULT_AGE_PUBKEY="${HOME}/.config/age/age-key.txt.pub"
BACKUP_DIR="${HOME}/.kube/backups"
AZURE_KEYVAULT_NAME="${AZURE_KEYVAULT_NAME:-}"  # Set via env var
RETENTION_DAYS=30

# ─── Colors for output ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Helper Functions ───────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Securely backup Kubernetes kubeconfig using Age encryption.

Options:
  -f, --file PATH       Path to kubeconfig (default: ${DEFAULT_KUBECONFIG})
  -k, --key PATH        Path to Age public key (default: ${DEFAULT_AGE_PUBKEY})
  -d, --dir PATH        Backup directory (default: ${BACKUP_DIR})
  -u, --upload          Upload encrypted backup to Azure Key Vault
  -r, --retention DAYS  Retention period in days (default: ${RETENTION_DAYS})
  -h, --help            Show this help message

Environment Variables:
  AZURE_KEYVAULT_NAME   Azure Key Vault name for --upload option

Examples:
  $(basename "$0")                                    # Default backup
  $(basename "$0") -f ~/.kube/config -u              # Custom config + upload
  AZURE_KEYVAULT_NAME=my-vault $(basename "$0") -u   # With Key Vault upload

Prerequisites:
  - age installed (brew install age / apt install age)
  - Age public key at ~/.config/age/age-key.txt.pub
  - Azure CLI logged in (for --upload): az login
EOF
}

# ─── Validation Functions ───────────────────────────────────────────────

check_command() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command '$cmd' not found."
    log_info "Install hint: $install_hint"
    return 1
  fi
}

validate_kubeconfig() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Kubeconfig not found: $file"
    return 1
  fi
  if [[ ! -r "$file" ]]; then
    log_error "Kubeconfig not readable: $file"
    return 1
  fi
  # Basic YAML sanity check — a real kubeconfig always has these keys
  if ! grep -qE '^(apiVersion|kind):' "$file"; then
    log_warn "File may not be a valid kubeconfig (missing apiVersion/kind)"
  fi
  log_ok "Kubeconfig validated: $file"
}

validate_age_pubkey() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Age public key not found: $file"
    log_info "Generate with: age-keygen -o ~/.config/age/age-key.txt"
    return 1
  fi
  if ! grep -q "^age1" "$file"; then
    log_error "Invalid Age public key format (should start with 'age1')"
    return 1
  fi
  log_ok "Age public key validated: $file"
}

# ─── Core Functions ─────────────────────────────────────────────────────

create_backup_dir() {
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  log_ok "Backup directory ready: $BACKUP_DIR"
}

encrypt_kubeconfig() {
  local kubeconfig="$1"
  local pubkey="$2"
  local output="$3"

  log_info "Encrypting kubeconfig with Age..."
  # age -r: recipient (public key); -a: armor output (ASCII text)
  age -r "$(cat "$pubkey")" -a < "$kubeconfig" > "$output"
  chmod 644 "$output"  # Encrypted file can be world-readable
  log_ok "Encrypted backup created: $output"
}

upload_to_keyvault() {
  local backup_file="$1"
  local secret_name="$2"

  if [[ -z "$AZURE_KEYVAULT_NAME" ]]; then
    log_error "AZURE_KEYVAULT_NAME not set. Cannot upload."
    return 1
  fi

  if ! command -v az &>/dev/null; then
    log_error "Azure CLI (az) not installed."
    return 1
  fi

  log_info "Uploading to Azure Key Vault: $AZURE_KEYVAULT_NAME"
  az keyvault secret set \
    --vault-name "$AZURE_KEYVAULT_NAME" \
    --name "$secret_name" \
    --file "$backup_file" \
    --output none

  log_ok "Uploaded to Key Vault as secret: $secret_name"
}

cleanup_old_backups() {
  local retention_days="$1"

  log_info "Cleaning backups older than $retention_days days..."
  find "$BACKUP_DIR" -type f -name 'kubeconfig-*.age' -mtime "+$retention_days" -delete
  log_ok "Cleanup complete"
}

# ─── Main Script ────────────────────────────────────────────────────────

main() {
  local kubeconfig="$DEFAULT_KUBECONFIG"
  local age_pubkey="$DEFAULT_AGE_PUBKEY"
  local upload=false
  local retention_days=$RETENTION_DAYS

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -f|--file)      kubeconfig="$2"; shift 2 ;;
      -k|--key)       age_pubkey="$2"; shift 2 ;;
      -d|--dir)       BACKUP_DIR="$2"; shift 2 ;;
      -u|--upload)    upload=true; shift ;;
      -r|--retention) retention_days="$2"; shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  log_info "Starting kubeconfig backup..."
  log_info "Kubeconfig: $kubeconfig"
  log_info "Age public key: $age_pubkey"
  log_info "Backup directory: $BACKUP_DIR"
  log_info "Upload to Key Vault: $upload"

  # Validate prerequisites
  check_command "age" "brew install age / apt install age / https://github.com/FiloSottile/age" || exit 1
  validate_kubeconfig "$kubeconfig" || exit 1
  validate_age_pubkey "$age_pubkey" || exit 1

  # Prepare backup
  create_backup_dir

  # Generate timestamped filename (ISO 8601 UTC: 2026-08-03T15-30-00Z)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  local backup_file="${BACKUP_DIR}/kubeconfig-${timestamp}.age"
  local secret_name="kubeconfig-backup-${timestamp}"

  # Encrypt
  encrypt_kubeconfig "$kubeconfig" "$age_pubkey" "$backup_file"

  # Optional upload
  if [[ "$upload" == true ]]; then
    upload_to_keyvault "$backup_file" "$secret_name"
  fi

  # Cleanup old backups
  cleanup_old_backups "$retention_days"

  log_ok "Backup complete!"
  log_info "Encrypted backup: $backup_file"
  log_info "To restore: age -d -i ~/.config/age/age-key.txt < $backup_file > ~/.kube/k3s-config"
}

main "$@"
