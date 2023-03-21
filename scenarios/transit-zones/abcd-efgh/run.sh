#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

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

# Wait for cluster to be onboarded
#   args:
#     (1) cluster name
function wait_cluster_onboarded {
  echo "Wait for cluster ${1} to be onboarded"
  while ! tctl experimental status cs ${1} | grep "Cluster onboarded" &>/dev/null ; do
    sleep 5
    echo -n "."
  done
  echo "DONE"
}


if [[ ${ACTION} = "deploy" ]]; then

  # Set TSB_INSTALL_REPO_URL for envsubst of image repo
  export TSB_INSTALL_REPO_URL=${INSTALL_REPO_URL}

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Deploy tsb cluster, organization-settings and tenant objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-organization-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-tenant.yaml ;

  # Wait for clusters to be onboarded to avoid race conditions
  sleep 5 ;
  wait_cluster_onboarded app-cluster1 ;
  wait_cluster_onboarded transit-cluster1 ;
  wait_cluster_onboarded transit-cluster2 ;
  wait_cluster_onboarded app-cluster2 ;
  
  # Generate tier1 and tier2 ingress certificates for the application
  generate_server_cert abcd demo.tetrate.io ;
  generate_server_cert efgh demo.tetrate.io ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  # Deploy kubernetes objects in app-cluster1
  kubectl --context app-cluster1-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster1/01-namespace.yaml ;
  if ! kubectl --context app-cluster1-m2 get secret app-abcd-cert -n gateway-a &>/dev/null ; then
    kubectl --context app-cluster1-m2 create secret tls app-abcd-cert -n gateway-a \
      --key ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context app-cluster1-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster1/02-service-account.yaml
  mkdir -p ${ROOT_DIR}/output/app-cluster1/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/app-cluster1/03-deployment.yaml > ${ROOT_DIR}/output/app-cluster1/k8s/03-deployment.yaml ;
  kubectl --context app-cluster1-m2 apply -f ${ROOT_DIR}/output/app-cluster1/k8s/03-deployment.yaml ;
  kubectl --context app-cluster1-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster1/04-service.yaml
  kubectl --context app-cluster1-m2 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster1/05-ingress-gateway.yaml

  # Deploy kubernetes objects in in transit-cluster1
  kubectl --context transit-cluster1-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster1/01-namespace.yaml ;
  if ! kubectl --context transit-cluster1-m3 get secret app-abcd-cert -n gateway-t1-abcd &>/dev/null ; then
    kubectl --context transit-cluster1-m3 create secret tls app-abcd-cert -n gateway-t1-abcd \
      --key ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abcd/server.abcd.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context transit-cluster1-m3 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster1/02-tier1-gateway.yaml

  # Deploy kubernetes objects in in transit-cluster2
  kubectl --context transit-cluster2-m4 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster2/01-namespace.yaml ;
  if ! kubectl --context transit-cluster2-m4 get secret app-efgh-cert -n gateway-t1-efgh &>/dev/null ; then
    kubectl --context transit-cluster2-m4 create secret tls app-efgh-cert -n gateway-t1-efgh \
      --key ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context transit-cluster2-m4 apply -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster2/02-tier1-gateway.yaml

  # Deploy kubernetes objects in app-cluster2
  kubectl --context app-cluster2-m5 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster2/01-namespace.yaml ;
  if ! kubectl --context app-cluster2-m5 get secret app-efgh-cert -n gateway-e &>/dev/null ; then
    kubectl --context app-cluster2-m5 create secret tls app-efgh-cert -n gateway-e \
      --key ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/efgh/server.efgh.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context app-cluster2-m5 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster2/02-service-account.yaml
  mkdir -p ${ROOT_DIR}/output/app-cluster2/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/app-cluster2/03-deployment.yaml > ${ROOT_DIR}/output/app-cluster2/k8s/03-deployment.yaml ;
  kubectl --context app-cluster2-m5 apply -f ${ROOT_DIR}/output/app-cluster2/k8s/03-deployment.yaml ;
  kubectl --context app-cluster2-m5 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster2/04-service.yaml
  kubectl --context app-cluster2-m5 apply -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster2/05-ingress-gateway.yaml

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
  kubectl --context app-cluster1-m2 delete -f ${ROOT_DIR}/output/app-cluster1/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context app-cluster1-m2 delete -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster1 2>/dev/null ;
  kubectl --context transit-cluster1-m3 delete -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster1 2>/dev/null ;
  kubectl --context transit-cluster2-m4 delete -f ${SCENARIO_ROOT_DIR}/k8s/transit-cluster2 2>/dev/null ;
  kubectl --context app-cluster2-m5 delete -f ${ROOT_DIR}/output/app-cluster2/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context app-cluster2-m5 delete -f ${SCENARIO_ROOT_DIR}/k8s/app-cluster2 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  ABCD_T1_GW_IP=$(kubectl --context transit-cluster1-m3 get svc -n gateway-t1-abcd gw-t1-abcd --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  EFGH_T1_GW_IP=$(kubectl --context transit-cluster2-m4 get svc -n gateway-t1-efgh gw-t1-efgh --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

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
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
