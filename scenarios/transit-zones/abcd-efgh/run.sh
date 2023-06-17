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
  wait_cluster_onboarded app1 ;
  wait_cluster_onboarded transit1 ;
  wait_cluster_onboarded transit2 ;
  wait_cluster_onboarded app2 ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-organization-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-tenant.yaml ;

  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert abcd demo.tetrate.io ;
  generate_server_cert efgh demo.tetrate.io ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  # Deploy kubernetes objects in cluster 'app1'
  kubectl --context app1 apply -f ${SCENARIO_ROOT_DIR}/k8s/app1/01-namespace.yaml ;
  if ! kubectl --context app1 get secret app-abcd-cert -n gateway-a &>/dev/null ; then
    kubectl --context app1 create secret tls app-abcd-cert -n gateway-a \
      --key ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context app1 apply -f ${SCENARIO_ROOT_DIR}/k8s/app1/02-service-account.yaml
  mkdir -p ${ROOT_DIR}/output/app1/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/app1/03-deployment.yaml > ${ROOT_DIR}/output/app1/k8s/03-deployment.yaml ;
  kubectl --context app1 apply -f ${ROOT_DIR}/output/app1/k8s/03-deployment.yaml ;
  kubectl --context app1 apply -f ${SCENARIO_ROOT_DIR}/k8s/app1/04-service.yaml
  kubectl --context app1 apply -f ${SCENARIO_ROOT_DIR}/k8s/app1/05-ingress-gateway.yaml

  # Deploy kubernetes objects in cluster 'transit1'
  kubectl --context transit1 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit1/01-namespace.yaml ;
  if ! kubectl --context transit1 get secret app-abcd-cert -n gateway-t1-abcd &>/dev/null ; then
    kubectl --context transit1 create secret tls app-abcd-cert -n gateway-t1-abcd \
      --key ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context transit1 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit1/02-tier1-gateway.yaml

  # Deploy kubernetes objects in cluster 'transit2'
  kubectl --context transit2 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit2/01-namespace.yaml ;
  if ! kubectl --context transit2 get secret app-efgh-cert -n gateway-t1-efgh &>/dev/null ; then
    kubectl --context transit2 create secret tls app-efgh-cert -n gateway-t1-efgh \
      --key ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context transit2 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit2/02-tier1-gateway.yaml

  # Deploy kubernetes objects in cluster 'app2'
  kubectl --context app2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app2/01-namespace.yaml ;
  if ! kubectl --context app2 get secret app-efgh-cert -n gateway-e &>/dev/null ; then
    kubectl --context app2 create secret tls app-efgh-cert -n gateway-e \
      --key ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context app2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app2/02-service-account.yaml
  mkdir -p ${ROOT_DIR}/output/app2/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/app2/03-deployment.yaml > ${ROOT_DIR}/output/app2/k8s/03-deployment.yaml ;
  kubectl --context app2 apply -f ${ROOT_DIR}/output/app2/k8s/03-deployment.yaml ;
  kubectl --context app2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app2/04-service.yaml
  kubectl --context app2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app2/05-ingress-gateway.yaml

  # Deploy tsb objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/04-workspace.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/05-group.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/06-tier1-gateway.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/07-ingress-gateway.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/08-security-setting.yaml ;

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
  kubectl --context app1 delete -f ${ROOT_DIR}/output/app1/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context app1 delete -f ${SCENARIO_ROOT_DIR}/k8s/app1 2>/dev/null ;
  kubectl --context transit1 delete -f ${SCENARIO_ROOT_DIR}/k8s/transit1 2>/dev/null ;
  kubectl --context transit2 delete -f ${SCENARIO_ROOT_DIR}/k8s/transit2 2>/dev/null ;
  kubectl --context app2 delete -f ${ROOT_DIR}/output/app2/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context app2 delete -f ${SCENARIO_ROOT_DIR}/k8s/app2 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  ABCD_T1_GW_IP=$(kubectl --context transit1 get svc -n gateway-t1-abcd gw-t1-abcd --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  EFGH_T1_GW_IP=$(kubectl --context transit2 get svc -n gateway-t1-efgh gw-t1-efgh --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  echo "****************************"
  echo "*** ABC Traffic Commands ***"
  echo "****************************"
  echo
  echo "ABCD Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abcd.demo.tetrate.io:443:${ABCD_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abcd.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c/proxy/app-d.ns-d\""
  echo
  echo "EFGH Traffic through T1 Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"efgh.demo.tetrate.io:443:${EFGH_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://efgh.demo.tetrate.io/proxy/app-f.ns-f/proxy/app-g.ns-g/proxy/app-h.ns-h\""
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abcd.demo.tetrate.io:443:${ABCD_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://abcd.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c/proxy/app-d.ns-d\"
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"efgh.demo.tetrate.io:443:${EFGH_T1_GW_IP}\" --cacert ${CERTS_BASE_DIR}/root-cert.pem \"https://efgh.demo.tetrate.io/proxy/app-f.ns-f/proxy/app-g.ns-g/proxy/app-h.ns-h\"
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
