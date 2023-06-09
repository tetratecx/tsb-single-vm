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
  wait_cluster_onboarded cluster1 ;
  wait_cluster_onboarded cluster2 ;
  wait_cluster_onboarded cluster3 ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-organization-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-tenant.yaml ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert abc demo.tetrate.io ;
  generate_server_cert def demo.tetrate.io ;
  generate_server_cert ghi demo.tetrate.io ;
  generate_client_cert abc demo.tetrate.io ;
  generate_client_cert def demo.tetrate.io ;
  generate_client_cert ghi demo.tetrate.io ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/01-namespace.yaml ;
  if ! kubectl --context mgmt-cluster get secret app-abc-cert -n gateway-tier1-abc &>/dev/null ; then
    kubectl --context mgmt-cluster create secret generic app-abc-cert -n gateway-tier1-abc \
      --from-file=tls.key=${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --from-file=tls.crt=${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem \
      --from-file=ca.crt=${CERTS_BASE_DIR}/root-cert.pem ;
  fi
  if ! kubectl --context mgmt-cluster get secret app-def-cert -n gateway-tier1-def &>/dev/null ; then
    kubectl --context mgmt-cluster create secret generic app-def-cert -n gateway-tier1-def \
      --from-file=tls.key=${CERTS_BASE_DIR}/def/server.def.demo.tetrate.io-key.pem \
      --from-file=tls.crt=${CERTS_BASE_DIR}/def/server.def.demo.tetrate.io-cert.pem \
      --from-file=ca.crt=${CERTS_BASE_DIR}/root-cert.pem ;
  fi
  if ! kubectl --context mgmt-cluster get secret app-ghi-cert -n gateway-tier1-ghi &>/dev/null ; then
    kubectl --context mgmt-cluster create secret generic app-ghi-cert -n gateway-tier1-ghi \
      --from-file=tls.key=${CERTS_BASE_DIR}/ghi/server.ghi.demo.tetrate.io-key.pem \
      --from-file=tls.crt=${CERTS_BASE_DIR}/ghi/server.ghi.demo.tetrate.io-cert.pem \
      --from-file=ca.crt=${CERTS_BASE_DIR}/root-cert.pem ;
  fi
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/02-tier1-gateway.yaml ;

  # Deploy kubernetes objects in cluster1
  kubectl --context cluster1 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster1/01-namespace.yaml ;
  if ! kubectl --context cluster1 get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context cluster1 create secret tls app-abc-cert -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context cluster1 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster1/02-service-account.yaml ;
  mkdir -p ${ROOT_DIR}/output/cluster1/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/cluster1/03-deployment.yaml > ${ROOT_DIR}/output/cluster1/k8s/03-deployment.yaml ;
  kubectl --context cluster1 apply -f ${ROOT_DIR}/output/cluster1/k8s/03-deployment.yaml ;
  kubectl --context cluster1 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster1/04-service.yaml ;
  kubectl --context cluster1 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster1/05-ingress-gateway.yaml ;

  # Deploy kubernetes objects in in cluster2
  kubectl --context cluster2 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster2/01-namespace.yaml ;
  if ! kubectl --context cluster2 get secret app-def-cert -n gateway-def &>/dev/null ; then
    kubectl --context cluster2 create secret tls app-def-cert -n gateway-def \
      --key ${CERTS_BASE_DIR}/def/server.def.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/def/server.def.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context cluster2 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster2/02-service-account.yaml ;
  mkdir -p ${ROOT_DIR}/output/cluster2/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/cluster2/03-deployment.yaml > ${ROOT_DIR}/output/cluster2/k8s/03-deployment.yaml ;
  kubectl --context cluster2 apply -f ${ROOT_DIR}/output/cluster2/k8s/03-deployment.yaml ;
  kubectl --context cluster2 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster2/04-service.yaml ;
  kubectl --context cluster2 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster2/05-ingress-gateway.yaml ;

  # Deploy kubernetes objects in in cluster3
  kubectl --context cluster3 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster3/01-namespace.yaml ;
  if ! kubectl --context cluster3 get secret app-ghi-cert -n gateway-ghi &>/dev/null ; then
    kubectl --context cluster3 create secret tls app-ghi-cert -n gateway-ghi \
      --key ${CERTS_BASE_DIR}/ghi/server.ghi.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/ghi/server.ghi.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context cluster3 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster3/02-service-account.yaml ;
  mkdir -p ${ROOT_DIR}/output/cluster3/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/cluster3/03-deployment.yaml > ${ROOT_DIR}/output/cluster3/k8s/03-deployment.yaml ;
  kubectl --context cluster3 apply -f ${ROOT_DIR}/output/cluster3/k8s/03-deployment.yaml ;
  kubectl --context cluster3 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster3/04-service.yaml ;
  kubectl --context cluster3 apply -f ${SCENARIO_ROOT_DIR}/k8s/cluster3/05-ingress-gateway.yaml ;

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
  kubectl --context mgmt-cluster delete -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster 2>/dev/null ;
  kubectl --context cluster1 delete -f ${ROOT_DIR}/output/cluster1/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context cluster1 delete -f ${SCENARIO_ROOT_DIR}/k8s/cluster1 2>/dev/null ;
  kubectl --context cluster2 delete -f ${ROOT_DIR}/output/cluster2/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context cluster2 delete -f ${SCENARIO_ROOT_DIR}/k8s/cluster2 2>/dev/null ;
  kubectl --context cluster3 delete -f ${ROOT_DIR}/output/cluster3/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context cluster3 delete -f ${SCENARIO_ROOT_DIR}/k8s/cluster3 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  ABC_T1_GW_IP=$(kubectl --context mgmt-cluster get svc -n gateway-tier1-abc gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  DEF_T1_GW_IP=$(kubectl --context mgmt-cluster get svc -n gateway-tier1-def gw-tier1-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  GHI_T1_GW_IP=$(kubectl --context mgmt-cluster get svc -n gateway-tier1-ghi gw-tier1-ghi --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  echo "****************************"
  echo "*** ABC Traffic Commands ***"
  echo "****************************"
  echo
  echo "ABC Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ABC_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/abc/client.abc.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/abc/client.abc.demo.tetrate.io-key.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo
  echo "DEF Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:443:${DEF_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/def/client.def.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/def/client.def.demo.tetrate.io-key.pem \"https://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/app-f.ns-f\""
  echo
  echo "GHI Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi.demo.tetrate.io:443:${GHI_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/ghi/client.ghi.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/ghi/client.ghi.demo.tetrate.io-key.pem \"https://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\""
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ABC_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/abc/client.abc.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/abc/client.abc.demo.tetrate.io-key.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ;
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:443:${DEF_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/def/client.def.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/def/client.def.demo.tetrate.io-key.pem \"https://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/app-f.ns-f\" ;
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi.demo.tetrate.io:443:${GHI_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem --cert ${CERTS_BASE_DIR}/ghi/client.ghi.demo.tetrate.io-cert.pem --key ${CERTS_BASE_DIR}/ghi/client.ghi.demo.tetrate.io-key.pem \"https://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\" ;
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
