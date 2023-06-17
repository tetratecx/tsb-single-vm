#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${ROOT_DIR}/tsb-helpers.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

if [[ ${ACTION} = "deploy" ]]; then

  # Set TSB_INSTALL_REPO_URL for envsubst of image repo
  export TSB_INSTALL_REPO_URL=${INSTALL_REPO_URL}

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Deploy tsb cluster, organization-settings and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  sleep 5 ;
  wait_cluster_onboarded active ;
  wait_cluster_onboarded standby ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-organization-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-tenant.yaml ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert abc demo.tetrate.io ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt/01-namespace.yaml ;
  if ! kubectl --context mgmt get secret app-abc-cert -n gateway-tier1 &>/dev/null ; then
    kubectl --context mgmt create secret tls app-abc-cert -n gateway-tier1 \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context mgmt apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt/02-tier1-gateway.yaml ;

  # Deploy kubernetes objects in active cluster
  kubectl --context active apply -f ${SCENARIO_ROOT_DIR}/k8s/active/01-namespace.yaml ;
  if ! kubectl --context active get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context active create secret tls app-abc-cert -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context active apply -f ${SCENARIO_ROOT_DIR}/k8s/active/02-service-account.yaml ;
  mkdir -p ${ROOT_DIR}/output/active/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/active/03-deployment.yaml > ${ROOT_DIR}/output/active/k8s/03-deployment.yaml ;
  kubectl --context active apply -f ${ROOT_DIR}/output/active/k8s/03-deployment.yaml ;
  kubectl --context active apply -f ${SCENARIO_ROOT_DIR}/k8s/active/04-service.yaml ;
  kubectl --context active apply -f ${SCENARIO_ROOT_DIR}/k8s/active/05-eastwest-gateway.yaml ;
  kubectl --context active apply -f ${SCENARIO_ROOT_DIR}/k8s/active/06-ingress-gateway.yaml ;

  # Deploy kubernetes objects in standby cluster
  kubectl --context standby apply -f ${SCENARIO_ROOT_DIR}/k8s/standby/01-namespace.yaml ;
  if ! kubectl --context standby get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context standby create secret tls app-abc-cert -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context standby apply -f ${SCENARIO_ROOT_DIR}/k8s/standby/02-service-account.yaml ;
  mkdir -p ${ROOT_DIR}/output/standby/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/standby/03-deployment.yaml > ${ROOT_DIR}/output/standby/k8s/03-deployment.yaml ;
  kubectl --context standby apply -f ${ROOT_DIR}/output/standby/k8s/03-deployment.yaml ;
  kubectl --context standby apply -f ${SCENARIO_ROOT_DIR}/k8s/standby/04-service.yaml ;
  kubectl --context standby apply -f ${SCENARIO_ROOT_DIR}/k8s/standby/05-eastwest-gateway.yaml ;
  kubectl --context standby apply -f ${SCENARIO_ROOT_DIR}/k8s/standby/06-ingress-gateway.yaml ;

  # Deploy tsb objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/04-workspace.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/05-workspace-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/06-group.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/07-tier1-gateway.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/08-ingress-gateway.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/09-security-setting.yaml ;

  exit 0
fi


if [[ ${ACTION} = "undeploy" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Delete tsb configuration
  for TSB_FILE in $(ls -1 ${SCENARIO_ROOT_DIR}/tsb | sort -r) ; do
    echo "Going to delete tsb/${TSB_FILE}"
    tctl delete -f ${SCENARIO_ROOT_DIR}/tsb/${TSB_FILE} 2>/dev/null ;
  done

  # Delete kubernetes configuration in mgmt, active and standby cluster
  kubectl --context mgmt delete -f ${SCENARIO_ROOT_DIR}/k8s/mgmt 2>/dev/null ;
  kubectl --context active delete -f ${ROOT_DIR}/output/active/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context active delete -f ${SCENARIO_ROOT_DIR}/k8s/active 2>/dev/null ;
  kubectl --context standby delete -f ${ROOT_DIR}/output/standby/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context standby delete -f ${SCENARIO_ROOT_DIR}/k8s/standby 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  while ! T1_GW_IP=$(kubectl --context mgmt get svc -n gateway-tier1 gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done
  while ! INGRESS_ACTIVE_GW_IP=$(kubectl --context active get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done
  while ! INGRESS_STANDBY_GW_IP=$(kubectl --context standby get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  print_info "****************************"
  print_info "*** ABC Traffic Commands ***"
  print_info "****************************"
  echo
  echo "Traffic to Active Ingress Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${INGRESS_ACTIVE_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo "Traffic to Standby Ingress Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${INGRESS_STANDBY_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo "Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"
  sleep 1 ;
done"
  echo
  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
