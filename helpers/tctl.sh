#!/usr/bin/env bash
#
# Helper functions for tctl management
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;

# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

# Get the local tctl version in format 1.9.3
#
function get_tctl_local_version() {
  tctl version --local-only 2>/dev/null | cut -d 'v' -f3
}

# Get the path to the current tctl binary
#
function get_tctl_path() {
  which tctl 2>/dev/null
}

# Download a specific tctl version to a given path
#   args:
#     (1) target version (e.g., "1.13.0")
#     (2) destination path (optional, defaults to /usr/local/bin/tctl)
#   returns:
#     path to downloaded tctl binary
#   notes:
#     - If tctl exists, it will be backed up to tctl-backup in the same directory
#     - The new tctl will be placed at the standard location without version suffix
#
function download_tctl_version() {
  [[ -z "${1}" ]] && print_error "Please provide target version as 1st argument" && return 2 || local target_version="${1}" ;

  # If destination path not provided, use standard location
  if [[ -z "${2}" ]]; then
    local existing_tctl_path; existing_tctl_path=$(get_tctl_path)
    if [[ -n "${existing_tctl_path}" ]]; then
      # Use the same location as the existing tctl (typically /usr/local/bin/tctl)
      local tctl_path="${existing_tctl_path}"
    else
      # No existing tctl, use standard location from prereq.sh
      local tctl_path="/usr/local/bin/tctl"
    fi
  else
    local tctl_path="${2}"
  fi

  if [[ "${target_version}" == "null" ]]; then
    print_error "Invalid target version: null"
    return 2
  fi

  local tctl_dir; tctl_dir=$(dirname "${tctl_path}")

  # Backup existing tctl if it exists using the backup_tctl function
  if [[ -f "${tctl_path}" ]]; then
    local backup_path; backup_path=$(backup_tctl)
    if [[ $? -ne 0 ]]; then
      print_error "Failed to backup existing tctl"
      return 1
    fi
  fi

  local architecture; architecture=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm64\|aarch64/arm64/')
  local tctl_url="https://binaries.dl.tetrate.io/public/raw/versions/linux-${architecture}-${target_version}/tctl"

  print_info "Downloading tctl version ${target_version} from ${tctl_url}"

  # Download to /tmp first
  local temp_path="/tmp/tctl-${target_version}-$$"
  if ! curl -Lo "${temp_path}" "${tctl_url}"; then
    print_error "Failed to download tctl version ${target_version}"
    print_error "Please verify the version exists at ${tctl_url}"

    # Restore backup if download failed (backup_path has version suffix)
    if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
      print_info "Restoring backup from ${backup_path}"
      sudo mv "${backup_path}" "${tctl_path}"
    fi

    rm -f "${temp_path}"
    return 1
  fi

  chmod +x "${temp_path}"

  # Move to final location (use sudo as /usr/local/bin typically requires root)
  if sudo install "${temp_path}" "${tctl_path}"; then
    rm -f "${temp_path}"
    print_info "Successfully installed tctl ${target_version} to ${tctl_path}"
    echo "${tctl_path}"
    return 0
  else
    print_error "Failed to install tctl to ${tctl_path}"

    # Restore backup if installation failed (backup_path has version suffix)
    if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
      print_info "Restoring backup from ${backup_path}"
      sudo mv "${backup_path}" "${tctl_path}"
    fi

    rm -f "${temp_path}"
    return 1
  fi
}

# Backup current tctl binary with version suffix
#   args:
#     (1) current version (optional, auto-detected if not provided)
#   returns:
#     path to backup location
#
function backup_tctl() {
  local tctl_path; tctl_path=$(get_tctl_path)

  if [[ -z "${tctl_path}" ]]; then
    print_error "tctl not found in PATH"
    return 1
  fi

  [[ -z "${1}" ]] && local current_version; current_version=$(get_tctl_local_version) || local current_version="${1}"

  if [[ -z "${current_version}" ]]; then
    print_error "Could not determine current tctl version"
    return 1
  fi

  local backup_path="${tctl_path}-${current_version}"

  if [[ -f "${backup_path}" ]]; then
    print_info "Backup already exists at ${backup_path}"
    echo "${backup_path}"
    return 0
  fi

  print_info "Backing up tctl version ${current_version} to ${backup_path}"
  sudo mv "${tctl_path}" "${backup_path}"

  if [[ $? -eq 0 ]]; then
    print_info "Successfully backed up tctl to ${backup_path}"
    echo "${backup_path}"
    return 0
  else
    print_error "Failed to backup tctl"
    return 1
  fi
}

# Install tctl binary to system location
#   args:
#     (1) path to tctl binary to install
#     (2) destination path (optional, defaults to /usr/local/bin/tctl)
#
function install_tctl() {
  [[ -z "${1}" ]] && print_error "Please provide tctl binary path as 1st argument" && return 2 || local tctl_binary="${1}" ;
  [[ -z "${2}" ]] && local dest_path="/usr/local/bin/tctl" || local dest_path="${2}" ;

  if [[ ! -f "${tctl_binary}" ]]; then
    print_error "tctl binary not found at ${tctl_binary}"
    return 1
  fi

  print_info "Installing tctl from ${tctl_binary} to ${dest_path}"

  if ! sudo install "${tctl_binary}" "${dest_path}"; then
    print_error "Failed to install tctl to ${dest_path}"
    return 1
  fi

  print_info "Successfully installed tctl to ${dest_path}"

  # Verify installation
  local installed_version; installed_version=$(get_tctl_local_version)
  print_info "Installed tctl version: ${installed_version}"

  return 0
}

# Upgrade system tctl to a target version (downloads, backs up current, installs new)
#   args:
#     (1) target version (e.g., "1.13.0")
#   returns:
#     0 on success, non-zero on failure
#
function upgrade_tctl_to_version() {
  [[ -z "${1}" ]] && print_error "Please provide target version as 1st argument" && return 2 || local target_version="${1}" ;

  if [[ -z "${target_version}" || "${target_version}" == "null" ]]; then
    print_error "Invalid target version specified"
    return 1
  fi

  # Check if tctl exists
  if ! command -v tctl &>/dev/null; then
    print_warning "tctl not found in PATH, will install version ${target_version}"
    local tctl_binary; tctl_binary=$(download_tctl_version "${target_version}")
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    install_tctl "${tctl_binary}"
    return $?
  fi

  # Check current version
  local current_version; current_version=$(get_tctl_local_version)

  if [[ "${current_version}" == "${target_version}" ]]; then
    print_error "Current tctl version ${current_version} is already at target version ${target_version}"
    print_error "No upgrade needed"
    return 1
  fi

  print_info "Upgrading tctl from version ${current_version} to version ${target_version}"

  # Download new version
  local new_tctl; new_tctl=$(download_tctl_version "${target_version}")
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  # Backup current version
  local backup_path; backup_path=$(backup_tctl "${current_version}")
  if [[ $? -ne 0 ]]; then
    print_error "Failed to backup current tctl version"
    return 1
  fi

  print_info "Old tctl version ${current_version} backed up at ${backup_path}"

  # Install new version
  if ! install_tctl "${new_tctl}"; then
    print_error "Failed to install new tctl version"
    print_error "Restoring backup from ${backup_path}"
    sudo mv "${backup_path}" "$(dirname ${backup_path})/tctl"
    return 1
  fi

  # Verify installation
  local installed_version; installed_version=$(get_tctl_local_version)
  if [[ "${installed_version}" != "${target_version}" ]]; then
    print_error "Installed tctl version ${installed_version} does not match target version ${target_version}"
    return 1
  fi

  print_info "Successfully upgraded tctl to version ${target_version}"
  return 0
}

# Sync TSB images using a specific tctl binary
#   args:
#     (1) path to tctl binary
#     (2) local registry endpoint
#     (3) tetrate registry username
#     (4) tetrate registry password/apikey
#
function sync_tsb_images_with_tctl() {
  [[ -z "${1}" ]] && print_error "Please provide tctl binary path as 1st argument" && return 2 || local tctl_binary="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide local registry as 2nd argument" && return 2 || local local_registry="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide username as 3rd argument" && return 2 || local username="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide password/apikey as 4th argument" && return 2 || local password="${4}" ;

  if [[ ! -f "${tctl_binary}" ]]; then
    print_error "tctl binary not found at ${tctl_binary}"
    return 1
  fi

  print_info "Syncing TSB images to local registry ${local_registry}"
  print_info "Using tctl from: ${tctl_binary}"

  # Show version
  "${tctl_binary}" version --local-only

  # Sync images
  if ! "${tctl_binary}" install image-sync \
      --username "${username}" \
      --apikey "${password}" \
      --registry "${local_registry}"; then
    print_error "Failed to sync images using tctl"
    return 1
  fi

  print_info "Successfully synced TSB images to ${local_registry}"
  return 0
}
