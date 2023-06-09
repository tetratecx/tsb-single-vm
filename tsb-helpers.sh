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
  echo "Wait for cluster ${1} to be onboarded"
  while ! tctl experimental status cs ${1} | grep "Cluster onboarded" &>/dev/null ; do
    sleep 5 ;
    echo -n "."
  done
  echo "DONE"
}
