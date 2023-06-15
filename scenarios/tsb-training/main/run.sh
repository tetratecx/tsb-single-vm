#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${ROOT_DIR}/tsb-helpers.sh

if [[ ${ACTION} = "deploy" ]]; then

  clusters=( c1 c2 ) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Deploy tsb cluster and tenant objects
  # Wait for clusters to be onboarded to avoid race conditions
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  wait_clusters_onboarded "${clusters[@]}"
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-tenant.yaml ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context t1 apply -f ${SCENARIO_ROOT_DIR}/k8s/t1/01-namespace.yaml ;
  kubectl --context t1 apply -f ${SCENARIO_ROOT_DIR}/k8s/t1/02-tier1-gateway.yaml ;

  # Deploy kubernetes objects to the workload clusters..
  for cluster in "${clusters[@]}"; do
    kubectl --context $cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/workload-clusters/01-namespace.yaml ;
    kubectl --context $cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/workload-clusters/02-ingress-gw.yaml ;

    kubectl --context $cluster apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml ;
    kubectl --context $cluster apply -n bookinfo -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml ;
  done

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
  while ! C1_GW_IP=$(kubectl --context c1 get svc -n bookinfo tsb-gateway-bookinfo --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done
  while ! C2_GW_IP=$(kubectl --context c2 get svc -n bookinfo tsb-gateway-bookinfo --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  print_info "****************************"
  print_info "*** App Traffic Commands ***"
  print_info "****************************"
  echo
  echo "Traffic through T1 Gateway:"
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${T1_GW_IP}\" http://bookinfo.tetrate.com/productpage"
  echo "Traffic to C1 Ingress Gateway:"
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${C1_GW_IP}\" http://bookinfo.tetrate.com/productpage"
  echo "Traffic to C2 Ingress Gateway:"
  print_command "curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${C2_GW_IP}\" http://bookinfo.tetrate.com/productpage"

  echo "Load gen through T1 Gateway:"
  print_command "while true ; do
  curl -I -H \"X-B3-Sampled: 1\" --resolve \"bookinfo.tetrate.com:80:${T1_GW_IP}\" http://bookinfo.tetrate.com/productpage
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
