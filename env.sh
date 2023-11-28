#!/usr/bin/env bash
BASE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
OUTPUT_DIR=${BASE_DIR}/output ;

# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

ENV_CONF=env.json ;
if ! [[ -f "${ENV_CONF}" ]] ; then
  print_error "Cannot find ${ENV_CONF}, aborting..." ;
  exit 1 ;
fi

if ! which jq &>/dev/null ; then
  print_error "Package for json parsing jq is not installed, please run 'sudo apt-get install -y jq'" ;
  exit 2 ;
fi

if ! jq -r ".topology" "${ENV_CONF}" &>/dev/null ; then
  print_error "Unable to parse topology from ${ENV_CONF}, aborting..." ;
  exit 3 ;
fi

function get_topology {
  jq -r ".topology" "${ENV_CONF}" ;
}
function get_scenario {
  jq -r ".scenario" "${ENV_CONF}" ;
}
function get_topology_dir {
  echo "${BASE_DIR}/topologies/$(get_topology)" ;
}
function get_scenario_dir {
  echo "${BASE_DIR}/topologies/$(get_topology)/scenarios/$(get_scenario)" ;
}

TOPOLOGY_CONF=$(get_topology_dir)/infra.json ;
if ! [[ -f "${TOPOLOGY_CONF}" ]] ; then
  print_error "Cannot find ${TOPOLOGY_CONF}, aborting..." ;
  exit 4 ;
fi

###### MP Cluster ######

function get_mp_k8s_provider {
  jq -r ".mp_cluster.k8s_provider" "${TOPOLOGY_CONF}" ;
}

function get_mp_k8s_version {
  jq -r ".mp_cluster.k8s_version" "${TOPOLOGY_CONF}" ;
}

function get_mp_name {
  jq -r ".mp_cluster.name" "${TOPOLOGY_CONF}" ;
}

function get_mp_region {
  jq -r ".mp_cluster.region" "${TOPOLOGY_CONF}" ;
}

function get_mp_trust_domain {
  jq -r ".mp_cluster.trust_domain" "${TOPOLOGY_CONF}" ;
}

function get_mp_vm_count {
  jq -r ".mp_cluster.vms | length" "${TOPOLOGY_CONF}" ;
}

function get_mp_vm_image_by_index {
  i=${1} ;
  jq -r ".mp_cluster.vms[${i}].image" "${TOPOLOGY_CONF}" ;
}

function get_mp_vm_name_by_index {
  i=${1} ;
  jq -r ".mp_cluster.vms[${i}].name" "${TOPOLOGY_CONF}" ;
}

function get_mp_zone {
  jq -r ".mp_cluster.zone" "${TOPOLOGY_CONF}" ;
}

###### CP Clusters ######

function get_cp_count {
  jq -r ".cp_clusters | length" "${TOPOLOGY_CONF}" ;
}

function get_cp_k8s_provider_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].k8s_provider" "${TOPOLOGY_CONF}" ;
}

function get_cp_k8s_version_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].k8s_version" "${TOPOLOGY_CONF}" ;
}

function get_cp_name_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].name" "${TOPOLOGY_CONF}" ;
}

function get_cp_vm_count_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].vms | length" "${TOPOLOGY_CONF}" ;
}

function get_cp_vm_image_by_index {
  i=${1} ;
  j=${2} ;
  jq -r ".cp_clusters[${i}].vms[${j}].image" "${TOPOLOGY_CONF}" ;
}

function get_cp_vm_name_by_index {
  i=${1} ;
  j=${2} ;
  jq -r ".cp_clusters[${i}].vms[${j}].name" "${TOPOLOGY_CONF}" ;
}

function get_cp_region_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].region" "${TOPOLOGY_CONF}" ;
}

function get_cp_trust_domain_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].trust_domain" "${TOPOLOGY_CONF}" ;
}

function get_cp_zone_by_index {
  i=${1} ;
  jq -r ".cp_clusters[${i}].zone" "${TOPOLOGY_CONF}" ;
}


### TSB Configuration ###
function get_tetrate_repo_password {
  jq -r ".tsb.tetrate_repo.password" "${ENV_CONF}" ;
}

function get_tetrate_repo_user {
  jq -r ".tsb.tetrate_repo.user" "${ENV_CONF}" ;
}

function get_tsb_install_method {
  jq -r ".tsb.install_method" "${ENV_CONF}" ;
}

function get_tsb_istio_version {
  jq -r ".tsb.istio_version" "${ENV_CONF}" ;
}

function get_tsb_version {
  jq -r ".tsb.version" "${ENV_CONF}" ;
}

### VM Configuration ###
function get_vm_kind {
  jq -r ".vm.kind" "${ENV_CONF}" ;
}

#### VM Multipass Configuration ####
function get_multipass_vm_cpu {
  jq -r ".vm.multipass.vm_cpus" "${ENV_CONF}" ;
}

function get_multipass_vm_disk {
  jq -r ".vm.multipass.vm_disk" "${ENV_CONF}" ;
}

function get_multipass_vm_mem {
  jq -r ".vm.multipass.vm_mem" "${ENV_CONF}" ;
}

function get_multipass_vm_name {
  jq -r ".vm.multipass.vm_name" "${ENV_CONF}" ;
}


#### VM GCP Configuration ####
function get_gcp_project_billing_account {
  jq -r ".vm.gcp.project_billing_account" "${ENV_CONF}" ;
}

function get_gcp_project_description {
  jq -r ".vm.gcp.project_description" "${ENV_CONF}" ;
}

function get_gcp_project_id {
  jq -r ".vm.gcp.project_id" "${ENV_CONF}" ;
}

function get_gcp_project_name {
  jq -r ".vm.gcp.project_name" "${ENV_CONF}" ;
}

function get_gcp_vm_disk {
  jq -r ".vm.gcp.vm_disk" "${ENV_CONF}" ;
}

function get_gcp_vm_machine_type {
  jq -r ".vm.gcp.vm_machine_type" "${ENV_CONF}" ;
}

function get_gcp_vm_name {
  jq -r ".vm.gcp.vm_name" "${ENV_CONF}" ;
}

function get_gcp_vm_ssh_key {
  jq -r ".vm.gcp.vm_ssh_key" "${ENV_CONF}" ;
}

function get_gcp_vm_zone {
  jq -r ".vm.gcp.vm_zone" "${ENV_CONF}" ;
}


### TSB installation templates files ###
function get_mp_cp_cr_template_file {
  echo "$(get_topology_dir)/$(jq -r ".mp_cluster.templates.cp_tctl" "${TOPOLOGY_CONF}")" ;
}

function get_mp_cp_helm_template_file {
  echo "$(get_topology_dir)/$(jq -r ".mp_cluster.templates.cp_helm" "${TOPOLOGY_CONF}")" ;
}

function get_mp_mp_cr_template_file {
  echo "$(get_topology_dir)/$(jq -r ".mp_cluster.templates.mp_tctl" "${TOPOLOGY_CONF}")" ;
}

function get_mp_mp_helm_template_file {
  echo "$(get_topology_dir)/$(jq -r ".mp_cluster.templates.mp_helm" "${TOPOLOGY_CONF}")" ;
}

function get_cp_cr_template_file_by_index {
  i=${1} ;
  echo "$(get_topology_dir)/$(jq -r ".cp_clusters[${i}].templates.cp_tctl" "${TOPOLOGY_CONF}")" ;
}

function get_cp_helm_template_file_by_index {
  i=${1} ;
  echo "$(get_topology_dir)/$(jq -r ".cp_clusters[${i}].templates.cp_helm" "${TOPOLOGY_CONF}")" ;
}

### Output directories ###
function get_certs_output_dir {
  mkdir -p "${OUTPUT_DIR}/certs" ;
  echo "${OUTPUT_DIR}/certs" ;
}

function get_mp_output_dir {
  mkdir -p "${OUTPUT_DIR}/$(get_mp_name)" ;
  echo "${OUTPUT_DIR}/$(get_mp_name)" ;
}

function get_cp_output_dir {
  i=${1} ;
  mkdir -p "${OUTPUT_DIR}/$(get_cp_name_by_index ${i})" ;
  echo "${OUTPUT_DIR}/$(get_cp_name_by_index ${i})" ;
}

### Parsing Tests
#
# get_k8s_version;
# get_mp_name;
# get_mp_region;
# get_mp_trust_domain;
# get_mp_vm_count;
# get_mp_vm_image_by_index 0;
# get_mp_vm_image_by_index 1;
# get_mp_vm_name_by_index 0;
# get_mp_vm_name_by_index 1;
# get_mp_zone;
# get_cp_count;
# get_cp_name_by_index 0;
# get_cp_region_by_index 0;
# get_cp_trust_domain_by_index 0;
# get_cp_zone_by_index 0;
# get_cp_name_by_index 1;
# get_cp_vm_count_by_index 0;
# get_cp_vm_name_by_index 0 0;
# get_cp_vm_name_by_index 0 1;
# get_cp_vm_image_by_index 0 0;
# get_cp_vm_image_by_index 0 1;
# get_cp_vm_count_by_index 1;
# get_cp_vm_name_by_index 1 0;
# get_cp_vm_name_by_index 1 1;
# get_cp_vm_image_by_index 1 0;
# get_cp_vm_image_by_index 1 1;
# get_cp_region_by_index 1;
# get_cp_trust_domain_by_index 1;
# get_cp_zone_by_index 1;

# get_tsb_repo_password;
# get_tsb_repo_url;
# get_tsb_repo_user;
# get_tsb_version;
# get_tsb_istio_version;

# get_certs_output_dir;
# get_mp_output_dir;
# get_cp_output_dir 0;
# get_cp_output_dir 1;

# get_mp_cp_cr_template_file;
# get_mp_cp_helm_template_file;
# get_mp_mp_cr_template_file;
# get_mp_mp_helm_template_file;
# get_cp_cr_template_file_by_index 0;
# get_cp_cr_template_file_by_index 1;
# get_cp_helm_template_file_by_index 0;
# get_cp_helm_template_file_by_index 1;

# get_scenario_dir;
