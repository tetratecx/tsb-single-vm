#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

ACTION=${1}

GREEN='\033[0;32m'
NC='\033[0m'


# Login as admin into tsb
#   args:
#     (1) organization
function login_tsb_admin {
  expect <<DONE
  spawn tctl login --username admin --password admin --org ${1}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}


if [[ ${ACTION} = "deploy" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Deploy tsb cluster, organization and tenant objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-organization-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-tenant.yaml ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert abc demo.tetrate.io ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt-cluster-m1 apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/01-namespace.yaml ;
  if ! kubectl --context mgmt-cluster-m1 get secret app-abc-certs -n gateway-tier1 &>/dev/null ; then
    kubectl --context mgmt-cluster-m1 create secret tls app-abc-certs -n gateway-tier1 \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context mgmt-cluster-m1 apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/02-tier1-gateway.yaml ;

  # Deploy kubernetes objects in active cluster
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/01-namespace.yaml ;
  if ! kubectl --context active-cluster-m2 get secret app-abc-certs -n gateway-abc &>/dev/null ; then
    kubectl --context active-cluster-m2 create secret tls app-abc-certs -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/02-service-account.yaml
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/03-deployment.yaml
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/04-service.yaml
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/05-eastwest-gateway.yaml
  kubectl --context active-cluster-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster/06-ingress-gateway.yaml

  # Deploy kubernetes objects in standby cluster
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/01-namespace.yaml ;
  if ! kubectl --context standby-cluster-m3 get secret app-abc-certs -n gateway-abc &>/dev/null ; then
    kubectl --context standby-cluster-m3 create secret tls app-abc-certs -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/02-service-account.yaml
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/03-deployment.yaml
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/04-service.yaml
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/05-eastwest-gateway.yaml
  kubectl --context standby-cluster-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster/06-ingress-gateway.yaml

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
    tctl delete -f ${SCENARIO_ROOT_DIR}/tsb/${TSB_FILE} 2>/dev/null ;
  done

  # Delete kubernetes configuration in mgmt, active and standby cluster
  kubectl --context mgmt-cluster-m1 delete -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster 2>/dev/null ;
  kubectl --context active-cluster-m2 delete -f ${SCENARIO_ROOT_DIR}/k8s/active-cluster 2>/dev/null ;
  kubectl --context standby-cluster-m3 delete -f ${SCENARIO_ROOT_DIR}/k8s/standby-cluster 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  T1_GW_IP=$(kubectl --context mgmt-cluster-m1 get svc -n gateway-tier1 gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  INGRESS_ACTIVE_GW_IP=$(kubectl --context active-cluster-m2 get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  INGRESS_STANDBY_GW_IP=$(kubectl --context standby-cluster-m3 get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "****************************"
  echo "*** ABC Traffic Commands ***"
  echo "****************************"
  echo
  echo "Traffic to Active Ingress Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${INGRESS_ACTIVE_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo "Traffic to Standby Ingress Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${INGRESS_STANDBY_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo "Traffic through T1 Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${T1_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
