#!/usr/bin/env bash
#
# Helper script to manage a gcp cloud Ubuntu VM.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

DEFAULT_PROJECT_BILLING_ACCOUNT="0183E5-447B34-776DEB" ;
DEFAULT_PROJECT_DESCRIPTION="TSB in a box" ;
DEFAULT_PROJECT_ID="tsb-in-a-box" ;
DEFAULT_VM_DISK="20GB" ;
DEFAULT_VM_MACHINE_TYPE="n1-standard-8" ;
DEFAULT_VM_NAME="tsb-single-vm" ;
DEFAULT_VM_SSH_PUBLIC_KEY="${HOME}/.ssh/id_rsa.pub" ;
DEFAULT_VM_SSH_PRIVATE_KEY="${HOME}/.ssh/id_rsa" ;
DEFAULT_VM_ZONE="europe-west1-b" ;

DEFAULT_IMAGE_FAMILTY="ubuntu-pro-2204-lts" ;
DEFAULT_IMAGE_PROJECT="ubuntu-os-pro-cloud" ;
DEFAULT_BOOT_DISK_TYPE="pd-ssd" ;

# Start a gcp project
#   args:
#     (1) project billing account (default: "0183E5-447B34-776DEB")
#     (2) project description (default: "TSB in  a Box")
#     (3) project id (default: "tsb-in-a-box")
function start_gcp_project() {
  [[ -z "${1}" ]] && local project_billing_account="${DEFAULT_PROJECT_BILLING_ACCOUNT}" || local project_billing_account="${1}" ;
  [[ -z "${2}" ]] && local project_description="${DEFAULT_PROJECT_DESCRIPTION}" || local project_description="${2}" ;
  [[ -z "${3}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${3}" ;

  existing_project=$(gcloud projects list --filter="projectId:${project_id}" --format="value(projectId)") ;
  if [ -z "${existing_project}" ]; then
    echo "Creating project '${project_id}'" ;
    if ! gcloud projects create "${project_id}" --name="${project_description}" --set-as-default; then
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
#     (1) project billing account (default: "0183E5-447B34-776DEB")
#     (2) project id (default: "tsb-in-a-box")
function link_gcp_project_to_billing_account() {
  [[ -z "${1}" ]] && local project_billing_account="${DEFAULT_PROJECT_BILLING_ACCOUNT}" || local project_billing_account="${1}" ;
  [[ -z "${2}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${2}" ;

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
#     (1) gcp project
#     (2) gcp service
function enable_gcp_service_on_project() {
  [[ -z "${1}" ]] && print_error "Please provide gcp project as 1st argument" && return 2 || local project="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide gcp service as 2nd argument" && return 2 || local service="${2}" ;

  if gcloud services list --enabled --filter="name:${service}" --project="${project_id}" --format="value(name)" | grep -q "${service}"; then
    echo "Service '${service}' is already enabled on project '${project_id}'."
    return
  fi

  echo "Enabling service '${service}' on project '${project_id}'..."
  if ! gcloud services enable "${service}" --project="${project_id}"; then
    print_error "Failed to enable service '${service}' on project '${project_id}'."
    exit 1
  fi

  echo -n "Waiting for ${service} to be enabled..."
  while ! gcloud services list --enabled --filter="name:${service}" --project="${project}" --format="value(name)" | grep -q "${service}"; do
    echo -n "." ;
    sleep 10 ;
  done
  echo "DONE"
  echo "${service} is now enabled in project ${project}" ;
}

# Create a gcp firewall rule
#   args:
#     (1) firewall rule name
#     (2) firewall rule description
#     (3) firewall rule network
#     (4) firewall rule source ranges
#     (5) firewall rule target tags
#     (6) firewall rule allow
#     (7) firewall rule project
function create_firewall_rule() {
  [[ -z "${1}" ]] && print_error "Please provide firewall rule name as 1st argument" && return 2 || local firewall_rule_name="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide firewall rule description as 2nd argument" && return 2 || local firewall_rule_description="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide firewall rule network as 3rd argument" && return 2 || local firewall_rule_network="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide firewall rule source ranges as 4th argument" && return 2 || local firewall_rule_source_ranges="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide firewall rule target tags as 5th argument" && return 2 || local firewall_rule_target_tags="${5}" ;
  [[ -z "${6}" ]] && print_error "Please provide firewall rule allow as 6th argument" && return 2 || local firewall_rule_allow="${6}" ;
  [[ -z "${7}" ]] && print_error "Please provide firewall rule project as 7th argument" && return 2 || local firewall_rule_project="${7}" ;

  existing_firewall_rule=$(gcloud compute firewall-rules list --filter="name=(${firewall_rule_name})" --project="${firewall_rule_project}" --format="value(name)") ;
  if [ -z "${existing_firewall_rule}" ]; then
    echo "Creating firewall rule '${firewall_rule_name}'"
    gcloud compute firewall-rules create "${firewall_rule_name}" \
      --description="${firewall_rule_description}" \
      --network="${firewall_rule_network}" \
      --source-ranges="${firewall_rule_source_ranges}" \
      --target-tags="${firewall_rule_target_tags}" \
      --allow="${firewall_rule_allow}" \
      --project="${firewall_rule_project}" ;
    echo "Firewall rule '${firewall_rule_name}' created" ;
  else
    echo "Firewall rule '${firewall_rule_name}' already exists" ;
  fi
}

# Start a gcp cloud Ubuntu VM
#   args:
#     (1) project billing account (default: "0183E5-447B34-776DEB")
#     (2) project description (default: "TSB in  a Box")
#     (3) project id (default: tsb-in-a-box)
#     (4) vm disk (default: 20GB)
#     (5) vm machine type (default: n1-standard-8)
#     (6) vm name (default: tsb-single-vm)
#     (7) vm ssh public key (default: ${HOME}/.ssh/id_rsa.pub)
#     (8) vm zone (default: europe-west1-b)
function start_gcp_vm() {
  [[ -z "${1}" ]] && local project_billing_account="${DEFAULT_PROJECT_BILLING_ACCOUNT}" || local project_billing_account="${1}" ;
  [[ -z "${2}" ]] && local project_description="${DEFAULT_PROJECT_DESCRIPTION}" || local project_description="${2}" ;
  [[ -z "${3}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${3}" ;
  [[ -z "${4}" ]] && local vm_disk="${DEFAULT_VM_DISK}" || local vm_disk="${4}" ;
  [[ -z "${5}" ]] && local vm_machine_type="${DEFAULT_VM_MACHINE_TYPE}" || local vm_machine_type="${5}" ;
  [[ -z "${6}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${6}" ;
  [[ -z "${7}" ]] && local vm_ssh_public_key="${DEFAULT_VM_SSH_PUBLIC_KEY}" || local vm_ssh_public_key="${7}" ;
  [[ -z "${8}" ]] && local vm_zone="${DEFAULT_VM_ZONE}" || local vm_zone="${8}" ;

  start_gcp_project "${project_billing_account}" "${project_description}" "${project_id}" ;
  link_gcp_project_to_billing_account "${project_billing_account}" "${project_id}" ;
  enable_gcp_service_on_project "${project_id}" "compute.googleapis.com" ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_vm}" ]; then
    echo "Creating VM instance '${vm_name}' in project '${project_id}'"
    gcloud compute instances create "${vm_name}" \
      --boot-disk-size="${vm_disk}" \
      --boot-disk-type="${DEFAULT_BOOT_DISK_TYPE}" \
      --image-family="${DEFAULT_IMAGE_FAMILTY}" \
      --image-project="${DEFAULT_IMAGE_PROJECT}" \
      --machine-type="${vm_machine_type}" \
      --metadata="ssh-keys=ubuntu:$(<"${vm_ssh_public_key}"),user-data=$(<"${HELPERS_DIR}/templates/gcp-cloud-init.tpl")" \
      --network="default" \
      --project="${project_id}" \
      --tags="http-server,https-server" \
      --zone="${vm_zone}" ;
    echo "VM instance '${vm_name}' created in project '${project_id}'" ;
  else
    echo "VM instance '${vm_name}' already exists in project '${project_id}'" ;
  fi

  create_firewall_rule "default-allow-http" "Allow HTTP" "default" "0.0.0.0/0" "http-server" "tcp:80,tcp:8080" "${project_id}" ;
  create_firewall_rule "default-allow-https" "Allow HTTPS" "default" "0.0.0.0/0" "https-server" "tcp:443,tcp:8443" "${project_id}" ;
}

# This function stops the gcp cloud Ubuntu VM
#   args:
#     (1) project id (default: "tsb-in-a-box")
#     (2) vm name (default: tsb-single-vm)
#     (3) vm zone (default: europe-west1-b)
function stop_gcp_vm() {
  [[ -z "${1}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${1}" ;
  [[ -z "${2}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${2}" ;
  [[ -z "${3}" ]] && local vm_zone="${DEFAULT_VM_ZONE}" || local vm_zone="${3}" ;

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
#     (1) project id (default: "tsb-in-a-box")
#     (2) vm name (default: tsb-single-vm)
#     (3) vm zone (default: europe-west1-b)
function delete_gcp_vm() {
  [[ -z "${1}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${1}" ;
  [[ -z "${2}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${2}" ;
  [[ -z "${3}" ]] && local vm_zone="${DEFAULT_VM_ZONE}" || local vm_zone="${3}" ;

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
#     (1) project id (default: "tsb-in-a-box")
#     (2) vm name (default: tsb-single-vm)
#     (3) vm zone (default: europe-west1-b)
function shell_gcp_vm() {
  [[ -z "${1}" ]] && local project_id="${DEFAULT_PROJECT_ID}" || local project_id="${1}" ;
  [[ -z "${2}" ]] && local vm_name="${DEFAULT_VM_NAME}" || local vm_name="${2}" ;
  [[ -z "${3}" ]] && local vm_zone="${DEFAULT_VM_ZONE}" || local vm_zone="${3}" ;

  existing_vm=$(gcloud compute instances list --filter="name:(${vm_name}) AND zone:(${vm_zone})" --project="${project_id}" --format="value(name)") ;
  if [ -z "${existing_vm}" ]; then
    print_error "VM instance '${vm_name}' does not exist in project '${project_id}'" ;
    exit 1 ;
  else
    echo "Spawn a shell in VM instance '${vm_name}' in project '${project_id}'"
    gcloud compute ssh "${vm_name}" \
      --project="${project_id}" \
      --zone="${vm_zone}" -- "sudo su ubuntu";
  fi
}
