#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
CONF_BASE_DIR=${ROOT_DIR}/output/config

source ${ROOT_DIR}/env.sh
source ${ROOT_DIR}/certs.sh

ACTION=${1}

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
#     (1) cluster profile/name
function create_cert_secret {
  CLUSTER_PROFILE=${1}
  generate_istio_cert ${CLUSTER_PROFILE} ;

  if ! kubectl --context ${1} get ns istio-system &>/dev/null; then
    kubectl --context ${1} create ns istio-system ; 
  fi
  if ! kubectl --context ${1} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${1} create secret generic cacerts -n istio-system \
    --from-file=${CERT_BASE_DIR}/${CLUSTER_PROFILE}/ca-cert.pem \
    --from-file=${CERT_BASE_DIR}/${CLUSTER_PROFILE}/ca-key.pem \
    --from-file=${CERT_BASE_DIR}/${CLUSTER_PROFILE}/root-cert.pem \
    --from-file=${CERT_BASE_DIR}/${CLUSTER_PROFILE}/cert-chain.pem
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

# Patch OAP refresh rate of management plane
#   args:
#     (1) cluster profile/name
function patch_oap_refresh_rate_mp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n tsb patch managementplanes managementplane --type merge --patch ${OAP_PATCH}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster profile/name
function patch_oap_refresh_rate_cp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n istio-system patch controlplanes controlplane --type merge --patch ${OAP_PATCH}
}

if [[ ${ACTION} = "install" ]]; then

  MP_CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  echo ${MP_CLUSTER_PROFILE}

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret ${MP_CLUSTER_PROFILE} ;
  
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

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  # kubectl get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/mp-certs.pem ;
  # kubectl get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/es-certs.pem ;
  # kubectl get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MGMT_CLUSTER_CONFDIR}/xcp-central-ca-certs.pem ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${MP_CLUSTER_PROFILE} ;
  patch_oap_refresh_rate_cp ${MP_CLUSTER_PROFILE} ;

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
echo "  - install"
echo "  - uninstall"
echo "  - reset"
exit 1
