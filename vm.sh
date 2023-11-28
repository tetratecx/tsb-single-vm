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
source "${BASE_DIR}/helpers/gcp.sh" ;
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
      print_info "Starting Multipass VM" ;
      print_info "  VM CPU: ${vm_cpu}" ;
      print_info "  VM Disk: ${vm_disk}" ;
      print_info "  VM Memory: ${vm_mem}" ;
      print_info "  VM Name: ${vm_name}" ;
      start_multipass_vm "${vm_cpu}" "${vm_disk}" "${vm_mem}" "${vm_name}" ;
      ;;
    gcp)
      local project_billing_account; project_billing_account=$(get_gcp_project_billing_account) ;
      local project_description; project_description=$(get_gcp_project_description) ;
      local project_id; project_id=$(get_gcp_project_id) ;
      local vm_disk; vm_disk=$(get_gcp_vm_disk) ;
      local vm_machine_type; vm_machine_type=$(get_gcp_vm_machine_type) ;
      local vm_name; vm_name=$(get_gcp_vm_name) ;
      local vm_ssh_key; vm_ssh_key=$(get_gcp_vm_ssh_key) ;
      local vm_zone; vm_zone=$(get_gcp_vm_zone) ;
      print_info "Starting GCP VM" ;
      print_info "  Project Billing Account: ${project_billing_account}" ;
      print_info "  Project Description: ${project_description}" ;
      print_info "  Project ID: ${project_id}" ;
      print_info "  VM Disk: ${vm_disk}" ;
      print_info "  VM Machine Type: ${vm_machine_type}" ;
      print_info "  VM Name: ${vm_name}" ;
      print_info "  VM SSH Key: ${vm_ssh_key}" ;
      print_info "  VM Zone: ${vm_zone}" ;
      start_gcp_vm "${project_billing_account}" "${project_description}" "${project_id}" \
        "${vm_disk}" "${vm_machine_type}" "${vm_name}" "${vm_ssh_key}" "${vm_zone}" ;
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
      print_info "Stopping the Multipass VM" ;
      print_info "  VM Name: ${vm_name}" ;
      stop_multipass_vm "${vm_name}" ;
      ;;
    gcp)
      local project_id; project_id=$(get_gcp_project_id) ;
      local vm_name; vm_name=$(get_gcp_vm_name) ;
      local vm_zone; vm_zone=$(get_gcp_vm_zone) ;
      print_info "Stopping GCP VM" ;
      print_info "  Project ID: ${project_id}" ;
      print_info "  VM Name: ${vm_name}" ;
      print_info "  VM Zone: ${vm_zone}" ;
      stop_gcp_vm "${project_id}" "${vm_name}" "${vm_zone}" ;
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
    gcp)
      local project_id; project_id=$(get_gcp_project_id) ;
      local vm_name; vm_name=$(get_gcp_vm_name) ;
      local vm_zone; vm_zone=$(get_gcp_vm_zone) ;
      print_info "Deleting GCP VM" ;
      print_info "  Project ID: ${project_id}" ;
      print_info "  VM Name: ${vm_name}" ;
      print_info "  VM Zone: ${vm_zone}" ;
      delete_gcp_vm "${project_id}" "${vm_name}" "${vm_zone}" ;
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
      print_info "Spawning a shell into Multipass VM" ;
      print_info "  VM Name: ${vm_name}" ;
      shell_multipass_vm "${vm_name}" "${vm_cpu}" "${vm_mem}" "${vm_disk}" ;
      ;;
    gcp)
      local project_id; project_id=$(get_gcp_project_id) ;
      local vm_name; vm_name=$(get_gcp_vm_name) ;
      local vm_zone; vm_zone=$(get_gcp_vm_zone) ;
      print_info "Spawning a shell into GCP VM" ;
      print_info "  Project ID: ${project_id}" ;
      print_info "  VM Name: ${vm_name}" ;
      print_info "  VM Zone: ${vm_zone}" ;
      shell_gcp_vm "${project_id}" "${vm_name}" "${vm_zone}" ;
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