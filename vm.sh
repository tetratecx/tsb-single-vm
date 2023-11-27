#!/usr/bin/env bash
#
# Helper script to manage an Ubuntu 22.04 VM to run TSB in a single VM.
# Supported environements include: 
#   - local: MacOS, Windows, Linux (multipass based)
#   - cloud: AWS, Azure, GCP
#
BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/multipass.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]"
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
  local vm_kind; vm_kind=$(get_vm_kind) ;

  case "${vm_kind}" in
    multipass)
      local vm_cpu; vm_cpu=$(get_multipass_vm_cpu) ;
      local vm_disk; vm_disk=$(get_multipass_vm_disk) ;
      local vm_mem; vm_mem=$(get_multipass_vm_mem) ;
      local vm_name; vm_name=$(get_multipass_vm_name) ;
      print_info "Starting a Multipass VM '${vm_name}'" ;
      print_info "  CPU: ${vm_cpu}" ;
      print_info "  Memory: ${vm_mem}" ;
      print_info "  Disk: ${vm_disk}" ;
      start_multipass_vm "${vm_name}" "${vm_cpu}" "${vm_mem}" "${vm_disk}" ;
      ;;
    *)
      print_error "Unsupported VM kind: ${vm_kind}" ;
      ;;
  esac
}

# This function stops the Ubuntu VM.
#
function stop() {
  local vm_kind; vm_kind=$(get_vm_kind) ;

  case "${vm_kind}" in
    multipass)
      local vm_name; vm_name=$(get_multipass_vm_name) ;
      print_info "Stopping the Multipass VM '${vm_name}'" ;
      stop_multipass_vm "${vm_name}" ;
      ;;
    *)
      print_error "Unsupported VM kind: ${vm_kind}" ;
      ;;
  esac
}

# This function deletes the Ubuntu VM.
#
function delete() {
  local vm_kind; vm_kind=$(get_vm_kind) ;

  case "${vm_kind}" in
    multipass)
      local vm_name; vm_name=$(get_multipass_vm_name) ;
      print_info "Deleting a Multipass VM '${vm_name}'" ;
      delete_multipass_vm "${vm_name}" ;
      ;;
    *)
      print_error "Unsupported VM kind: ${vm_kind}" ;
      ;;
  esac
}

# This function spawns a shell in the Ubuntu VM.
#
function shell() {
  local vm_kind; vm_kind=$(get_vm_kind) ;

  case "${vm_kind}" in
    multipass)
      local vm_name; vm_name=$(get_multipass_vm_name) ;
      print_info "Spawning a shell into Multipass VM '${vm_name}'" ;
      shell_multipass_vm "${vm_name}" "${vm_cpu}" "${vm_mem}" "${vm_disk}" ;
      ;;
    *)
      print_error "Unsupported VM kind: ${vm_kind}" ;
      ;;
  esac
}


# Main execution
#
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