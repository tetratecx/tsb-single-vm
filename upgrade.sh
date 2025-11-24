#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
# BASE_DIR="$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tctl.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/debug.sh"

ACTION=${1}

TSB_HELM_REPO="https://charts.dl.tetrate.io/public/helm/charts"
MP_HELM_CHART="tetrate-tsb-charts/managementplane"
CP_HELM_CHART="tetrate-tsb-charts/controlplane"
LOCAL_REGISTRY="$(get_local_registry_endpoint)"
BASE_DIR_UPGRADE="${BASE_DIR}/upgrade"
CLUSTERS=( c1 c2 t1 )
MP="t1"

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 "
  echo "Upgrades TSB to new version set in env.json file"
}

# This function backs up install manifests
#
function backup_manifests() {
  local backup_dir="${BASE_DIR_UPGRADE}/backups"
  mkdir -p "${backup_dir}"
  print_info "Creating backups for clusters ${CLUSTERS} and mp ${MP} at ${backup_dir}"
  for cluster in "${CLUSTERS[@]}"; do
    kubectl --context "${cluster}" get controlplane -n istio-system -oyaml > "${backup_dir}/${cluster}-controlplane-backup.yaml"
  done
  kubectl --context "${MP}" get managementplane -n tsb -oyaml > "${backup_dir}/${MP}-managementplane-backup.yaml"
}

# This function brings new tctl version if needed
#
function upgrade_tctl() {
  # Present in env.json file under .tsb.upgrade.version_upgrade_target
  local desired_tsb_version=$(get_tsb_version_upgrade_target)

  # Check if version_upgrade_target is set
  if [[ -z "${desired_tsb_version}" || "${desired_tsb_version}" == "null" ]]; then
    print_error "No upgrade target version specified in env.json at .tsb.upgrade.version_upgrade_target"
    print_error "Please set the target version before running upgrade"
    exit 1
  fi

  # Use the modular upgrade function from helpers/tctl.sh
  if ! upgrade_tctl_to_version "${desired_tsb_version}"; then
    exit 1
  fi
}



function upgrade_mp_with_tctl() {
  local output_dir="${BASE_DIR_UPGRADE}/mp"
  mkdir -p "${output_dir}"
  print_info "${output_dir} created to store new mp operator yaml"

  tctl install manifest management-plane-operator \
      --registry "${LOCAL_REGISTRY}" \
      > "${output_dir}/managementplaneoperator.yaml" 2>&1

  if [[ $? -eq 0 ]]; then
    if [[ -s "${output_dir}/managementplaneoperator.yaml" ]]; then
      kubectl apply --context "${MP}" -f "${output_dir}/managementplaneoperator.yaml"
      print_info "Waiting for new CRD managementoperator to be processed"
      sleep 60
      kubectl get pod -n tsb --context "${MP}"
      print_command "$ tctl version"
      tctl version 2>&1
    else
      print_error "${output_dir}/managementplaneoperator.yaml is empty"
      exit 1
    fi
  else
    print_error "tctl install manifest management-plane-operator failed"
    exit 1
  fi

}

function upgrade_cp_with_tctl() {
  local output_dir="${BASE_DIR_UPGRADE}/cp"
  mkdir -p "${output_dir}"
  print_info "${output_dir} created to store new cp operator yaml"

  tctl install manifest cluster-operators \
      --registry "${LOCAL_REGISTRY}" \
      > "${output_dir}/clusteroperators.yaml" 2>&1

  if [[ $? -eq 0 ]]; then
    if [[ -s "${output_dir}/clusteroperators.yaml" ]]; then
      for cluster in "${CLUSTERS[@]}"; do
        print_info "Updating cluster ${cluster}"
        kubectl apply --context "${cluster}" -f "${output_dir}/clusteroperators.yaml"
        print_info "Waiting for new CRD cluster operator to be processed"
        sleep 60
        kubectl get pod -n istio-system --context "${cluster}"
      done
    else
      print_error "${output_dir}/clusteroperators.yaml is empty"
      exit 1
    fi
  else
    print_error "tctl install cluster-operators failed"
  fi
}



# Main execution
#

if [[ "$1" == "upgrade-tctl" ]]; then
  upgrade_tctl
  exit $?
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  backup_manifests
  upgrade_tctl

  # Get upgrade flags from env.json
  upgrade_mp_flag=$(get_tsb_version_upgrade_mp)
  upgrade_cp_flag=$(get_tsb_version_upgrade_cp)

  # Validate upgrade flags
  if [[ "${upgrade_mp_flag}" != "true" && "${upgrade_cp_flag}" != "true" ]]; then
    print_error "No components selected for upgrade"
    print_error "Set .tsb.upgrade.mp or .tsb.upgrade.cp to true in env.json"
    exit 1
  fi

  docker_remove_isolation
  restart_clusters_cps
  print_info "Using credentials present in env.json to sync images"
  sync_tsb_images "${LOCAL_REGISTRY}" "$(get_tetrate_repo_user)" "$(get_tetrate_repo_password)"

  # Upgrade management plane if flag is set
  if [[ "${upgrade_mp_flag}" == "true" ]]; then
    print_info "Upgrading management plane as .tsb.upgrade.mp is set to true"
    upgrade_mp_with_tctl
  else
    print_info "Skipping management plane upgrade as .tsb.upgrade.mp is not set to true"
  fi

  # Upgrade control plane if flag is set
  if [[ "${upgrade_cp_flag}" == "true" ]]; then
    print_info "Upgrading control plane as .tsb.upgrade.cp is set to true"
    upgrade_cp_with_tctl
  else
    print_info "Skipping control plane upgrade as .tsb.upgrade.cp is not set to true"
  fi

  tctl_fix_timeout
  login_tsb_admin
  for cluster in "${CLUSTERS[@]}"; do
    tctl status cluster "${cluster}" 2>/dev/null ||  tctl status cluster "${cluster}"
  done
fi
