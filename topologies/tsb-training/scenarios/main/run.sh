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

  local clusters=( c1 c2 ) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Deploy tsb cluster and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f "${SCENARIO_DIR}/tsb/01-cluster.yaml" ;
  wait_clusters_onboarded "${clusters[@]}" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-tenant.yaml" ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context t1 apply -f "${SCENARIO_DIR}/k8s/t1/01-namespace.yaml" ;
  kubectl --context t1 apply -f "${SCENARIO_DIR}/k8s/t1/02-tier1-gateway.yaml" ;

  # Deploy kubernetes objects to the workload clusters..
  for cluster in "${clusters[@]}"; do
    kubectl --context "${cluster}" apply -f "${SCENARIO_DIR}/k8s/workload-clusters/01-namespace.yaml" ;
    kubectl --context "${cluster}" apply -f "${SCENARIO_DIR}/k8s/workload-clusters/02-ingress-gw.yaml" ;

    kubectl --context "${cluster}" apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml ;
    kubectl --context "${cluster}" apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml ;
  done

  # Deploy tsb objects
  tctl apply -f "${SCENARIO_DIR}/tsb/03-workspace.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/04-group.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/05-gateways.yaml" ;
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

  # Delete kubernetes configuration in t1, c1 and c2 clusters
  kubectl --context c2 delete -f "${SCENARIO_DIR}/k8s/workload-clusters/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context c1 delete -f "${SCENARIO_DIR}/k8s/workload-clusters/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context t1 delete -f "${SCENARIO_DIR}/k8s/t1/01-namespace.yaml" --wait=true 2>/dev/null ;
}


# This function prints info about the scenario.
#
function info() {

  local t1_gw_ip ;
  local c1_gw_ip ;
  local c2_gw_ip ;

  while ! t1_gw_ip=$(kubectl --context t1 get svc -n tier1 tier1-gateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! c1_gw_ip=$(kubectl --context c1 get svc -n bookinfo tsb-gateway-bookinfo --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! c2_gw_ip=$(kubectl --context c2 get svc -n bookinfo tsb-gateway-bookinfo --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done

  print_info "*********************************" ;
  print_info "*** Bookinfo Traffic Commands ***" ;
  print_info "*********************************" ;
  echo ;
  echo "Traffic through T1 Gateway:" ;
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${t1_gw_ip}\" http://bookinfo.tetrate.com/productpage" ;
  echo "Traffic to C1 Ingress Gateway:" ;
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${c1_gw_ip}\" http://bookinfo.tetrate.com/productpage" ;
  echo "Traffic to C2 Ingress Gateway:" ;
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${c2_gw_ip}\" http://bookinfo.tetrate.com/productpage" ;

  echo "Load gen through T1 Gateway:" ;
  print_command "while true ; do
  curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${t1_gw_ip}\" http://bookinfo.tetrate.com/productpage ;
  sleep 0.5 ;
done"
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