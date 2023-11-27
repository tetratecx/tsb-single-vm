#!/usr/bin/env bash
#
# Helper script to manage a local Multipass Ubuntu VM for MacOS or Windows
# because the docker network stack on those OS's is not useable.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

DEFAULT_VM_CPU="2"
DEFAULT_VM_DISK="20G"
DEFAULT_VM_MEM="16G"
DEFAULT_VM_NAME="tsb-single-vm"
DEFAULT_VM_OS="22.04"

# This function starts a multipass Ubuntu VM
#   args:
#     (1) vm name (default: tsb-single-vm)
#     (2) vm cpu (default: 2)
#     (3) vm memory (default: 16G)
#     (4) vm disk (default: 20G)
#     (5) vm ubuntu os version (default: 22.04)
function start_multipass_vm() {
  [[ -z "${1}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${1}" ;
  [[ -z "${2}" ]] && local vm_cpu="${DEFAULT_VM_CPU}" || local vm_cpu="${2}" ;
  [[ -z "${3}" ]] && local vm_mem="${DEFAULT_VM_MEM}" || local vm_mem="${3}" ;
  [[ -z "${4}" ]] && local vm_disk="${DEFAULT_VM_DISK}" || local vm_disk="${4}" ;
  [[ -z "${5}" ]] && local vm_os_version="${DEFAULT_VM_OS}" || local vm_os_version="${5}" ;

  if multipass list --format json | jq -r --arg vm_name "${vm_name}" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    echo "VM '${vm_name}' already exists" ;
    vm_state=$(multipass list --format json | jq -r --arg vm_name "${vm_name}" '.list[] | select(.name == $vm_name) | .state')
    if [ "$vm_state" = "Running" ]; then
      echo "VM' ${vm_name}' is already running" ;
    elif [ "$vm_state" = "Stopped" ]; then
      echo "Restart multipass VM '${vm_name}'" ;
      multipass start "${vm_name}" ;

      while true; do
        mount_output=$(multipass mount "${PWD}" "${vm_name}:/home/ubuntu/tsb-single-vm" 2>&1) ;
        mount_status=$? ;
        if [[ $mount_status -eq 0 ]]; then
          echo "mount succeeded" ;
          break ;
        elif [[ $mount_output == *"'tsb-single-vm' is already mounted in 'tsb-single-vm'"* ]]; then
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
    multipass launch --cpus "${vm_cpu}" \
                    --disk "${vm_disk}" \
                    --memory "${vm_mem}" \
                    --mount "${PWD}:/home/ubuntu/tsb-single-vm" \
                    --name "${vm_name}" \
                    "${vm_os_version}" ;

    echo "Install packages in multipass VM '${vm_name}'" ;
    multipass exec "${vm_name}" -- bash -c "sudo NEEDRESTART_MODE=a apt-get -y update && sudo NEEDRESTART_MODE=a apt-get -y upgrade && sudo NEEDRESTART_MODE=a apt-get install -y curl docker.io expect httpie jq net-tools make  nmap traceroute tree" ;
    multipass exec "${vm_name}" -- bash -c "sudo usermod -aG docker ubuntu" ;
  fi
}

# This function stops the multipass Ubuntu VM
#   args:
#     (1) vm name (default: tsb-single-vm)
function stop_multipass_vm() {
  [[ -z "${1}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${1}" ;

  echo "Stop multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    multipass stop "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist or is not running" ;
  fi
}

# This function deletes the multipass Ubuntu VM
#   args:
#     (1) vm name (default: tsb-single-vm)
function delete_multipass_vm() {
  [[ -z "${1}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${1}" ;

  echo "Delete multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .name' 2>/dev/null | grep -q "${vm_name}" ; then
    multipass delete --purge "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist" ;
  fi  
}


# This function launches a shell in the multipass Ubuntu VM
#   args:
#     (1) vm name (default: tsb-single-vm)
function shell_multipass_vm() {
  [[ -z "${1}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${1}" ;

  echo "Spawn a shell in multipass VM '${vm_name}'" ;
  if multipass list --format json | jq -r --arg vm_name "$vm_name" '.list[] | select(.name == $vm_name) | .state' 2>/dev/null | grep -q "Running" ; then
    multipass shell "${vm_name}" ;
  else
    echo "VM '${vm_name}' does not exist or is not running." ;
  fi
}
