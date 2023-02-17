#!/usr/bin/env bash

INFRA_CONF=infra-config.json

# Top level configuration

function get_istioctl_version {
  cat ${INFRA_CONF} | jq -r ".istioctl_version"
}

function get_k8s_version {
  cat ${INFRA_CONF} | jq -r ".k8s_version"
}

function get_tsb_image_sync_apikey {
  cat ${INFRA_CONF} | jq -r ".tsb_image_sync_apikey"
}

function get_tsb_image_sync_repo {
  cat ${INFRA_CONF} | jq -r ".tsb_image_sync_repo"
}

function get_tsb_image_sync_username {
  cat ${INFRA_CONF} | jq -r ".tsb_image_sync_username"
}

function get_tsb_org {
  cat ${INFRA_CONF} | jq -r ".tsb_org"
}

function get_tsb_password {
  cat ${INFRA_CONF} | jq -r ".tsb_password"
}

function get_tsb_version {
  cat ${INFRA_CONF} | jq -r ".tsb_version"
}

# MP configuration

function get_mp_minikube_profile {
  echo $(cat ${INFRA_CONF} | jq -r ".tsb_mp.name")-m1
}

function get_mp_name {
  cat ${INFRA_CONF} | jq -r ".tsb_mp.name"
}

function get_mp_region {
  cat ${INFRA_CONF} | jq -r ".tsb_mp.region"
}

function get_mp_vm_count {
  cat ${INFRA_CONF} | jq -r ".tsb_mp.vms[].name" | wc -l | tr -d ' '
}

function get_mp_vm_image_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".tsb_mp.vms[${i}].image"
}

function get_mp_vm_name_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".tsb_mp.vms[${i}].name"
}

function get_mp_zone {
  cat ${INFRA_CONF} | jq -r ".tsb_mp.zone"
}

# CP configuration

function get_cp_count {
  cat ${INFRA_CONF} | jq -r ".tsb_cp[].name" | wc -l | tr -d ' '
}

function get_cp_minikube_profile_by_index {
  i=${1}
  echo $(cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].name")-m$((i+2))
}

function get_cp_name_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].name"
}

function get_cp_vm_count_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].vms[].name" | wc -l | tr -d ' '
}

function get_cp_vm_image_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].vms[${j}].image"
}

function get_cp_vm_name_by_index {
  i=${1}
  j=${2}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].vms[${j}].name"
}

function get_cp_region_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].region"
}

function get_cp_zone_by_index {
  i=${1}
  cat ${INFRA_CONF} | jq -r ".tsb_cp[${i}].zone"
}

# Tests

# get_istioctl_version;
# get_k8s_version;
# get_tsb_image_sync_apikey;
# get_tsb_image_sync_repo;
# get_tsb_image_sync_username;
# get_tsb_org;
# get_tsb_password;
# get_tsb_version;
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
# get_cp_region_by_index 1;
# get_cp_zone_by_index 1;
# get_cp_minikube_profile_by_index 0;
# get_cp_minikube_profile_by_index 1;