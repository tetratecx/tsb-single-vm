#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

ACTION=${1} ;

TSB_HELM_REPO="https://charts.dl.tetrate.io/public/helm/charts" ;
MP_HELM_CHART="tetrate-tsb-charts/managementplane" ;
CP_HELM_CHART="tetrate-tsb-charts/controlplane" ;


# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 " ;
  echo "Upgrades TSB to new version set in env.json file" ;
}

# This function backs up install manifests
#
function backup_manifests() {
  local clusters=( c1 c2 )
  local mp="t1"
  local backup_dir="${BASE_DIR}/upgrade/backups"
  mkdir -p "${backup_dir}"
  print_info "Creating backups for clusters ${clusters} and mp ${mp} at ${backup_dir}" ;
  for cluster in "${clusters[@]}"; do
    #wait_cluster_onboarded "${cluster}" ;
    kubectl --context "${cluster}" get controlplane controlplane -n istio-system -oyaml > "${backup_dir}/${cluster}-controlplane-backup.yaml" ;
  done
  kubectl --context "${mp}" get controlplane controlplane -n istio-system -oyaml > "${backup_dir}/${mp}-managementplane-backup.yaml" ;
}

# This function brings new tctl version if needed
#
function upgrade_tctl() {
  local tctl_dir=$(which tctl)
  # As the output is TCTL version: v1.9.3, this brings only 1.9.3 using 'v' as separator
  local tctl_current_version=$(tctl version --local-only | cut -d 'v' -f3)
  # Present in env.json file
  local desired_tsb_version=$(get_tsb_version)
  local tctl_current_version_new_location="${tctl_dir}-${tctl_current_version}"
  if [[ "${tctl_current_version}" != "${desired_tsb_version}" ]]; then
    print_info "Updating tctl to version ${desired_tsb_version}" ;
    print_info "No worries, old tctl version  ${tctl_current_version} will be kept at " ;
    mv ${tctl_dir} "${tctl_current_version_new_location}"
    # TODO: DOWNLOAD NEW TCTL
  fi
}


# Main execution
#

backup_manifests
