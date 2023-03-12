#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
SCENARIO=$(get_scenario)
SCENARIO_DIR=$(get_scenario_dir)

ACTION=${1}

if [[ ${ACTION} = "deploy" ]]; then
  print_info "Start deploying scenario ${SCENARIO}"
  ${SCENARIO_DIR}/run.sh ${ROOT_DIR} deploy
  print_info "Finished deploying scenario ${SCENARIO}"
  exit 0
fi

if [[ ${ACTION} = "undeploy" ]]; then
  print_info "Start undeploying scenario ${SCENARIO}"
  ${SCENARIO_DIR}/run.sh ${ROOT_DIR} undeploy
  print_info "Finished undeploying scenario ${SCENARIO}"
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
