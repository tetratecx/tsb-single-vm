#!/usr/bin/env bash

ACTION=${1}
TIER1_MODE=${2}
TIER2_MODE=${3}
APP_ABC_MODE=${4}

GREEN='\033[0;32m'
NC='\033[0m'

MGMT_CLUSTER_PROFILE=mgmt-cluster
ACTIVE_CLUSTER_PROFILE=active-cluster
STANDBY_CLUSTER_PROFILE=standby-cluster

TSB_CONFDIR=./config/00-tsb-config
MGMT_CLUSTER_CONFDIR=./config/01-mgmt-cluster
ACTIVE_CLUSTER_CONFDIR=./config/02-active-cluster
STANDBY_CLUSTER_CONFDIR=./config/03-standby-cluster

ROOT_CERTDIR=./certs
APP_ABC_CERTDIR=${ROOT_CERTDIR}/app-abc
MGMT_CLUSTER_CERTDIR=./certs/mgmt-cluster
ACTIVE_CLUSTER_CERTDIR=./certs/active-cluster
STANDBY_CLUSTER_CERTDIR=./certs/standby-cluster

GW_K8S_CONFDIR=./apps/gateways
APP_A_K8S_CONFDIR=./apps/app-a
APP_B_K8S_CONFDIR=./apps/app-b
APP_C_K8S_CONFDIR=./apps/app-c

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


if [[ ${ACTION} = "deploy-app" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Clusters, organization and tenants
  tctl apply -f ${TSB_CONFDIR}/01-clusters.yaml ;
  tctl apply -f ${TSB_CONFDIR}/02-organization.yaml ;
  tctl apply -f ${TSB_CONFDIR}/03-tenants.yaml ;

  # Deploy tier1 GW in mgmt cluster (certs if needed)
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl apply -f ${GW_K8S_CONFDIR}/01-tier1-namespace.yaml ;
  if [[ ${TIER1_MODE} = "https" ]]; then
    kubectl create secret tls app-abc-certs -n gateway-tier1 \
      --key ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.key \
      --cert ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.pem ;
  elif [[ ${TIER1_MODE} = "mtls" ]]; then
    kubectl create secret generic app-abc-certs -n gateway-tier1 \
      --from-file=tls.key=${APP_ABC_CERTDIR}/server.abc.tetrate.prod.key \
      --from-file=tls.crt=${APP_ABC_CERTDIR}/server.abc.tetrate.prod.pem \
      --from-file=ca.crt=${ROOT_CERTDIR}/root-cert.pem ;
  fi
  kubectl apply -f ${GW_K8S_CONFDIR}/02-tier1-gateway.yaml ;

  # Deploy tier2 GW in active cluster
  #   (with east-west GW if needed)
  #   (with certs if needed)
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ${GW_K8S_CONFDIR}/03-tier2-namespace.yaml ;
  if [[ ${TIER2_MODE} = "https" ]]; then
    kubectl create secret tls app-abc-certs -n gateway-abc \
      --key ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.key \
      --cert ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.pem ;
  fi
  kubectl apply -f ${GW_K8S_CONFDIR}/04-tier2-gateway.yaml ;
  if [[ ${APP_ABC_MODE} = "active-standby" ]] ; then
    kubectl apply -f ${GW_K8S_CONFDIR}/05-eastwest-gateway.yaml ;
  fi

  # Deploy tier2 GW in standby cluster (if needed) with east-west GW
  #   (with certs if needed)
  if [[ ${APP_ABC_MODE} = "active-standby" ]] ; then
    kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
    kubectl apply -f ${GW_K8S_CONFDIR}/03-tier2-namespace.yaml ;
    if [[ ${TIER2_MODE} = "https" ]]; then
      kubectl create secret tls app-abc-certs -n gateway-abc \
        --key ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.key \
        --cert ${APP_ABC_CERTDIR}/server.abc.tetrate.prod.pem ;
    fi
    kubectl apply -f ${GW_K8S_CONFDIR}/04-tier2-gateway.yaml ;
    kubectl apply -f ${GW_K8S_CONFDIR}/05-eastwest-gateway.yaml ;
  fi

  # Deploy workspaces, workspacesettings, groups, gateways and security
  tctl apply -f ${TSB_CONFDIR}/04-workspaces.yaml ;
  if [[ ${APP_ABC_MODE} = "active" ]]; then
    tctl apply -f ${TSB_CONFDIR}/05-workspace-settings.yaml ;
  elif [[ ${APP_ABC_MODE} = "active-standby" ]]; then
    tctl apply -f ${TSB_CONFDIR}/05-workspace-settings-failover.yaml ;
  fi
  tctl apply -f ${TSB_CONFDIR}/06-groups.yaml ;
  if [[ ${TIER1_MODE} = "http" ]]; then
    tctl apply -f ${TSB_CONFDIR}/07-tier1-http.yaml ;
  elif [[ ${TIER1_MODE} = "https" ]]; then
    tctl apply -f ${TSB_CONFDIR}/07-tier1-https.yaml ;
  elif [[ ${TIER1_MODE} = "mtls" ]]; then
    tctl apply -f ${TSB_CONFDIR}/07-tier1-mtls.yaml ;
  fi 
  if [[ ${TIER2_MODE} = "http" ]]; then
    tctl apply -f ${TSB_CONFDIR}/08-ingress-http.yaml ;
  elif [[ ${TIER2_MODE} = "https" ]]; then
    tctl apply -f ${TSB_CONFDIR}/08-ingress-https.yaml ;
  fi 
  tctl apply -f ${TSB_CONFDIR}/09-security.yaml ;

  # Application deployment in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl apply -f ${APP_A_K8S_CONFDIR}/k8s ;
  kubectl apply -f ${APP_B_K8S_CONFDIR}/k8s ;
  kubectl apply -f ${APP_C_K8S_CONFDIR}/k8s ;

  # Application deployment in standby cluster (if needed)
  if [[ ${APP_ABC_MODE} = "active-standby" ]] ; then
    kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
    kubectl apply -f ${APP_A_K8S_CONFDIR}/k8s ;
    kubectl apply -f ${APP_B_K8S_CONFDIR}/k8s ;
    kubectl apply -f ${APP_C_K8S_CONFDIR}/k8s ;
  fi

  exit 0
fi


if [[ ${ACTION} = "undeploy-app" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Delete tsb configuration
  for TSB_FILE in $(ls -1 ${TSB_CONFDIR} | sort -r) ; do
    tctl delete -f ${TSB_CONFDIR}/${TSB_FILE} 2>/dev/null ;
  done

  # Delete kubernetes configuration in mgmt cluster
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl delete -f ${GW_K8S_CONFDIR} 2>/dev/null ;

  # Delete kubernetes configuration in active cluster
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl delete -f ${APP_A_K8S_CONFDIR}/k8s 2>/dev/null ;
  kubectl delete -f ${APP_B_K8S_CONFDIR}/k8s 2>/dev/null ;
  kubectl delete -f ${APP_C_K8S_CONFDIR}/k8s 2>/dev/null ;
  kubectl delete -f ${GW_K8S_CONFDIR} 2>/dev/null ;

  # Delete kubernetes configuration in standby cluster (if needed)
  if [[ ${APP_ABC_MODE} = "active-standby" ]] ; then
    kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
    kubectl delete -f ${APP_A_K8S_CONFDIR}/k8s 2>/dev/null ;
    kubectl delete -f ${APP_B_K8S_CONFDIR}/k8s 2>/dev/null ;
    kubectl delete -f ${APP_C_K8S_CONFDIR}/k8s 2>/dev/null ;
    kubectl delete -f ${GW_K8S_CONFDIR} 2>/dev/null ;
  fi

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
  echo "Traffic to Active Ingress Gateway: HTTP"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:80:${INGRESS_ACTIVE_GW_IP}\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo "Traffic to Standby Ingress Gateway: HTTP"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:80:${INGRESS_STANDBY_GW_IP}\" \"http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo
  echo "Traffic to Active Ingress Gateway: HTTPS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:443:${INGRESS_ACTIVE_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
  echo "Traffic to Standby Ingress Gateway: HTTPS"
  printf "${GREEN}curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.tetrate.prod:443:${INGRESS_STANDBY_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c\" ${NC}\n"
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


echo "Please specify one of the following action:"
echo "  - deploy-app"
echo "  - undeploy-app"
echo "  - traffic-cmd-abc"
echo "  - traffic-cmd-def"
exit 1
