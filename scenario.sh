#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/env.sh
source ${ROOT_DIR}/certs.sh

ACTION=${1}

SCENARIO_DIR=$(get_scenario_dir)

if [[ ${ACTION} = "deploy" ]]; then
  ${SCENARIO_DIR}/run.sh deploy
  exit 0
fi

if [[ ${ACTION} = "undeploy" ]]; then
  ${SCENARIO_DIR}/run.sh undeploy
  exit 0
fi

if [[ ${ACTION} = "info" ]]; then
  ${SCENARIO_DIR}/run.sh info
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
