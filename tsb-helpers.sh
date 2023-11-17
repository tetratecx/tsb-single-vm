#!/usr/bin/env bash

# Login as admin into tsb
#   args:
#     (1) organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide tsb organization as 1st argument" && return 2 || local organization="${1}" ;

  expect <<DONE
  spawn tctl login --username admin --password admin --org ${organization}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Wait for cluster to be onboarded
#   args:
#     (1) onboarding cluster name
function wait_cluster_onboarded {
  [[ -z "${1}" ]] && print_error "Please provide the onboarding cluster name as 1st argument" && return 2 || local cluster="${1}" ;
  echo "Wait for cluster ${cluster} to be onboarded"
  while ! tctl experimental status cluster ${cluster} | grep "Cluster onboarded" &>/dev/null ; do
    sleep 5 ;
    echo -n "."
  done
  echo "DONE"
}

function wait_clusters_onboarded {
  local clusters=("$@")
  for cluster in "${clusters[@]}"; do
    wait_cluster_onboarded $cluster
  done
}
