#!/usr/bin/env bash
#
# Helper script to manage an Ubuntu 22.04 VM to run TSB in a single VM.
# Supported environements include: 
#   - local: MacOS, Windows, Linux (multipass based)
#   - cloud: AWS, Azure, GCP
#
BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/gcp.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/multipass.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

VM_CONFIG_FILE=${1} ;
ACTION=${2} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <vm-config.json> [options]"
  echo "Commands:"
  echo "  --start     Start an Ubuntu VM."
  echo "  --stop      Stop the Ubuntu VM."
  echo "  --delete    Delete the Ubuntu VM."
  echo "  --recreate  Recreate (delete & start) the Ubuntu VM."
  echo "  --shell     Spawn a shell into the Ubuntu VM."
  echo "  --help      Display this help message."
}


# This function starts an Ubuntu VM.
#
function start() {
  local vm_target_type; vm_target_type=$(jq -r ".vm_target_type" "${VM_CONFIG_FILE}") ;

  case "${vm_target_type}" in
    multipass)
      local multipass_config; multipass_config=$(jq -c ".multipass" "${VM_CONFIG_FILE}") ;
      print_info "Starting Multipass VM" ;
      print_info "${multipass_config}" ;
      start_multipass_vm "${multipass_config}" ;
      ;;
    gcp)
      local gcp_config; gcp_config=$(jq -c ".gcp" "${VM_CONFIG_FILE}") ;
      print_info "Starting GCP VM" ;
      print_info "${gcp_config}" ;
      start_gcp_vm "${gcp_config}" ;
      ;;
    *)
      print_error "Unsupported VM kind: '${vm_target_type}'" ;
      ;;
  esac
}

# This function stops the Ubuntu VM.
#
function stop() {
  local vm_target_type; vm_target_type=$(jq -r ".vm_target_type" "${VM_CONFIG_FILE}") ;

  case "${vm_target_type}" in
    multipass)
      local multipass_config; multipass_config=$(jq -c ".multipass" "${VM_CONFIG_FILE}") ;
      print_info "Stopping the Multipass VM" ;
      print_info "${multipass_config}" ;
      stop_multipass_vm "${multipass_config}" ;
      ;;
    gcp)
      local gcp_config; gcp_config=$(jq -c ".gcp" "${VM_CONFIG_FILE}") ;
      print_info "Stopping GCP VM" ;
      print_info "${gcp_config}" ;
      stop_gcp_vm "${gcp_config}" ;
      ;;
    *)
      print_error "Unsupported VM kind: '${vm_target_type}'" ;
      ;;
  esac
}

# This function deletes the Ubuntu VM.
#
function delete() {
  local vm_target_type; vm_target_type=$(jq -r ".vm_target_type" "${VM_CONFIG_FILE}") ;

  case "${vm_target_type}" in
    multipass)
      local multipass_config; multipass_config=$(jq -c ".multipass" "${VM_CONFIG_FILE}") ;
      print_info "Deleting the Multipass VM" ;
      print_info "${multipass_config}" ;
      delete_multipass_vm "${multipass_config}" ;
      ;;
    gcp)
      local gcp_config; gcp_config=$(jq -c ".gcp" "${VM_CONFIG_FILE}") ;
      print_info "Deleting the GCP VM" ;
      print_info "${gcp_config}" ;
      delete_gcp_vm "${gcp_config}" ;
      ;;
    *)
      print_error "Unsupported VM kind: '${vm_target_type}'" ;
      ;;
  esac
}

# This function spawns a shell in the Ubuntu VM.
#
function shell() {
  local vm_target_type; vm_target_type=$(jq -r ".vm_target_type" "${VM_CONFIG_FILE}") ;

  case "${vm_target_type}" in
    multipass)
      local multipass_config; multipass_config=$(jq -c ".multipass" "${VM_CONFIG_FILE}") ;
      print_info "Spawning a shell into Multipass VM" ;
      print_info "${multipass_config}" ;
      shell_multipass_vm "${multipass_config}" ;
      ;;
    gcp)
      local gcp_config; gcp_config=$(jq -c ".gcp" "${VM_CONFIG_FILE}") ;
      print_info "Spawning a shell into GCP VM" ;
      print_info "${gcp_config}" ;
      shell_gcp_vm "${gcp_config}" ;
      ;;
    *)
      print_error "Unsupported VM kind: '${vm_target_type}'" ;
      ;;
  esac
}


# Main execution
#
if [ ! -f "${VM_CONFIG_FILE}" ]; then
  print_error "Error: VM configuration file '${VM_CONFIG_FILE}' not found."
  help ;
  exit 1
fi
if ! jq empty "${VM_CONFIG_FILE}" > /dev/null 2>&1; then
  print_error "Error: VM configuration file '${VM_CONFIG_FILE}' is not a valid JSON file."
  help ;
  exit 1
fi

case "${ACTION}" in
  --help)
    help ;
    ;;
  --start)
    print_stage "Going to start an Ubuntu VM" ;
    start_time=$(date +%s); start; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Started an Ubuntu VM in ${elapsed_time} seconds" ;
    ;;
  --stop)
    print_stage "Going to stop the Ubuntu VM" ;
    start_time=$(date +%s); stop; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Stopped the Ubuntu VM in ${elapsed_time} seconds" ;
    ;;
  --delete)
    print_stage "Going to delete the Ubuntu VM" ;
    start_time=$(date +%s); delete; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Deleted the Ubuntu VM in ${elapsed_time} seconds" ;
    ;;
  --recreate)
    print_stage "Going to recreate the Ubuntu VM" ;
    start_time=$(date +%s); delete; start; elapsed_time=$(( $(date +%s) - start_time )) ;
    print_stage "Recreated the Ubuntu VM in ${elapsed_time} seconds" ;
    ;;
  --shell)
    print_stage "Going to spawn a shell into the Ubuntu VM" ;
    shell ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac