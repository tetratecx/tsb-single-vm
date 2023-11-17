#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/helpers.sh

CPU_MASTER=2
MEM_MASTER=16G
DISK_MASTER=20G
RUN_OS=22.04
VM_NAME=tsb-single-vm

print_info "Creating ${VM_NAME} VM"
multipass launch \
  --cpus "${CPU_MASTER}" \
  --disk "${DISK_MASTER}" \
  --memory "${MEM_MASTER}" \
  --mount .:~/tsb-single-vm \
  --name "${VM_NAME}" 
  "${RUN_OS}" ;

print_info "Starting shell in VM ${VM_NAME}"
print_command "multipass shell ${VM_NAME}"
multipass shell ${VM_NAME} ;
