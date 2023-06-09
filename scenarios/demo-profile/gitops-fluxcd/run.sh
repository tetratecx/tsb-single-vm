#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${ROOT_DIR}/tsb-helpers.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

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
