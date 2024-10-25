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

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local install_repo_url; install_repo_url="$(get_local_registry_endpoint)" ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Deploy tsb cluster, organization-settings and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f "${SCENARIO_DIR}/tsb/01-cluster.yaml" ;
  sleep 5 ;
  wait_cluster_onboarded app1 ;
  wait_cluster_onboarded transit1 ;
  wait_cluster_onboarded transit2 ;
  wait_cluster_onboarded app2 ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-organization-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/03-tenant.yaml" ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert "${certs_base_dir}" "abcd" "demo.tetrate.io" ;
  generate_server_cert "${certs_base_dir}" "efgh" "demo.tetrate.io" ;

  # Deploy kubernetes objects in cluster 'app1'
  kubectl --context app1 apply -f "${SCENARIO_DIR}/k8s/app1/01-namespace.yaml" ;
  if ! kubectl --context app1 get secret app-abcd-cert -n gateway-a &>/dev/null ; then
    kubectl --context app1 create secret tls app-abcd-cert -n gateway-a \
      --key "${certs_base_dir}/abcd/server.abcd.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abcd/server.abcd.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context app1 apply -f "${SCENARIO_DIR}/k8s/app1/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/app1/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/app1/03-deployment.yaml" > "${BASE_DIR}/output/app1/k8s/03-deployment.yaml" ;

  kubectl --context app1 apply -f "${BASE_DIR}/output/app1/k8s/03-deployment.yaml" ;
  kubectl --context app1 apply -f "${SCENARIO_DIR}/k8s/app1/04-service.yaml" ;
  kubectl --context app1 apply -f "${SCENARIO_DIR}/k8s/app1/05-ingress-gateway.yaml" ;

  # Deploy kubernetes objects in cluster 'transit1'
  kubectl --context transit1 apply -f "${SCENARIO_DIR}/k8s/transit1/01-namespace.yaml" ;
  if ! kubectl --context transit1 get secret app-abcd-cert -n gateway-t1-abcd &>/dev/null ; then
    kubectl --context transit1 create secret tls app-abcd-cert -n gateway-t1-abcd \
      --key "${certs_base_dir}/abcd/server.abcd.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abcd/server.abcd.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context transit1 apply -f "${SCENARIO_DIR}/k8s/transit1/02-tier1-gateway.yaml" ;
  kubectl --context transit1 apply -f "${SCENARIO_DIR}/k8s/transit1/03-deployment.yaml" ; # Deploy sleep pod (bug in TSB)

  # Deploy kubernetes objects in cluster 'transit2'
  kubectl --context transit2 apply -f "${SCENARIO_DIR}/k8s/transit2/01-namespace.yaml" ;
  if ! kubectl --context transit2 get secret app-efgh-cert -n gateway-t1-efgh &>/dev/null ; then
    kubectl --context transit2 create secret tls app-efgh-cert -n gateway-t1-efgh \
      --key "${certs_base_dir}/efgh/server.efgh.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/efgh/server.efgh.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context transit2 apply -f "${SCENARIO_DIR}/k8s/transit2/02-tier1-gateway.yaml" ;
  kubectl --context transit2 apply -f "${SCENARIO_DIR}/k8s/transit2/03-deployment.yaml" ; # Deploy sleep pod (bug in TSB)

  # Deploy kubernetes objects in cluster 'app2'
  kubectl --context app2 apply -f "${SCENARIO_DIR}/k8s/app2/01-namespace.yaml" ;
  if ! kubectl --context app2 get secret app-efgh-cert -n gateway-e &>/dev/null ; then
    kubectl --context app2 create secret tls app-efgh-cert -n gateway-e \
      --key "${certs_base_dir}/efgh/server.efgh.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/efgh/server.efgh.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context app2 apply -f "${SCENARIO_DIR}/k8s/app2/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/app2/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/app2/03-deployment.yaml" > "${BASE_DIR}/output/app2/k8s/03-deployment.yaml" ;

  kubectl --context app2 apply -f "${BASE_DIR}/output/app2/k8s/03-deployment.yaml" ;
  kubectl --context app2 apply -f "${SCENARIO_DIR}/k8s/app2/04-service.yaml" ;
  kubectl --context app2 apply -f "${SCENARIO_DIR}/k8s/app2/05-ingress-gateway.yaml" ;

  # Deploy tsb objects
  tctl apply -f "${SCENARIO_DIR}/tsb/04-workspace.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/05-group.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/06-tier1-gateway.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/07-ingress-gateway.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/08-security-setting.yaml" ;
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

  # Delete kubernetes configuration in app1, transit1, transit2 and app2 cluster
  kubectl --context app2 delete -f "${SCENARIO_DIR}/k8s/app2/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context transit2 delete -f "${SCENARIO_DIR}/k8s/transit2/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context transit1 delete -f "${SCENARIO_DIR}/k8s/transit1/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context app1 delete -f "${SCENARIO_DIR}/k8s/app1/01-namespace.yaml" --wait=true 2>/dev/null ;
}


# This function prints info about the scenario.
#
function info() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local abcd_t1_gw_ip ;
  local efgh_t1_gw_ip ;

  while ! abcd_t1_gw_ip=$(kubectl --context transit1 get svc -n gateway-t1-abcd gw-t1-abcd --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! efgh_t1_gw_ip=$(kubectl --context transit2 get svc -n gateway-t1-efgh gw-t1-efgh --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done

  echo "***********************************"
  echo "*** ABCD, EFGH Traffic Commands ***"
  echo "***********************************"
  echo
  echo "ABCD Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abcd.demo.tetrate.io:443:${abcd_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abcd.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c/proxy/app-d.ns-d\""
  echo
  echo "EFGH Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"efgh.demo.tetrate.io:443:${efgh_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://efgh.demo.tetrate.io/proxy/app-f.ns-f/proxy/app-g.ns-g/proxy/app-h.ns-h\""
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abcd.demo.tetrate.io:443:${abcd_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abcd.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c/proxy/app-d.ns-d\"
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"efgh.demo.tetrate.io:443:${efgh_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://efgh.demo.tetrate.io/proxy/app-f.ns-f/proxy/app-g.ns-g/proxy/app-h.ns-h\"
  sleep 1 ;
done"
  echo
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