#!/usr/bin/env bash
#
# Helper script to manage a local multipass Ubuntu VM.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

DEFAULT_VM_CPU="2" ;
DEFAULT_VM_DISK="20G" ;
DEFAULT_VM_MEM="16G" ;
DEFAULT_VM_NAME="tsb-single-vm" ;
DEFAULT_VM_OS="22.04" ;

# This function starts a multipass Ubuntu VM
#   args:
#     (1) multipass json config
function start_multipass_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local vm_cpu; vm_cpu=$(echo "${json_config}" | jq -r ".vm_cpu // \"${DEFAULT_VM_CPU}\"") ;
  local vm_disk; vm_disk=$(echo "${json_config}" | jq -r ".vm_disk // \"${DEFAULT_VM_DISK}\"") ;
  local vm_mem; vm_mem=$(echo "${json_config}" | jq -r ".vm_mem // \"${DEFAULT_VM_MEM}\"") ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;
  local vm_os_version; vm_os_version=$(echo "${json_config}" | jq -r ".vm_os_version // \"${DEFAULT_VM_OS}\"") ;

  if multipass list --format json | jq -r --arg vm_name "${vm_name}" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    echo "VM '${vm_name}' already exists" ;
    vm_state=$(multipass list --format json | jq -r --arg vm_name "${vm_name}" '.list[] | select(.name == $vm_name) | .state')
    if [ "$vm_state" = "Running" ]; then
      echo "VM '${vm_name}' is already running" ;
    elif [ "$vm_state" = "Stopped" ]; then
      echo "Restart multipass VM '${vm_name}'" ;
      multipass start "${vm_name}" ;

      while true; do
        mount_output=$(multipass mount "${PWD}" "${vm_name}:/home/ubuntu/tsb-single-vm" 2>&1) ;
        mount_status=$? ;
        if [[ ${mount_status} -eq 0 ]]; then
          echo "mount succeeded" ;
          break ;
        elif [[ ${mount_output} == *"'tsb-single-vm' is already mounted in 'tsb-single-vm'"* ]]; then
          echo "mount point is already mounted" ;
          break ;
        else
          echo "mount failed, retrying..." ;
          sleep 1 ;
        fi
      done
    else
      echo "VM '${vm_name}' is in an unknown state" ;
    fi
  else
    echo "Create multipass VM '${vm_name}'" ;
    multipass launch --cloud-init "${HELPERS_DIR}/templates/multipass-cloud-init.yaml" \
                     --cpus "${vm_cpu}" \
                     --disk "${vm_disk}" \
                     --memory "${vm_mem}" \
                     --mount "${PWD}:/home/ubuntu/tsb-single-vm" \
                     --name "${vm_name}" \
                     "${vm_os_version}" ;
    echo "Multipass VM '${vm_name}' created" ;                 
  fi
}

# This function stops the multipass Ubuntu VM
#   args:
#     (1) multipass json config
function stop_multipass_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;  

  echo "Stop multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    multipass stop "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist or is not running" ;
  fi
}

# This function deletes the multipass Ubuntu VM
#   args:
#     (1) multipass json config
function delete_multipass_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;  

  echo "Delete multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    multipass delete --purge "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist" ;
  fi
}


# This function launches a shell in the multipass Ubuntu VM
#   args:
#     (1) multipass json config
function shell_multipass_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;  

  echo "Spawn a shell in multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .state' 2>/dev/null | grep -q "Running" ; then
    multipass shell "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist or is not running." ;
  fi
}
