#!/usr/bin/env bash

ACTION=${1}
CLUSTER=${2}

MGMT_CLUSTER_PROFILE=mgmt-cluster
ACTIVE_CLUSTER_PROFILE=active-cluster
STANDBY_CLUSTER_PROFILE=standby-cluster

MGMT_CLUSTER_CONFDIR=./config/01-mgmt-cluster
ACTIVE_CLUSTER_CONFDIR=./config/02-active-cluster
STANDBY_CLUSTER_CONFDIR=./config/03-standby-cluster

MGMT_CLUSTER_CERTDIR=./certs/mgmt-cluster
ACTIVE_CLUSTER_CERTDIR=./certs/active-cluster
STANDBY_CLUSTER_CERTDIR=./certs/standby-cluster

# Patch deployment still using dockerhub: tsb/ratelimit-redis
function patch_dockerhub_dep_redis {
  while ! kubectl --context ${MGMT_CLUSTER_PROFILE} -n tsb set image deployment/ratelimit-redis redis=containers.dl.tetrate.io/redis:7.0.5-alpine &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment tsb/ratelimit-redis sucessfully patched"
}

# Patch deployment still using dockerhub: istio-system/ratelimit-server
function patch_dockerhub_dep_ratelimit {
  while ! kubectl --context ${MGMT_CLUSTER_PROFILE} -n istio-system set image deployment/ratelimit-server ratelimit=containers.dl.tetrate.io/ratelimit:5e9a43f9 &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment istio-system/ratelimit-server sucessfully patched"
}

# Create cacert secret in istio-system namespace
#   args:
#     (1) cluster profile
#     (2) certificate directory
function create_cert_secret {
  if ! kubectl --context ${1} get ns istio-system &>/dev/null; then
    kubectl --context ${1} create ns istio-system ; 
  fi
  if ! kubectl --context ${1} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${1} create secret generic cacerts -n istio-system \
    --from-file=${2}/ca-cert.pem \
    --from-file=${2}/ca-key.pem \
    --from-file=${2}/root-cert.pem \
    --from-file=${2}/cert-chain.pem
  fi
}

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

# Force delete a namespace
#   args:
#     (1) namespace
function force_delete_namespace {
  kubectl proxy &>/dev/null &
  PROXY_PID=$!
  killproxy () {
    kill $PROXY_PID
  }
  trap killproxy EXIT

  sleep 1 # give the proxy a second
  kubectl get namespace ${1} -o json | \
    jq 'del(.spec.finalizers[] | select("kubernetes"))' | \
    curl -s -k -H "Content-Type: application/json" -X PUT -o /dev/null --data-binary @- http://localhost:8001/api/v1/namespaces/${1}/finalize && \
    echo "Killed namespace: ${1}"
}

if [[ ${ACTION} = "mgmt-cluster-install" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret ${MGMT_CLUSTER_PROFILE} ${MGMT_CLUSTER_CERTDIR}  ;

  # start patching deployments that depend on dockerhub asynchronously
  patch_dockerhub_dep_redis &
  patch_dockerhub_dep_ratelimit &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane in a demo cluster!
  tctl install demo --registry containers.dl.tetrate.io --admin-password admin ;

  # Wait for the management, control and data plane to become available
  kubectl wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s
  kubectl wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s
  kubectl wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s
  while ! kubectl get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl wait deployment -n istio-system edge --for condition=Available=True --timeout=600s
  kubectl get pods -A

  # Deploy operators
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
  login_tsb_admin tetrate ;
  tctl install manifest cluster-operators --registry containers.dl.tetrate.io > ${MGMT_CLUSTER_CONFDIR}/clusteroperators.yaml ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  kubectl get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/mp-certs.pem ;
  kubectl get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/es-certs.pem ;
  kubectl get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/xcp-central-ca-certs.pem ;

  # Apply AOP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  kubectl -n tsb patch managementplanes managementplane --patch-file ${MGMT_CLUSTER_CONFDIR}/oap-deploy-patch.yaml --type merge
  kubectl -n istio-system patch controlplanes controlplane --patch-file ${MGMT_CLUSTER_CONFDIR}/oap-deploy-patch.yaml --type merge

  exit 0
fi


if [[ ${ACTION} = "app-cluster-install" ]]; then

  if [[ ${CLUSTER} = "active-cluster" ]]; then
    CLUSTER_PROFILE=${ACTIVE_CLUSTER_PROFILE}
    CLUSTER_CONFDIR=${ACTIVE_CLUSTER_CONFDIR}
    CLUSTER_CERTDIR=${ACTIVE_CLUSTER_CERTDIR}
  elif [[ ${CLUSTER} = "standby-cluster" ]]; then
    CLUSTER_PROFILE=${STANDBY_CLUSTER_PROFILE}
    CLUSTER_CONFDIR=${STANDBY_CLUSTER_CONFDIR}
    CLUSTER_CERTDIR=${STANDBY_CLUSTER_CERTDIR}
  else
    echo "Please specify one of the following cluster:"
    echo "  - active-cluster"
    echo "  - standby-cluster"
    exit 1
  fi

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  TSB_API_ENDPOINT=$(kubectl --context ${MGMT_CLUSTER_PROFILE} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  kubectl config use-context ${CLUSTER_PROFILE} ;

  # Generate a service account private key for the active cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install cluster-service-account --cluster ${CLUSTER_PROFILE} > ${CLUSTER_CONFDIR}/cluster-service-account.jwk ;

  # Create control plane secrets
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install manifest control-plane-secrets \
    --cluster ${CLUSTER_PROFILE} \
    --cluster-service-account="$(cat ${CLUSTER_CONFDIR}/cluster-service-account.jwk)" \
    --elastic-ca-certificate="$(cat ${MGMT_CLUSTER_CONFDIR}/es-certs.pem)" \
    --management-plane-ca-certificate="$(cat ${MGMT_CLUSTER_CONFDIR}/mp-certs.pem)" \
    --xcp-central-ca-bundle="$(cat ${MGMT_CLUSTER_CONFDIR}/xcp-central-ca-certs.pem)" \
    > ${CLUSTER_CONFDIR}/controlplane-secrets.yaml ;

  # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
  cat ${CLUSTER_CONFDIR}/controlplane-template.yaml | sed s/__TSB_API_ENDPOINT__/${TSB_API_ENDPOINT}/g \
    > ${CLUSTER_CONFDIR}/controlplane.yaml ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret ${CLUSTER_PROFILE} ${CLUSTER_CERTDIR};

  # Applying operator, secrets and control plane configuration
  kubectl apply -f ${MGMT_CLUSTER_CONFDIR}/clusteroperators.yaml 
  kubectl apply -f ${CLUSTER_CONFDIR}/controlplane-secrets.yaml ;
  while ! kubectl get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
  kubectl apply -f ${CLUSTER_CONFDIR}/controlplane.yaml ;

  # Apply AOP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  kubectl -n istio-system patch controlplanes controlplane --patch-file ${CLUSTER_CONFDIR}/oap-deploy-patch.yaml --type merge

  # Wait for the control and data plane to become available
  kubectl wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s
  kubectl wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s
  while ! kubectl get deployment -n istio-system edge &>/dev/null; do sleep 5; done ;
  kubectl wait deployment -n istio-system edge --for condition=Available=True --timeout=600s
  kubectl get pods -A

  exit 0
fi


if [[ ${ACTION} = "reset-tsb" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;

  # Remove all TSB configuration objects
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects
  kubectl get -A egressgateways.install.tetrate.io,ingressgateways.install.tetrate.io,tier1gateways.install.tetrate.io -o yaml \
   | kubectl delete -f - ;

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - mgmt-cluster-install"
echo "  - app-cluster-install"
echo "  - reset-tsb"
exit 1
