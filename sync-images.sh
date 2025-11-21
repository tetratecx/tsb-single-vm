#!/usr/bin/env bash
#
# Script to download tctl and sync TSB images to local registry
# This script reads the target TSB version from env.json and:
# 1. Downloads the specified tctl version
# 2. Syncs TSB images to the local registry
#

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tctl.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/debug.sh"

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0"
  echo "Downloads tctl based on version_upgrade_target in env.json and syncs TSB images to local registry"
  echo ""
  echo "Prerequisites:"
  echo "  - env.json must exist with .tsb.upgrade.version_upgrade_target set"
  echo "  - Tetrate repository credentials must be set in env.json"
  echo "  - Local registry must be running"
}

# Main execution
#

# Check if help was requested
if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
  help
  exit 0
fi

# Get target version from env.json
TARGET_VERSION=$(get_tsb_version_upgrade_target)

if [[ -z "${TARGET_VERSION}" || "${TARGET_VERSION}" == "null" ]]; then
  print_error "No target version specified in env.json"
  print_error "Please set .tsb.upgrade.version_upgrade_target before running this script"
  print_error ""
  print_error "Example:"
  print_error '  "tsb": {'
  print_error '    "upgrade": {'
  print_error '      "version_upgrade_target": "1.13.0"'
  print_error '    }'
  print_error '  }'
  exit 1
fi

print_info "Target TSB version: ${TARGET_VERSION}"

# Get Tetrate repository credentials
TETRATE_USER=$(get_tetrate_repo_user)
TETRATE_PASSWORD=$(get_tetrate_repo_password)

if [[ -z "${TETRATE_USER}" || -z "${TETRATE_PASSWORD}" ]]; then
  print_error "Tetrate repository credentials not found in env.json"
  print_error "Please set .tsb.tetrate_repo.user and .tsb.tetrate_repo.password"
  exit 1
fi

LOCAL_REGISTRY="$(get_local_registry_endpoint)"
# Check if local registry is running
if [[ -z "${LOCAL_REGISTRY}" ]]; then
  print_error "Local registry is not running"
  print_error "Please start the local registry first"
  exit 1
fi
print_info "Local registry: ${LOCAL_REGISTRY}"

# Check if tctl is installed
TCTL_PATH="$(get_tctl_path)"
if [[ -z "${TCTL_PATH}" ]]; then
  print_error "TCTL is not installed."
  exit 1
fi

# Remove Docker isolation (required for registry access)
docker_remove_isolation

# Sync images using helper function
if ! sync_tsb_images_with_tctl "${TCTL_PATH}" "${LOCAL_REGISTRY}" "${TETRATE_USER}" "${TETRATE_PASSWORD}"; then
  print_error "Failed to sync images"
  exit 1
fi

print_info "Done! All images synced successfully"
print_info "Downloaded tctl is available at: ${TCTL_PATH}"
print_info "To use this version: sudo install ${TCTL_PATH} /usr/local/bin/tctl"
