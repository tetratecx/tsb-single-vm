#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
SCENARIO_DIR=$(get_scenario_dir)

ACTION=${1}

if [[ ${ACTION} = "deploy" ]]; then
  ${SCENARIO_DIR}/run.sh ${ROOT_DIR} deploy
  exit 0
fi

if [[ ${ACTION} = "undeploy" ]]; then
  ${SCENARIO_DIR}/run.sh ${ROOT_DIR} undeploy
  exit 0
fi

if [[ ${ACTION} = "info" ]]; then
  ${SCENARIO_DIR}/run.sh ${ROOT_DIR} info
  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
