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
  wait_cluster_onboarded cluster1 ;
  wait_cluster_onboarded cluster2 ;
  wait_cluster_onboarded cluster3 ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-organization-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/03-tenant.yaml" ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert "${certs_base_dir}" "abc" "demo.tetrate.io" ;
  generate_server_cert "${certs_base_dir}" "def" "demo.tetrate.io" ;
  generate_server_cert "${certs_base_dir}" "ghi" "demo.tetrate.io" ;
  generate_client_cert "${certs_base_dir}" "abc" "demo.tetrate.io" ;
  generate_client_cert "${certs_base_dir}" "def" "demo.tetrate.io" ;
  generate_client_cert "${certs_base_dir}" "ghi" "demo.tetrate.io" ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" ;
  if ! kubectl --context mgmt get secret app-abc-cert -n gateway-tier1-abc &>/dev/null ; then
    kubectl --context mgmt create secret generic app-abc-cert -n gateway-tier1-abc \
      --from-file=tls.key="${certs_base_dir}/abc/server.abc.demo.tetrate.io-key.pem" \
      --from-file=tls.crt="${certs_base_dir}/abc/server.abc.demo.tetrate.io-cert.pem" \
      --from-file=ca.crt="${certs_base_dir}/root-cert.pem" ;
  fi
  if ! kubectl --context mgmt get secret app-def-cert -n gateway-tier1-def &>/dev/null ; then
    kubectl --context mgmt create secret generic app-def-cert -n gateway-tier1-def \
      --from-file=tls.key="${certs_base_dir}/def/server.def.demo.tetrate.io-key.pem" \
      --from-file=tls.crt="${certs_base_dir}/def/server.def.demo.tetrate.io-cert.pem" \
      --from-file=ca.crt="${certs_base_dir}/root-cert.pem" ;
  fi
  if ! kubectl --context mgmt get secret app-ghi-cert -n gateway-tier1-ghi &>/dev/null ; then
    kubectl --context mgmt create secret generic app-ghi-cert -n gateway-tier1-ghi \
      --from-file=tls.key="${certs_base_dir}/ghi/server.ghi.demo.tetrate.io-key.pem" \
      --from-file=tls.crt="${certs_base_dir}/ghi/server.ghi.demo.tetrate.io-cert.pem" \
      --from-file=ca.crt="${certs_base_dir}/root-cert.pem" ;
  fi
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/02-tier1-gateway.yaml" ;

  # Deploy kubernetes objects in cluster1
  kubectl --context cluster1 apply -f "${SCENARIO_DIR}/k8s/cluster1/01-namespace.yaml" ;
  if ! kubectl --context cluster1 get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context cluster1 create secret tls app-abc-cert -n gateway-abc \
      --key "${certs_base_dir}/abc/server.abc.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/abc/server.abc.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context cluster1 apply -f "${SCENARIO_DIR}/k8s/cluster1/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/cluster1/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/cluster1/03-deployment.yaml" > "${BASE_DIR}/output/cluster1/k8s/03-deployment.yaml" ;
  
  kubectl --context cluster1 apply -f "${BASE_DIR}/output/cluster1/k8s/03-deployment.yaml" ;
  kubectl --context cluster1 apply -f "${SCENARIO_DIR}/k8s/cluster1/04-service.yaml" ;
  kubectl --context cluster1 apply -f "${SCENARIO_DIR}/k8s/cluster1/05-ingress-gateway.yaml" ;

  # Deploy kubernetes objects in in cluster2
  kubectl --context cluster2 apply -f "${SCENARIO_DIR}/k8s/cluster2/01-namespace.yaml" ;
  if ! kubectl --context cluster2 get secret app-def-cert -n gateway-def &>/dev/null ; then
    kubectl --context cluster2 create secret tls app-def-cert -n gateway-def \
      --key "${certs_base_dir}/def/server.def.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/def/server.def.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context cluster2 apply -f "${SCENARIO_DIR}/k8s/cluster2/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/cluster2/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/cluster2/03-deployment.yaml" > "${BASE_DIR}/output/cluster2/k8s/03-deployment.yaml" ;

  kubectl --context cluster2 apply -f "${BASE_DIR}/output/cluster2/k8s/03-deployment.yaml" ;
  kubectl --context cluster2 apply -f "${SCENARIO_DIR}/k8s/cluster2/04-service.yaml" ;
  kubectl --context cluster2 apply -f "${SCENARIO_DIR}/k8s/cluster2/05-ingress-gateway.yaml" ;

  # Deploy kubernetes objects in in cluster3
  kubectl --context cluster3 apply -f "${SCENARIO_DIR}/k8s/cluster3/01-namespace.yaml" ;
  if ! kubectl --context cluster3 get secret app-ghi-cert -n gateway-ghi &>/dev/null ; then
    kubectl --context cluster3 create secret tls app-ghi-cert -n gateway-ghi \
      --key "${certs_base_dir}/ghi/server.ghi.demo.tetrate.io-key.pem" \
      --cert "${certs_base_dir}/ghi/server.ghi.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context cluster3 apply -f "${SCENARIO_DIR}/k8s/cluster3/02-service-account.yaml" ;
  mkdir -p "${BASE_DIR}/output/cluster3/k8s" ;

  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  envsubst < "${SCENARIO_DIR}/k8s/cluster3/03-deployment.yaml" > "${BASE_DIR}/output/cluster3/k8s/03-deployment.yaml" ;

  kubectl --context cluster3 apply -f "${BASE_DIR}/output/cluster3/k8s/03-deployment.yaml" ;
  kubectl --context cluster3 apply -f "${SCENARIO_DIR}/k8s/cluster3/04-service.yaml" ;
  kubectl --context cluster3 apply -f "${SCENARIO_DIR}/k8s/cluster3/05-ingress-gateway.yaml" ;

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

  # Delete kubernetes configuration in mgmt, cluster1, cluster2 and cluster3 cluster
  kubectl --context standby delete -f "${SCENARIO_DIR}/k8s/cluster3/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context standby delete -f "${SCENARIO_DIR}/k8s/cluster2/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context active delete -f "${SCENARIO_DIR}/k8s/cluster1/01-namespace.yaml" --wait=true 2>/dev/null ;
  kubectl --context mgmt delete -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" --wait=true 2>/dev/null ;
}


# This function prints info about the scenario.
#
function info() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local abc_t1_gw_ip ;
  local def_t1_gw_ip ;
  local ghi_t1_gw_ip ;

  while ! abc_t1_gw_ip=$(kubectl --context mgmt get svc -n gateway-tier1-abc gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! def_t1_gw_ip=$(kubectl --context mgmt get svc -n gateway-tier1-def gw-tier1-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! ghi_t1_gw_ip=$(kubectl --context mgmt get svc -n gateway-tier1-ghi gw-tier1-ghi --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done

  echo "**************************************" ;
  echo "*** ABC, DEF, GHI Traffic Commands ***" ;
  echo "**************************************" ;
  echo ;
  echo "ABC Traffic through T1 Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${abc_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/abc/client.abc.demo.tetrate.io-cert.pem --key ${certs_base_dir}/abc/client.abc.demo.tetrate.io-key.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "DEF Traffic through T1 Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:443:${def_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def/client.def.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def/client.def.demo.tetrate.io-key.pem \"https://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/app-f.ns-f\"" ;
  echo ;
  echo "GHI Traffic through T1 Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi.demo.tetrate.io:443:${ghi_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/ghi/client.ghi.demo.tetrate.io-cert.pem --key ${certs_base_dir}/ghi/client.ghi.demo.tetrate.io-key.pem \"https://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  echo ;
  echo "All at once in a loop" ;
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${abc_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/abc/client.abc.demo.tetrate.io-cert.pem --key ${certs_base_dir}/abc/client.abc.demo.tetrate.io-key.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ;
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:443:${def_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def/client.def.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def/client.def.demo.tetrate.io-key.pem \"https://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/app-f.ns-f\" ;
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi.demo.tetrate.io:443:${ghi_t1_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/ghi/client.ghi.demo.tetrate.io-cert.pem --key ${certs_base_dir}/ghi/client.ghi.demo.tetrate.io-key.pem \"https://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\" ;
  sleep 1 ;
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