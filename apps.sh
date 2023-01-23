#!/usr/bin/env bash

ACTION=${1}

MGMT_CLUSTER_PROFILE=mgmt-cluster-m1
ACTIVE_CLUSTER_PROFILE=active-cluster-m2
STANDBY_CLUSTER_PROFILE=standby-cluster-m3

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

# Pull and load demo application image
#   args:
#     (1) minikube profile name
function load_demo_app_image {
  if ! docker image inspect containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi

  if ! minikube --profile ${1} image ls | grep containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    echo "Syncing image containers.dl.tetrate.io/obs-tester-server:1.0 to minikube profile ${1}" ;
    minikube --profile ${1} image load containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi
}


if [[ ${ACTION} = "deploy-app-abc" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
  minikube --profile ${ACTIVE_CLUSTER_PROFILE} image load containers.dl.tetrate.io/obs-tester-server:1.0 ;
  minikube --profile ${STANDBY_CLUSTER_PROFILE} image load containers.dl.tetrate.io/obs-tester-server:1.0 ;

  # Tier 1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/mgmt-cluster/k8s/abc ;

  # Workspaces, groups and gateways for abc (mgmt cluster)
  tctl apply -f ./config/mgmt-cluster/tsb/abc/04-workspaces.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/abc/05-groups.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/abc/06-gateways.yaml ;

  # Application deployment in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/active-cluster/apps/abc ;

  # Application deployment in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/standby-cluster/apps/abc ;

  exit 0
fi


if [[ ${ACTION} = "deploy-app-def" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Pull and load demo application image
  load_demo_app_image ${ACTIVE_CLUSTER_PROFILE}
  load_demo_app_image ${STANDBY_CLUSTER_PROFILE}


  # Tier 1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/mgmt-cluster/k8s/def ;

  # Workspaces, groups and gateways for abc (mgmt cluster)
  tctl apply -f ./config/mgmt-cluster/tsb/def/04-workspaces.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/def/05-groups.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/def/06-gateways.yaml ;

  # Application deployment in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/active-cluster/apps/def ;

  # Application deployment in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/standby-cluster/apps/def ;

  exit 0
fi


if [[ ${ACTION} = "traffic-cmd-abc" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  T1_GW_IP=$(kubectl get svc -n gateway-tier1 gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  INGRESS_ACTIVE_GW_IP=$(kubectl get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  INGRESS_STANDBY_GW_IP=$(kubectl get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "ABC Traffic through T1 Gateway"
  echo "curl -k -v -H \"X-B3-Sampled: 1\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" --resolve \"abc.tetrate.prod:80:${T1_GW_IP}\""
  echo "ABC Traffic through Active Ingress Gateway"
  echo "curl -k -v -H \"X-B3-Sampled: 1\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" --resolve \"abc.tetrate.prod:80:${INGRESS_ACTIVE_GW_IP}\""
  echo "ABC Traffic through Standby Ingress Gateway"
  echo "curl -k -v -H \"X-B3-Sampled: 1\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" --resolve \"abc.tetrate.prod:80:${INGRESS_STANDBY_GW_IP}\""

  exit 0
fi


if [[ ${ACTION} = "traffic-cmd-def" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  T1_GW_IP=$(kubectl get svc -n gateway-tier1 gw-tier1-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  INGRESS_ACTIVE_GW_IP=$(kubectl get svc -n gateway-def gw-ingress-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "DEF Traffic through T1 Gateway"
  echo "curl -k -v -H \"X-B3-Sampled: 1\" \"http://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" --resolve \"def.tetrate.prod:80:${T1_GW_IP}\""
  echo "DEF Traffic through Active Ingress Gateway"
  echo "curl -k -v -H \"X-B3-Sampled: 1\" \"http://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" --resolve \"def.tetrate.prod:80:${INGRESS_ACTIVE_GW_IP}\""

  exit 0
fi

echo "Please specify one of the following action:"
echo "  - deploy-app-abc"
echo "  - deploy-app-def"
echo "  - traffic-cmd-abc"
echo "  - traffic-cmd-def"
exit 1
