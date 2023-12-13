#!/usr/bin/env bash
SCENARIO_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;

if [[ -z "${BASE_DIR}" ]]; then
    echo "BASE_DIR environment variable is not set or is empty" ;
    exit 1 ;
fi

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/certs.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh" ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --deploy: delpoy the scenario" ;
  echo "  --undeploy: undeploy the scenario" ;
  echo "  --info: print info about the scenario" ;
}


# This function deploys the scenario.
#
function deploy() {

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Deploy tsb cluster, organization-settings and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f "${SCENARIO_DIR}/tsb/01-cluster.yaml" ;
  sleep 5 ;
  # wait_cluster_onboarded main ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-organization-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/03-tenant.yaml" ;

  # Deploy kubernetes objects in main cluster
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/01-namespace.yaml" ;
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/02-traffic-client.yaml" ;
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/03-spray-out-parallel.yaml" ;
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/04-spray-out-serial.yaml" ;
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/05-daisy-chain-single.yaml" ;
  kubectl --context main apply -f "${SCENARIO_DIR}/k8s/06-daisy-chain-tree.yaml" ;

  # Deploy tsb objects
  tctl apply -f "${SCENARIO_DIR}/tsb/04-workspace.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/05-group.yaml" ;
}


# This function undeploys the scenario.
#
function undeploy() {

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Delete tsb configuration
  for tsb_yaml_files in $(find "${SCENARIO_DIR}/tsb" -name '*.yaml' ! -name '01-cluster.yaml' | sort -r) ; do
    echo "Going to delete ${tsb_yaml_files}" ;
    tctl delete -f "${tsb_yaml_files}" 2>/dev/null ;
    sleep 1 ;
  done

  echo "Sleep 30 seconds to allow TSB to delete all the objects" ;
  sleep 30 ;

  # Delete kubernetes configuration in mgmt, active and standby cluster
  kubectl --context main delete -f "${SCENARIO_DIR}/k8s/01-namespace.yaml" --wait=true 2>/dev/null ;
}


# This function prints info about the scenario.
#
function info() {

  print_info "******************************" ;
  print_info "*** Observability Commands ***" ;
  print_info "******************************" ;
  echo ;
  echo "Traffic for AppA: spray-out-parallel" ;
  print_command "kubectl exec -n ns-a -it \"$(kubectl get pods -l app=client -o jsonpath="{.items[0].metadata.name}" -n ns-a)\" -- fortio load  -t 0 -H \"X-B3-Sampled:1\" svc-a:8080" ;
  echo "Traffic for AppB: spray-out-serial" ;
  print_command "kubectl exec -n ns-a -it \"$(kubectl get pods -l app=client -o jsonpath="{.items[0].metadata.name}" -n ns-a)\" -- fortio load  -t 0 -H \"X-B3-Sampled:1\" svc-a:8080" ;
  echo "Traffic for AppC: daisy-chain-single" ;
  print_command "kubectl exec -n ns-a -it \"$(kubectl get pods -l app=client -o jsonpath="{.items[0].metadata.name}" -n ns-a)\" -- fortio load  -t 0 -H \"X-B3-Sampled:1\" svc-a:8080" ;
  echo "Traffic for AppD: daisy-chain-tree" ;
  print_command "kubectl exec -n ns-a -it \"$(kubectl get pods -l app=client -o jsonpath="{.items[0].metadata.name}" -n ns-a)\" -- fortio load  -t 0 -H \"X-B3-Sampled:1\" svc-a:8080" ;
  echo ;
  echo "All at once in a loop" ;
  print_command "for i in a b c d; do
  kubectl exec -n ns-${i} -it \"$(kubectl get pods -l app=client -o jsonpath=\"{.items[0].metadata.name}\" -n ns-${i})\" -- fortio load  -t 0 -H \"X-B3-Sampled:1\" svc-${i}:8080 &
done" ;
  echo ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --deploy)
    deploy ;
    ;;
  --undeploy)
    undeploy ;
    ;;
  --info)
    info ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac