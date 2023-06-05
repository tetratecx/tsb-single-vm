#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

# Login as admin into tsb
#   args:
#     (1) tsb organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide tsb organization as 1st argument" && return 2 || local organization="${1}" ;

  expect <<DONE
  spawn tctl login --username admin --password admin --org ${organization}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

if [[ ${ACTION} = "deploy" ]]; then

  exit 0
fi


if [[ ${ACTION} = "undeploy" ]]; then

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
