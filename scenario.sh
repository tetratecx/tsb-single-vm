#!/usr/bin/env bash
BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;

SCENARIO=$(get_scenario) ;
SCENARIO_DIR=$(get_scenario_dir) ;

ACTION=${1} ;


# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --deploy: deploy scenario '${SCENARIO}'" ;
  echo "  --undeploy: undeploy scenario '${SCENARIO}'" ;
  echo "  --info: show info for scenario '${SCENARIO}'" ;
}

# This function deploys the scenario.
#
function deploy() {
  print_info "Start deploying scenario '${SCENARIO}'" ;
  BASE_DIR=${BASE_DIR} "${SCENARIO_DIR}/run.sh" --deploy ;
  print_info "Finished deploying scenario '${SCENARIO}'" ;
}

# This function undeploys the scenario.
#
function undeploy() {
  print_info "Start undeploying scenario '${SCENARIO}'" ;
  BASE_DIR=${BASE_DIR} "${SCENARIO_DIR}/run.sh" --undeploy ;
  print_info "Finished undeploying scenario '${SCENARIO}'" ;
}


# This function shows info for the scenario.
#
function info() {
  BASE_DIR=${BASE_DIR} "${SCENARIO_DIR}/run.sh" --info ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --deploy)
    print_stage "Going to deploy scenario '${SCENARIO}'" ;
    deploy ;
    ;;
  --undeploy)
    print_stage "Going to undeploy scenario '${SCENARIO}'" ;
    undeploy ;
    ;;
  --info)
    print_stage "Going to print info for scenario '${SCENARIO}'" ;
    info ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac