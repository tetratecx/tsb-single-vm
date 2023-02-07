#!/usr/bin/env bash

ACTION=${1}
TIER1_MODE=${2}
TIER2_MODE=${3}
APP_ABC_MODE=${4}
VM_NAME=${5}

GREEN='\033[0;32m'
NC='\033[0m'

MGMT_CLUSTER_PROFILE=mgmt-cluster
ACTIVE_CLUSTER_PROFILE=active-cluster
STANDBY_CLUSTER_PROFILE=standby-cluster

TSB_CONFDIR=./config/00-tsb-config
MGMT_CLUSTER_CONFDIR=./config/01-mgmt-cluster
ACTIVE_CLUSTER_CONFDIR=./config/02-active-cluster
VM_APP_A_CONFDIR=./config/04-ubuntu-vm-a
VM_APP_B_CONFDIR=./config/05-ubuntu-vm-b
VM_APP_C_CONFDIR=./config/06-ubuntu-vm-c

ROOT_CERTDIR=./certs
APP_ABC_CERTDIR=${ROOT_CERTDIR}/app-abc
MGMT_CLUSTER_CERTDIR=./certs/mgmt-cluster
ACTIVE_CLUSTER_CERTDIR=./certs/active-cluster
STANDBY_CLUSTER_CERTDIR=./certs/standby-cluster
VM_ONBOARDING_CERTDIR=./certs/vm-onboarding

GW_K8S_CONFDIR=./apps/gateways


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

# Get vm bridge ip address
#   args:
#     (1) vm name
function get_vm_bridge_ip {
  echo $(vboxmanage guestproperty get ${1} "/VirtualBox/GuestInfo/Net/0/V4/IP" | cut -d " " -f2)
}

if [[ ${ACTION} = "deploy-app" ]]; then

  if [[ ${VM_NAME} = "ubuntu-vm-a" ]]; then
    VM_CONFDIR=${VM_APP_A_CONFDIR}
    SVCNAME=app-a
    APP_K8S_CONFDIR=./apps/app-a
  elif [[ ${VM_NAME} = "ubuntu-vm-b" ]]; then
    VM_CONFDIR=${VM_APP_B_CONFDIR}
    SVCNAME=app-b
    APP_K8S_CONFDIR=./apps/app-b
  elif [[ ${VM_NAME} = "ubuntu-vm-c" ]]; then
    VM_CONFDIR=${VM_APP_C_CONFDIR}
    SVCNAME=app-c
    APP_K8S_CONFDIR=./apps/app-c
  else
    echo "Please specify one of the following vms:"
    echo "  - ubuntu-vm-a"
    echo "  - ubuntu-vm-b"
    echo "  - ubuntu-vm-c"
    exit 1
  fi

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

  VM_IP=$(get_vm_bridge_ip ${VM_NAME}) ;
  VM_SSH_EXEC="ssh -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_IP} -- " ;

  # Login to TSB private docker registry and pull demo container
  ${VM_SSH_EXEC} docker login -u ${TSB_DOCKER_USERNAME} -p ${TSB_DOCKER_PASSWORD} containers.dl.tetrate.io ;
  ${VM_SSH_EXEC} docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;

  # Start app in a container (listen on 127.0.0.1)
  if ! ${VM_SSH_EXEC} docker ps | grep containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    ${VM_SSH_EXEC} docker run -d --restart=always --net=host --name ${SVCNAME} \
        -e SVCNAME=${SVCNAME} \
      containers.dl.tetrate.io/obs-tester-server:1.0 \
        --log-output-level=all:debug \
        --http-listen-address=:8080 \
        --health-address=127.0.0.1:7777 \
        --ep-duration=0 \
        --ep-errors=0 \
        --ep-headers=0 \
        --zipkin-reporter-endpoint=http://zipkin.istio-system:9411/api/v2/spans \
        --zipkin-sample-rate=1.0 \
        --zipkin-singlehost-spans ;
  fi

  # Apply vm onboarding patch to create a VM gateway and allow jwt based onboarding
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding#allow-workloads-to-authenticate-themselves-by-means-of-a-jwt-token
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  if ! kubectl get secret vm-onboarding -n istio-system &>/dev/null ; then
    kubectl create secret tls vm-onboarding -n istio-system \
      --key ${VM_ONBOARDING_CERTDIR}/server.vm-onboarding.tetrate.prod.key \
      --cert ${VM_ONBOARDING_CERTDIR}/server.vm-onboarding.tetrate.prod.pem ;
  fi

  kubectl -n istio-system patch controlplanes controlplane --patch-file ${ACTIVE_CLUSTER_CONFDIR}/onboarding-vm-patch.yaml --type merge ;

  # Create WorkloadGroup, Sidecar and OnboardingPolicy for app
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding
  kubectl apply -f ${APP_K8S_CONFDIR}/vm ;

  # Add /etc/host entries for egress
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/guides/setup#workload-configuration-egress
  if ! ${VM_SSH_EXEC} cat /etc/hosts | grep "The following lines are insterted for istio" &>/dev/null ; then
    scp -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no ${VM_CONFDIR}/hosts tsbadmin@${VM_IP}:/tmp/hosts ;
    ${VM_SSH_EXEC} "cat /tmp/hosts | sudo tee -a /etc/hosts ;"
  fi

  echo "Getting vm gateway exernal ip address"
  while ! VM_GW_IP=$(kubectl get svc -n istio-system vmgateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    echo -n "."
  done
  echo "DONE"

  # Install istio sidecar, onboarding agent and sample jwt credential plugin
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-istio-sidecar
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-workload-onboarding-agent
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-sample-jwt-credential-plugin
  scp -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no ${VM_CONFDIR}/sample-jwt-issuer.jwk tsbadmin@${VM_IP}:/tmp/jwt-issuer.jwk
  ${VM_SSH_EXEC} sudo mkdir -p /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin
  ${VM_SSH_EXEC} sudo cp /tmp/jwt-issuer.jwk /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk
  ${VM_SSH_EXEC} sudo chmod 400 /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk
  ${VM_SSH_EXEC} sudo chown onboarding-agent: -R /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/

  scp -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no ${VM_CONFDIR}/agent.config.yaml tsbadmin@${VM_IP}:/tmp/agent.config.yaml
  ${VM_SSH_EXEC} sudo mkdir -p /etc/onboarding-agent
  ${VM_SSH_EXEC} sudo cp /tmp/agent.config.yaml /etc/onboarding-agent/agent.config.yaml

  cat ${VM_CONFDIR}/install-onboarding-template.sh | sed s/__TSB_VM_ONBOARDING_ENDPOINT__/${VM_GW_IP}/g > ${VM_CONFDIR}/install-onboarding.sh ;
  scp -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no ${VM_CONFDIR}/install-onboarding.sh tsbadmin@${VM_IP}:/tmp/install-onboarding.sh
  ${VM_SSH_EXEC} chmod +x /tmp/install-onboarding.sh
  ${VM_SSH_EXEC} sudo /tmp/install-onboarding.sh

  # Configure OnboardingConfiguration
  # REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/onboard-vm
  cat ${VM_CONFDIR}/apps/onboarding.config-template.yaml | sed s/__TSB_VM_ONBOARDING_ENDPOINT__/${VM_GW_IP}/g > ${VM_CONFDIR}/apps/onboarding.config.yaml ;
  scp -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no ${VM_CONFDIR}/apps/onboarding.config.yaml tsbadmin@${VM_IP}:/tmp/onboarding.config.yaml
  ${VM_SSH_EXEC} sudo mkdir -p /etc/onboarding-agent
  ${VM_SSH_EXEC} sudo cp /tmp/onboarding.config.yaml /etc/onboarding-agent/onboarding.config.yaml

  ### START ONBOARDING AGENT ###
  if ${VM_SSH_EXEC} systemctl is-active onboarding-agent.service &>/dev/null ; then
    ${VM_SSH_EXEC} sudo systemctl stop onboarding-agent
  fi
  ${VM_SSH_EXEC} sudo systemctl enable onboarding-agent
  ${VM_SSH_EXEC} sudo systemctl start onboarding-agent


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
