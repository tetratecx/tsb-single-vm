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
  print_command "kubectl exec -n ns-a -it \"\$(kubectl get pods -l app=client -o jsonpath='{.items[0].metadata.name}' -n ns-a)\" -- fortio load -allow-initial-errors -t 0 -H \"X-B3-Sampled:1\" http://svc-a:8080" ;
  echo "Traffic for AppB: spray-out-serial" ;
  print_command "kubectl exec -n ns-b -it \"\$(kubectl get pods -l app=client -o jsonpath='{.items[0].metadata.name}' -n ns-b)\" -- fortio load -allow-initial-errors -t 0 -H \"X-B3-Sampled:1\" http://svc-b:8080" ;
  echo "Traffic for AppC: daisy-chain-single" ;
  print_command "kubectl exec -n ns-c -it \"\$(kubectl get pods -l app=client -o jsonpath='{.items[0].metadata.name}' -n ns-c)\" -- fortio load -allow-initial-errors -t 0 -H \"X-B3-Sampled:1\" http://svc-c:8080" ;
  echo "Traffic for AppD: daisy-chain-tree" ;
  print_command "kubectl exec -n ns-d -it \"\$(kubectl get pods -l app=client -o jsonpath='{.items[0].metadata.name}' -n ns-d)\" -- fortio load -allow-initial-errors -t 0 -H \"X-B3-Sampled:1\" http://svc-d:8080" ;
  echo ;
  echo "All dt once in a loop" ;
  print_command "while true; do
  for i in a b c d; do
    kubectl exec -n \"ns-\${i}\" -it \"\$(kubectl get pods -l app=client -o jsonpath='{.items[0].metadata.name}' -n ns-\${i})\" -- fortio load -allow-initial-errors -t 5s -H \"X-B3-Sampled:1\" \"http://svc-\${i}:8080\" ;
  done
  sleep 1 ;
done" ;
  echo ;
  echo "Add delays" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/delays/03-spray-out-parallel.yaml\" && kubectl get deployments -n ns-a -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-a" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/delays/04-spray-out-serial.yaml\" && kubectl get deployments -n ns-b -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-b" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/delays/05-daisy-chain-single.yaml\" && kubectl get deployments -n ns-c -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-c" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/delays/06-daisy-chain-tree.yaml\" && kubectl get deployments -n ns-d -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-d" ;
  echo ;
  echo "Add errors" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/errors/03-spray-out-parallel.yaml\" && kubectl get deployments -n ns-a -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-a" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/errors/04-spray-out-serial.yaml\" && kubectl get deployments -n ns-b -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-b" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/errors/05-daisy-chain-single.yaml\" && kubectl get deployments -n ns-c -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-c" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/errors/06-daisy-chain-tree.yaml\" && kubectl get deployments -n ns-d -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-d" ;
  echo ;
  echo "Back to normal" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/normal/03-spray-out-parallel.yaml\" && kubectl get deployments -n ns-a -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-a" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/normal/04-spray-out-serial.yaml\" && kubectl get deployments -n ns-b -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-b" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/normal/05-daisy-chain-single.yaml\" && kubectl get deployments -n ns-c -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-c" ;
  print_command "kubectl apply -f \"${SCENARIO_DIR}/k8s/normal/06-daisy-chain-tree.yaml\" && kubectl get deployments -n ns-d -l \"role=service\" -o name | xargs -I {} kubectl rollout restart {} -n ns-d" ;
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