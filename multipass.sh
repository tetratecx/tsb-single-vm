#!/usr/bin/env bash
#
# Helper script to manage a local Multipass Ubuntu VM for MacOS or Windows
# because the docker network stack on those OS's is not useable.
#

BASE_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export BASE_DIR

# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

ACTION=${1}

VM_CPU="${VM_CPU:-2}"
VM_DISK="${VM_DISK:-20G}"
VM_MEM="${VM_MEM:-16G}"
VM_OS="${VM_OS:-22.04}"
VM_NAME="${VM_NAME:-tsb-single-vm}"

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]"
  echo "Commands:"
  echo "  --start     Start multipass Ubuntu VM."
  echo "  --shell     Spawn a shell into multipass Ubuntu VM."
  echo "  --stop      Stop multipass Ubuntu VM."
  echo "  --delete    Delete multipass Ubuntu VM."
  echo "  --recreate  Recreate multipass Ubuntu VM."
  echo "  --help      Display this help message."
}

# This function starts multipass Ubuntu VM.
#
function start() {

  if multipass list --format json | jq -r '.list[].name' 2>/dev/null | grep -q "${VM_NAME}" ; then
    echo "VM ${VM_NAME} already exists" ;
    if multipass list --format json | jq -r '.list[].state' 2>/dev/null | grep -q "Running" ; then
      echo "VM ${VM_NAME} is already running" ;
    elif multipass list --format json | jq -r '.list[].state' 2>/dev/null | grep -q "Stopped" ; then
      echo "Start ${VM_NAME} VM" ;
      multipass start "${VM_NAME}" ;
    else
      echo "VM ${VM_NAME} is in an unknown state" ;
    fi
  else
    echo "Create ${VM_NAME} VM" ;
    multipass launch --cpus "${VM_CPU}" \
                    --disk "${VM_DISK}" \
                    --memory "${VM_MEM}" \
                    --mount "${PWD}:/home/ubuntu/tsb-single-vm" \
                    --name "${VM_NAME}" \
                    "${VM_OS}" ;

    echo "Install packages in VM ${VM_NAME}" ;
    multipass exec "${VM_NAME}" -- bash -c "sudo apt-get -y update && sudo apt-get install -y curl docker.io expect jq make net-tools" ;
    multipass exec "${VM_NAME}" -- bash -c "sudo usermod -aG docker ubuntu" ;
  fi

}

# This function stops multipass Ubuntu VM.
#
function stop() {

  echo "Stop ${VM_NAME} VM" ;
  if multipass list --format json | jq -r '.list[].name' 2>/dev/null | grep -q "${VM_NAME}" ; then
    multipass stop "${VM_NAME}" ;
  fi

}

# This function launches a shell in multipass Ubuntu VM.
#
function shell() {

  echo "Spawn a shell in VM ${VM_NAME}" ;
  multipass shell "${VM_NAME}" ;

}

# This function deletes multipass Ubuntu VM.
#
function delete() {

  echo "Delete VM ${VM_NAME}" ;
  if multipass list --format json | jq -r '.list[].name' 2>/dev/null | grep -q "${VM_NAME}" ; then
    multipass delete --purge "${VM_NAME}" ;
  fi  

}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --start)
    print_stage "Going start the multipass Ubuntu VM" ;
    start ;
    ;;
  --stop)
    print_stage "Going start the multipass Ubuntu VM" ;
    stop ;
    ;;
  --shell)
    print_stage "Going spawn a shell into the multipass Ubuntu VM" ;
    shell ;
    ;;
  --delete)
    print_stage "Going to delete the multipass Ubuntu VM" ;
    delete ;
    ;;
  --recreate)
    print_stage "Going to recreate the multipass Ubuntu VM" ;
    delete ;
    start ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac