#!/usr/bin/env bash
#
# Helper script to create a local Ubuntu VM for MacOS or Windows
# because the docker network stack on those OS's is not useable.
#

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/helpers.sh

CPU_MASTER=2
MEM_MASTER=16G
DISK_MASTER=20G
RUN_OS=22.04
VM_NAME=tsb-single-vm

print_info "Creating ${VM_NAME} VM" ;
multipass launch --cpus "${CPU_MASTER}" \
                 --disk "${DISK_MASTER}" \
                 --memory "${MEM_MASTER}" \
                 --mount "${PWD}:/home/ubuntu/tsb-single-vm" \
                 --name "${VM_NAME}" \
                 "${RUN_OS}" ;

print_info "Installing packages in VM ${VM_NAME}" ;
multipass exec "${VM_NAME}" -- bash -c "sudo apt-get -y update && sudo apt-get install -y docker.io net-tools expect curl jq" ;
multipass exec "${VM_NAME}" -- bash -c "sudo usermod -aG docker ubuntu" ;

print_info "Starting shell in VM ${VM_NAME}" ;
print_command "multipass shell ${VM_NAME}" ;
multipass shell ${VM_NAME} ;

