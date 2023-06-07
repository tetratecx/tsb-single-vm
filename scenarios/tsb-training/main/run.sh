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
#     (1) onboarding cluster name
function wait_cluster_onboarded {
  echo "Wait for cluster ${1} to be onboarded"
  while ! tctl experimental status cs ${1} | grep "Cluster onboarded" &>/dev/null ; do
    sleep 5 ;
    echo -n "."
  done
  echo "DONE"
}


if [[ ${ACTION} = "deploy" ]]; then

  # Set TSB_INSTALL_REPO_URL for envsubst of image repo
  export TSB_INSTALL_REPO_URL=${INSTALL_REPO_URL}

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Deploy tsb cluster and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  sleep 5 ;
  wait_cluster_onboarded c1 ;
  wait_cluster_onboarded c2 ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-tenant.yaml ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context t1 apply -f ${SCENARIO_ROOT_DIR}/k8s/t1/01-namespace.yaml ;
  kubectl --context t1 apply -f ${SCENARIO_ROOT_DIR}/k8s/t1/02-tier1-gateway.yaml ;

  # Deploy kubernetes objects in c1
  kubectl --context c1 apply -f ${SCENARIO_ROOT_DIR}/k8s/c1/01-namespace.yaml ;
  kubectl --context c1 apply -n bookinfo -f ${SCENARIO_ROOT_DIR}/k8s/c1/02-bookinfo.yaml ;
  kubectl --context c1 apply -n bookinfo -f ${SCENARIO_ROOT_DIR}/k8s/c1/03-sleep.yaml ;
  kubectl --context c1 apply -f ${SCENARIO_ROOT_DIR}/k8s/c1/04-ingress-gw.yaml ;

  # Deploy kubernetes objects in c2
  kubectl --context c2 apply -f ${SCENARIO_ROOT_DIR}/k8s/c2/01-namespace.yaml ;
  kubectl --context c2 apply -n bookinfo -f ${SCENARIO_ROOT_DIR}/k8s/c2/02-bookinfo.yaml ;
  kubectl --context c2 apply -n bookinfo -f ${SCENARIO_ROOT_DIR}/k8s/c2/03-sleep.yaml ;
  kubectl --context c2 apply -f ${SCENARIO_ROOT_DIR}/k8s/c2/04-ingress-gw.yaml ;

  # Deploy tsb objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-workspace.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/04-group.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/05-gateways.yaml ;

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

  # Delete kubernetes configuration in t1, c1 and c2 clusters
  kubectl --context t1 delete -f ${SCENARIO_ROOT_DIR}/k8s/t1 2>/dev/null ;
  kubectl --context c1 delete -f ${SCENARIO_ROOT_DIR}/k8s/c1 2>/dev/null ;
  kubectl --context c2 delete -f ${SCENARIO_ROOT_DIR}/k8s/c2 2>/dev/null ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  while ! T1_GW_IP=$(kubectl --context t1 get svc -n tier1 tier1-gateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  print_info "****************************"
  print_info "*** App Traffic Commands ***"
  print_info "****************************"
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${T1_GW_IP}\" \"http://bookinfo.tetrate.com/productpage\"
  sleep 0.5 ;
done"
  echo
  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
