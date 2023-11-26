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
  wait_cluster_onboarded active ;
  wait_cluster_onboarded standby ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-organization-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/03-tenant.yaml" ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert "${certs_base_dir}" "abc" "demo.tetrate.io" ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" ;
  if ! kubectl --context mgmt get secret app-abc-cert -n gateway-tier1 &>/dev/null ; then
    kubectl --context mgmt create secret tls app-abc-cert -n gateway-tier1 \
      --key "${certs_base_dir}/abc/server.abc.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abc/server.abc.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/02-tier1-gateway.yaml" ;

  # Deploy kubernetes objects in active cluster
  kubectl --context active apply -f "${SCENARIO_DIR}/k8s/active/01-namespace.yaml" ;
  if ! kubectl --context active get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context active create secret tls app-abc-cert -n gateway-abc \
      --key "${certs_base_dir}/abc/server.abc.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abc/server.abc.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context active apply -f "${SCENARIO_DIR}/k8s/active/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/active/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/active/03-deployment.yaml" > "${BASE_DIR}/output/active/k8s/03-deployment.yaml" ;

  kubectl --context active apply -f "${BASE_DIR}/output/active/k8s/03-deployment.yaml" ;
  kubectl --context active apply -f "${SCENARIO_DIR}/k8s/active/04-service.yaml" ;
  kubectl --context active apply -f "${SCENARIO_DIR}/k8s/active/05-eastwest-gateway.yaml" ;
  kubectl --context active apply -f "${SCENARIO_DIR}/k8s/active/06-ingress-gateway.yaml" ;

  # Deploy kubernetes objects in standby cluster
  kubectl --context standby apply -f "${SCENARIO_DIR}/k8s/standby/01-namespace.yaml" ;
  if ! kubectl --context standby get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context standby create secret tls app-abc-cert -n gateway-abc \
      --key "${certs_base_dir}/abc/server.abc.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abc/server.abc.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context standby apply -f "${SCENARIO_DIR}/k8s/standby/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/standby/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/standby/03-deployment.yaml" > "${BASE_DIR}/output/standby/k8s/03-deployment.yaml" ;

  kubectl --context standby apply -f "${BASE_DIR}/output/standby/k8s/03-deployment.yaml" ;
  kubectl --context standby apply -f "${SCENARIO_DIR}/k8s/standby/04-service.yaml" ;
  kubectl --context standby apply -f "${SCENARIO_DIR}/k8s/standby/05-eastwest-gateway.yaml" ;
  kubectl --context standby apply -f "${SCENARIO_DIR}/k8s/standby/06-ingress-gateway.yaml" ;

  # Deploy tsb objects
  tctl apply -f "${SCENARIO_DIR}/tsb/04-workspace.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/05-workspace-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/06-group.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/07-tier1-gateway.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/08-ingress-gateway.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/09-security-setting.yaml" ;
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
  kubectl --context standby delete -f "${SCENARIO_DIR}/k8s/standby/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context active delete -f "${SCENARIO_DIR}/k8s/active/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context mgmt delete -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" --wait=true 2>/dev/null ;
}


# This function prints info about the scenario.
#
function info() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local t1_gw_ip;
  local ingress_active_gw_ip;
  local ingress_standby_gw_ip;

  while ! t1_gw_ip=$(kubectl --context mgmt get svc -n gateway-tier1 gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! ingress_active_gw_ip=$(kubectl --context active get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! ingress_standby_gw_ip=$(kubectl --context standby get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done

  print_info "****************************" ;
  print_info "*** ABC Traffic Commands ***" ;
  print_info "****************************" ;
  echo ;
  echo "Traffic to Active Ingress Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ingress_active_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo "Traffic to Standby Ingress Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ingress_standby_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo "Traffic through T1 Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "All at once in a loop" ;
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ;
  sleep 1 ;
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