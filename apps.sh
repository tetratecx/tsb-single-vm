#!/usr/bin/env bash

ACTION=${1}
TIER1_MODE=${2}

GREEN='\033[0;32m'
NC='\033[0m'

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

  # Pull and load demo application image
  load_demo_app_image ${ACTIVE_CLUSTER_PROFILE}
  load_demo_app_image ${STANDBY_CLUSTER_PROFILE}

  # Deploy tier1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/mgmt-cluster/k8s/abc ;

  # Deploy tier1 secrets if needed
  if [[ ${TIER1_MODE} = "https" ]]; then
    kubectl create secret tls app-abc-certs -n gateway-tier1 \
      --key certs/app-abc/server.abc.tetrate.prod.key \
      --cert certs/app-abc/server.abc.tetrate.prod.pem ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    kubectl create secret generic app-abc-certs -n gateway-tier1 \
      --from-file=tls.key=certs/app-abc/server.abc.tetrate.prod.key \
      --from-file=tls.crt=certs/app-abc/server.abc.tetrate.prod.pem \
      --from-file=ca.crt=certs/root-cert.pem ;
  fi

  # Deploy workspaces, groups, gateways and security for ABC (mgmt cluster)
  tctl apply -f ./config/mgmt-cluster/tsb/abc/04-workspaces.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/abc/05-groups.yaml ;
  if [[ ${TIER1_MODE} = "http" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/abc/06-tier1-http.yaml ;
  fi
  if [[ ${TIER1_MODE} = "https" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/abc/06-tier1-https.yaml ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/abc/06-tier1-mtls.yaml ;
  fi 
  tctl apply -f ./config/mgmt-cluster/tsb/abc/06-ingress.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/abc/07-security.yaml ;



  # Application deployment in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/active-cluster/apps/abc ;

  # Application deployment in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/standby-cluster/apps/abc ;

  exit 0
fi


if [[ ${ACTION} = "undeploy-app-abc" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Application removal in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/standby-cluster/apps/abc ;

  # Application removal in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/active-cluster/apps/abc ;

  # Remove workspaces, groups, gateways and security for ABC (mgmt cluster)
  tctl delete -f ./config/mgmt-cluster/tsb/abc/07-security.yaml ;
  tctl delete -f ./config/mgmt-cluster/tsb/abc/06-ingress.yaml ;
  if [[ ${TIER1_MODE} = "http" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/abc/06-tier1-http.yaml ;
  fi
  if [[ ${TIER1_MODE} = "https" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/abc/06-tier1-https.yaml ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/abc/06-tier1-mtls.yaml ;
  fi 
  tctl delete -f ./config/mgmt-cluster/tsb/abc/05-groups.yaml ;
  tctl delete -f ./config/mgmt-cluster/tsb/abc/04-workspaces.yaml ;

  # Remove tier1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/mgmt-cluster/k8s/abc ;
  kubectl delete secret app-abc-certs -n gateway-tier1

  exit 0
fi


if [[ ${ACTION} = "deploy-app-def" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Pull and load demo application image
  load_demo_app_image ${ACTIVE_CLUSTER_PROFILE}
  load_demo_app_image ${STANDBY_CLUSTER_PROFILE}

  # Deploy tier1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/mgmt-cluster/k8s/def ;

  # Deploy tier1 secrets if needed
  if [[ ${TIER1_MODE} = "https" ]]; then
    kubectl create secret tls app-def-certs -n gateway-tier1 \
      --key certs/app-def/server.def.tetrate.prod.key \
      --cert certs/app-def/server.def.tetrate.prod.pem ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    kubectl create secret generic app-def-certs -n gateway-tier1 \
      --from-file=tls.key=certs/app-def/server.def.tetrate.prod.key \
      --from-file=tls.crt=certs/app-def/server.def.tetrate.prod.pem \
      --from-file=ca.crt=certs/root-cert.pem ;
  fi

  # Deploy workspaces, groups, gateways and security for DEF (mgmt cluster)
  tctl apply -f ./config/mgmt-cluster/tsb/def/04-workspaces.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/def/05-groups.yaml ;
  if [[ ${TIER1_MODE} = "http" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/def/06-tier1-http.yaml ;
  fi
  if [[ ${TIER1_MODE} = "https" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/def/06-tier1-https.yaml ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    tctl apply -f ./config/mgmt-cluster/tsb/def/06-tier1-mtls.yaml ;
  fi 
  tctl apply -f ./config/mgmt-cluster/tsb/def/06-ingress.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/def/07-security.yaml ;

  # Application deployment in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/active-cluster/apps/def ;

  # Application deployment in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl apply -f ./config/standby-cluster/apps/def ;

  exit 0
fi


if [[ ${ACTION} = "undeploy-app-def" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Application removal in standby cluster
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/standby-cluster/apps/def ;

  # Application removal in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/active-cluster/apps/def ;

  # Remove workspaces, groups, gateways and security for DEF (mgmt cluster)
  tctl delete -f ./config/mgmt-cluster/tsb/def/07-security.yaml ;
  tctl delete -f ./config/mgmt-cluster/tsb/def/06-ingress.yaml ;
  if [[ ${TIER1_MODE} = "http" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/def/06-tier1-http.yaml ;
  fi
  if [[ ${TIER1_MODE} = "https" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/def/06-tier1-https.yaml ;
  fi
  if [[ ${TIER1_MODE} = "mtls" ]]; then
    tctl delete -f ./config/mgmt-cluster/tsb/def/06-tier1-mtls.yaml ;
  fi 
  tctl delete -f ./config/mgmt-cluster/tsb/def/05-groups.yaml ;
  tctl delete -f ./config/mgmt-cluster/tsb/def/04-workspaces.yaml ;

  # Remove tier1 GW in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl delete -f ./config/mgmt-cluster/k8s/def ;
  kubectl delete secret app-def-certs -n gateway-tier1

  exit 0
fi


if [[ ${ACTION} = "traffic-cmd-abc" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  T1_GW_IP=$(kubectl get svc -n gateway-tier1 gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  INGRESS_ACTIVE_GW_IP=$(kubectl get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  INGRESS_STANDBY_GW_IP=$(kubectl get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "****************************"
  echo "*** ABC Traffic Commands ***"
  echo "****************************"
  echo
  echo "Traffic to Active Ingress Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:80:${INGRESS_ACTIVE_GW_IP}\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo "Traffic to Standby Ingress Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:80:${INGRESS_STANDBY_GW_IP}\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  echo
  echo "Traffic through T1 Gateway: HTTP"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:80:${T1_GW_IP}\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  echo "Traffic through T1 Gateway: HTTPS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:443:${T1_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  echo "Traffic through T1 Gateway: MTLS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:443:${T1_GW_IP}\" --cacert ca.crt=certs/root-cert.pem --cert certs/app-abc/client.abc.tetrate.prod.pem --key certs/app-abc/client.abc.tetrate.prod.key \"https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  exit 0
fi


if [[ ${ACTION} = "traffic-cmd-def" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  T1_GW_IP=$(kubectl get svc -n gateway-tier1 gw-tier1-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  INGRESS_ACTIVE_GW_IP=$(kubectl get svc -n gateway-def gw-ingress-def --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "****************************"
  echo "*** DEF Traffic Commands ***"
  echo "****************************"
  echo
  echo "Traffic to Active Ingress Gateway"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"def.tetrate.prod:80:${INGRESS_ACTIVE_GW_IP}\" \"http://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" ${NC}\n"
  echo
  echo
  echo "Traffic through T1 Gateway: HTTP"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"def.tetrate.prod:80:${T1_GW_IP}\" \"http://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" ${NC}\n"
  echo
  echo "Traffic through T1 Gateway: HTTPS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"def.tetrate.prod:443:${T1_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" ${NC}\n"
  echo
  echo "Traffic through T1 Gateway: MTLS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"def.tetrate.prod:443:${T1_GW_IP}\" --cacert ca.crt=certs/root-cert.pem --cert certs/app-def/client.def.tetrate.prod.pem --key certs/app-def/client.def.tetrate.prod.key \"https://def.tetrate.prod/proxy/app-e.ns-e/proxy/app-f.ns-f\" ${NC}\n"
  echo
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - deploy-app-abc http/https/mtls"
echo "  - undeploy-app-def http/https/mtls"
echo "  - deploy-app-abc http/https/mtls"
echo "  - undeploy-app-def http/https/mtls"
echo "  - traffic-cmd-abc"
echo "  - traffic-cmd-def"
exit 1
