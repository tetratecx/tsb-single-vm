#!/usr/bin/env bash
#
# Helper script to manage a gcp cloud Ubuntu VM.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

DEFAULT_PROJECT_BILLING_ACCOUNT="0183E5-447B34-776DEB" ;
DEFAULT_PROJECT_DESCRIPTION="TSB in a Box" ;
DEFAULT_PROJECT_ID="tsb-in-a-box" ;
DEFAULT_PROJECT_LABELS="tetrate_lifespan=always,tetrate_owner=everyone,tetrate_purpose=tsb-in-a-box,tetrate_team=tetrate" ;
DEFAULT_VM_DISK="50GB" ;
DEFAULT_VM_LABELS="tetrate_lifespan=oneoff,tetrate_purpose=demo,tetrate_team=tetrate" ;
DEFAULT_VM_MACHINE_TYPE="n2-standard-8" ;
DEFAULT_VM_NAME="tsb-single-vm" ;
DEFAULT_VM_ZONE="europe-west1-b" ;

DEFAULT_IMAGE_FAMILTY="ubuntu-pro-2204-lts" ;
DEFAULT_IMAGE_PROJECT="ubuntu-os-pro-cloud" ;
DEFAULT_BOOT_DISK_TYPE="pd-ssd" ;

# Start a gcp project
#   args:
#     (1) project description
#     (2) project id
#     (3) project labels
function start_gcp_project() {
  [[ -z "${1}" ]] && print_error "Please provide project description as 1st argument" && return 2 || local project_description="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide project id as 2nd argument" && return 2 || local project_id="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide project labels as 3rd argument" && return 2 || local project_labels="${3}" ;

  existing_project=$(gcloud projects list --filter="projectId:${project_id}" --format="value(projectId)") ;
  if [ -z "${existing_project}" ]; then
    echo "Creating project '${project_id}'" ;
    if ! gcloud projects create "${project_id}" --labels="${project_labels}" --name="${project_description}" --set-as-default; then
      print_error "Failed to create project '${project_id}'. The project ID may already be in use by another project. Ask permission or rename the project ID and try again."
      exit 1
    fi
    print_info "Project '${project_id}' created" ;  
  else
    echo "Project '${project_id}' already exists" ;
    gcloud config set project "${project_id}" ;
  fi
}

# Link a gcp project to a billing account
#   args:
#     (1) project billing account
#     (2) project id
function link_gcp_project_to_billing_account() {
  [[ -z "${1}" ]] && print_error "Please provide project billing account as 1st argument" && return 2 || local project_billing_account="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide project id as 2nd argument" && return 2 || local project_id="${2}" ;

  current_billing_account=$(gcloud billing projects describe "${project_id}" --format="value(billingAccountName)")
  if [[ "${current_billing_account}" == "billingAccounts/${project_billing_account}" ]]; then
    echo "Project '${project_id}' is already linked to billing account '${project_billing_account}'."
  else
    echo "Linking project '${project_id}' to billing account '${project_billing_account}'..."
    if ! gcloud billing projects link "${project_id}" --billing-account "${project_billing_account}"; then
      print_error "Failed to link project '${project_id}' to billing account '${project_billing_account}'."
      exit 1
    fi
    print_info "Project '${project_id}' successfully linked to billing account '${project_billing_account}'."
  fi
}

# Enable and wait for a service to be enabled on a gcp project
#   args:
#     (1) project id
#     (2) gcp cloud service
function enable_gcp_service_on_project() {
  [[ -z "${1}" ]] && print_error "Please provide project id as 1st argument" && return 2 || local project_id="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide gcp cloud service as 2nd argument" && return 2 || local cloud_service="${2}" ;

  if gcloud services list --enabled --filter="name:${cloud_service}" --project="${project_id}" --format="value(name)" | grep -q "${cloud_service}"; then
    echo "Service '${cloud_service}' is already enabled on project '${project_id}'."
    return
  fi

  echo "Enabling service '${cloud_service}' on project '${project_id}'..."
  if ! gcloud services enable "${cloud_service}" --project="${project_id}"; then
    print_error "Failed to enable service '${cloud_service}' on project '${project_id}'."
    exit 1
  fi

  echo -n "Waiting for ${cloud_service} to be enabled..."
  while ! gcloud services list --enabled --filter="name:${cloud_service}" --project="${project_id}" --format="value(name)" | grep -q "${cloud_service}"; do
    echo -n "." ;
    sleep 10 ;
  done
  echo "DONE"
  echo "${cloud_service} is now enabled in project ${project_id}" ;
}

# Create a gcp firewall rule
#   args:
#     (1) firewall rule name
#     (2) firewall rule description
#     (3) firewall rule network
#     (4) firewall rule source ranges
#     (5) firewall rule target tags
#     (6) firewall rule allow
#     (7) project id
function create_firewall_rule() {
  [[ -z "${1}" ]] && print_error "Please provide firewall rule name as 1st argument" && return 2 || local firewall_rule_name="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide firewall rule description as 2nd argument" && return 2 || local firewall_rule_description="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide firewall rule network as 3rd argument" && return 2 || local firewall_rule_network="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide firewall rule source ranges as 4th argument" && return 2 || local firewall_rule_source_ranges="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide firewall rule target tags as 5th argument" && return 2 || local firewall_rule_target_tags="${5}" ;
  [[ -z "${6}" ]] && print_error "Please provide firewall rule allow as 6th argument" && return 2 || local firewall_rule_allow="${6}" ;
  [[ -z "${7}" ]] && print_error "Please provide project id as 7th argument" && return 2 || local project_id="${7}" ;

  existing_firewall_rule=$(gcloud compute firewall-rules list --filter="name=(${firewall_rule_name})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_firewall_rule}" ]; then
    echo "Creating firewall rule '${firewall_rule_name}' in project '${project_id}'"
    gcloud compute firewall-rules create "${firewall_rule_name}" \
      --description="${firewall_rule_description}" \
      --network="${firewall_rule_network}" \
      --source-ranges="${firewall_rule_source_ranges}" \
      --target-tags="${firewall_rule_target_tags}" \
      --allow="${firewall_rule_allow}" \
      --project="${project_id}" ;
    echo "Firewall rule '${firewall_rule_name}' created in project '${project_id}'" ;
  else
    echo "Firewall rule '${firewall_rule_name}' already exists in project '${project_id}'" ;
  fi
}

# Wait for a gcp vm to be ready
#   args:
#     (1) vm name
#     (2) vm zone
#     (3) project id
function wait_ssh_ready() {
  [[ -z "${1}" ]] && print_error "Please provide vm name as 1st argument" && return 2 || local vm_name="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide vm zone as 2nd argument" && return 2 || local vm_zone="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide project id as 3rd argument" && return 2 || local project_id="${3}" ;

  echo -n "Waiting for ${vm_name} to be SSH ready: "
  while ! gcloud compute ssh "${vm_name}" --zone="${vm_zone}" --project="${project_id}" --command="echo 'VM is ready'" &> /dev/null; do
    echo -n "." ;
    sleep 1 ;
  done
  echo "DONE"
  echo "VM '${vm_name}' in project '${project_id}' is now SSH ready" ;
}

# Start a gcp cloud Ubuntu VM
#   args:
#     (1) gcp json config
function start_gcp_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local project_billing_account; project_billing_account=$(echo "${json_config}" | jq -r ".project_billing_account // \"${DEFAULT_PROJECT_BILLING_ACCOUNT}\"") ;
  local project_description; project_description=$(echo "${json_config}" | jq -r ".project_description // \"${DEFAULT_PROJECT_DESCRIPTION}\"") ;
  local project_id; project_id=$(echo "${json_config}" | jq -r ".project_id // \"${DEFAULT_PROJECT_ID}\"") ;
  local project_labels; project_labels=$(echo "${json_config}" | jq -r ".project_labels // \"${DEFAULT_PROJECT_LABELS}\"") ;
  local vm_disk; vm_disk=$(echo "${json_config}" | jq -r ".vm_disk // \"${DEFAULT_VM_DISK}\"") ;
  local vm_labels; vm_labels=$(echo "${json_config}" | jq -r ".vm_labels // \"${DEFAULT_VM_LABELS}\"") ;
  local vm_machine_type; vm_machine_type=$(echo "${json_config}" | jq -r ".vm_machine_type // \"${DEFAULT_VM_MACHINE_TYPE}\"") ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;
  local vm_zone; vm_zone=$(echo "${json_config}" | jq -r ".vm_zone // \"${DEFAULT_VM_ZONE}\"") ;

  start_gcp_project "${project_description}" "${project_id}" "${project_labels}";
  link_gcp_project_to_billing_account "${project_billing_account}" "${project_id}" ;
  enable_gcp_service_on_project "${project_id}" "compute.googleapis.com" ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)")
  if [ -z "${existing_vm}" ]; then
    echo "Creating VM instance '${vm_name}' in project '${project_id}'"
    gcloud compute instances create "${vm_name}" \
      --boot-disk-size="${vm_disk}" \
      --boot-disk-type="${DEFAULT_BOOT_DISK_TYPE}" \
      --image-family="${DEFAULT_IMAGE_FAMILTY}" \
      --image-project="${DEFAULT_IMAGE_PROJECT}" \
      --labels="${vm_labels}" \
      --machine-type="${vm_machine_type}" \
      --metadata="user-data=$(<"${HELPERS_DIR}/templates/gcp-cloud-init.yaml")" \
      --network="default" \
      --project="${project_id}" \
      --tags="http-server,https-server" \
      --zone="${vm_zone}" ;
    echo "VM instance '${vm_name}' created in project '${project_id}'" ;
  elif vm_status=$(gcloud compute instances describe "${vm_name}" --zone="${vm_zone}" --project="${project_id}" --format="value(status)"); \
      [[ "${vm_status}" == "TERMINATED" ]] || [[ "${vm_status}" = "SUSPENDED" ]]; then
    echo "VM instance '${vm_name}' is in '${vm_status}' state, starting it..."
    gcloud compute instances start "${vm_name}" --zone="${vm_zone}" --project="${project_id}"
  else
    echo "VM instance '${vm_name}' already exists and is running in project '${project_id}'"
  fi

  create_firewall_rule "default-allow-http" "Allow HTTP" "default" "0.0.0.0/0" "http-server" "tcp:80,tcp:8080" "${project_id}" ;
  create_firewall_rule "default-allow-https" "Allow HTTPS" "default" "0.0.0.0/0" "https-server" "tcp:443,tcp:8443" "${project_id}" ;
  wait_ssh_ready "${vm_name}" "${vm_zone}" "${project_id}" ;
  print_info "VM '${vm_name}' in project '${project_id}' is now ready" ;
}

# This function stops the gcp cloud Ubuntu VM
#   args:
#     (1) gcp json config
function stop_gcp_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local project_id; project_id=$(echo "${json_config}" | jq -r ".project_id // \"${DEFAULT_PROJECT_ID}\"") ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;
  local vm_zone; vm_zone=$(echo "${json_config}" | jq -r ".vm_zone // \"${DEFAULT_VM_ZONE}\"") ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_vm}" ]; then
    echo "VM instance '${vm_name}' does not exist in project '${project_id}'" ;
  else
    echo "Stopping VM instance '${vm_name}' in project '${project_id}'"
    gcloud compute instances stop "${vm_name}" \
      --project="${project_id}" \
      --zone="${vm_zone}" ;
    echo "VM instance '${vm_name}' stopped in project '${project_id}'" ;
  fi
}

# This function deletes the gcp cloud Ubuntu VM
#   args:
#     (1) gcp json config
function delete_gcp_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local project_id; project_id=$(echo "${json_config}" | jq -r ".project_id // \"${DEFAULT_PROJECT_ID}\"") ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;
  local vm_zone; vm_zone=$(echo "${json_config}" | jq -r ".vm_zone // \"${DEFAULT_VM_ZONE}\"") ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_vm}" ]; then
    echo "VM instance '${vm_name}' does not exist in project '${project_id}'" ;
  else
    echo "Deleting VM instance '${vm_name}' in project '${project_id}'"
    gcloud compute instances delete "${vm_name}" \
      --delete-disks=all \
      --project="${project_id}" \
      --quiet \
      --zone="${vm_zone}" ;
    echo "VM instance '${vm_name}' deleted in project '${project_id}'" ;
  fi
}

# This function launches a shell in the gcp cloud Ubuntu VM
#   args:
#     (1) gcp json config
function shell_gcp_vm() {
  [[ -z "${1}" ]] && print_error "Please provide gcp config json as 1st argument" && return 2 || local json_config="${1}" ;
  local project_id; project_id=$(echo "${json_config}" | jq -r ".project_id // \"${DEFAULT_PROJECT_ID}\"") ;
  local vm_name; vm_name=$(echo "${json_config}" | jq -r ".vm_name // \"${DEFAULT_VM_NAME}\"") ;
  local vm_zone; vm_zone=$(echo "${json_config}" | jq -r ".vm_zone // \"${DEFAULT_VM_ZONE}\"") ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_vm}" ]; then
    print_error "VM instance '${vm_name}' does not exist in project '${project_id}'" ;
    exit 1 ;
  else
    echo "Spawn a shell in VM instance '${vm_name}' in project '${project_id}'"
    print_command "gcloud compute ssh ${vm_name} --project=${project_id} --zone=${vm_zone} -- 'sudo su ubuntu'" ;
    gcloud compute ssh "${vm_name}" --project="${project_id}" --zone="${vm_zone}" -- 'sudo su ubuntu';
  fi
}
