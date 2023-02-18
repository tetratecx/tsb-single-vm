#!/usr/bin/env bash

ENV_CONF=environment.json
if ! [[ -f "${ENV_CONF}" ]] ; then
  echo "Cannot find ${ENV_CONF}, aborting..."
  exit 1
fi

if ! cat ${ENV_CONF} | jq -r ".infra_json" &>/dev/null ; then
  echo "Unable to parse infra_json from ${ENV_CONF}, aborting..."
  exit 2
fi

INFRA_CONF=$(cat ${ENV_CONF} | jq -r ".infra_json")
if ! [[ -f "${INFRA_CONF}" ]] ; then
  echo "Cannot find ${INFRA_CONF}, aborting..."
  exit 3
fi

### Infra Configuration ###

function get_istioctl_version {
  cat ${INFRA_CONF} | jq -r ".istioctl_version"
}

function get_k8s_version {
  cat ${INFRA_CONF} | jq -r ".k8s_version"
}

###### MP Cluster ######

function get_mp_minikube_profile {
  echo $(cat ${INFRA_CONF} | jq -r ".mp_cluster.name")-m1
}

function get_mp_name {
  cat ${INFRA_CONF} | jq -r ".mp_cluster.name"
}

function get_mp_region {
  cat ${INFRA_CONF} | jq -r ".mp_cluster.region"
}

function get_mp_vm_count {
  cat ${INFRA_CONF} | jq -r ".mp_cluster.vms[].name" | wc -l | tr -d ' '
}

function get_mp_vm_image_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".mp_cluster.vms[${i}].image"
}

function get_mp_vm_name_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".mp_cluster.vms[${i}].name"
}

function get_mp_zone {
  cat ${INFRA_CONF} | jq -r ".mp_cluster.zone"
}

###### CP Clusters ######

function get_cp_count {
  cat ${INFRA_CONF} | jq -r ".cp_clusters[].name" | wc -l | tr -d ' '
}

function get_cp_minikube_profile_by_index {
  i=${1}
  echo $(cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].name")-m$((i+2))
}

function get_cp_name_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].name"
}

function get_cp_vm_count_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].vms[].name" | wc -l | tr -d ' '
}

function get_cp_vm_image_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].vms[${j}].image"
}

function get_cp_vm_name_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].vms[${j}].name"
}

function get_cp_region_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].region"
}

function get_cp_zone_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".cp_clusters[${i}].zone"
}


### TSB Configuration ###

function get_tsb_apikey {
  cat ${ENV_CONF} | jq -r ".tsb.apikey"
}

function get_tsb_repo {
  cat ${ENV_CONF} | jq -r ".tsb.repo"
}

function get_tsb_username {
  cat ${ENV_CONF} | jq -r ".tsb.username"
}

function get_tsb_version {
  cat ${ENV_CONF} | jq -r ".tsb.version"
}

### Parsing Tests

# get_istioctl_version;
# get_k8s_version;
# get_mp_minikube_profile;
# get_mp_name;
# get_mp_region;
# get_mp_vm_count;
# get_mp_vm_image_by_index 0;
# get_mp_vm_image_by_index 1;
# get_mp_vm_name_by_index 0;
# get_mp_vm_name_by_index 1;
# get_mp_zone;
# get_cp_count;
# get_cp_name_by_index 0;
# get_cp_region_by_index 0;
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
# get_cp_zone_by_index 1;
# get_cp_minikube_profile_by_index 0;
# get_cp_minikube_profile_by_index 1;