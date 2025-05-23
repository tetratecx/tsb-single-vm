#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh"
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh"
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

# This function gets local version in format 1.9.3
#
function get_tsb_local_version() {
  tctl version --local-only | cut -d 'v' -f3
}
# This function brings new tctl version if needed
#
function upgrade_tctl() {
  local tctl_dir=$(which tctl)
  # As the output is TCTL version: v1.9.3, this brings only 1.9.3 using 'v' as separator
  local tctl_current_version=$(get_tsb_local_version)
  # Present in env.json file
  local desired_tsb_version=$(get_tsb_version)
  local tctl_current_version_new_location="${tctl_dir}-${tctl_current_version}"
  if [[ "${tctl_current_version}" != "${desired_tsb_version}" ]]; then
    print_info "Updating tctl to version ${desired_tsb_version}"
    print_info "No worries, old tctl version ${tctl_current_version} will be kept at ${tctl_current_version_new_location}"
    sudo mv ${tctl_dir} "${tctl_current_version_new_location}"

    local architecture; architecture=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm64\|aarch64/arm64/')
    curl -Lo /tmp/tctl "https://binaries.dl.tetrate.io/public/raw/versions/linux-${architecture}-${desired_tsb_version}/tctl"
    chmod +x /tmp/tctl
    sudo install /tmp/tctl /usr/local/bin/tctl

    tctl_current_version=$(get_tsb_local_version)
    if [[ "${tctl_current_version}" != "${desired_tsb_version}" ]]; then
      tctl_current_version=$(tctl version)
      print_error "tctl version --local-only output does not match with your desired version"
      print_error "New version is ${tctl_current_version}"
    fi
  else
    print_error "You are trying to update to the same version. Go to env.json .tsb.version and change it"
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
backup_manifests
upgrade_tctl
docker_remove_isolation
restart_clusters_cps
print_info "Using credentials present in env.json to sync images"
sync_tsb_images "${LOCAL_REGISTRY}" "$(get_tetrate_repo_user)" "$(get_tetrate_repo_password)"
upgrade_mp_with_tctl
upgrade_cp_with_tctl
tctl_fix_timeout
login_tsb_admin
for cluster in "${CLUSTERS[@]}"; do
  tctl status cluster "${cluster}" 2>/dev/null ||  tctl x status cluster "${cluster}"
done
