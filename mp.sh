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

# Uninstall tsb installation
#   args:
#     (1) cluster profile/name
function uninstall_tsb {
  kubectl config use-context ${1} ;

  # Put operators to sleep
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl scale deployment {} -n ${NS} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl delete deployment {} -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    kubectl delete --all jobs -n ${NS} --timeout=10s --wait=false ;
    kubectl delete --all statefulset -n ${NS} --timeout=10s --wait=false ;
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl patch deployment {} -n ${NS} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl delete namespace ${NS} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;
  kubectl get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl delete clusterrole {} --timeout=10s --wait=false ;
  kubectl get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl get namespace ${NS} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl replace --raw /api/v1/namespaces/${NS}/finalize -f - ;
  done
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

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${MP_CLUSTER_PROFILE} ;
  patch_oap_refresh_rate_cp ${MP_CLUSTER_PROFILE} ;

  exit 0
fi

if [[ ${ACTION} = "uninstall" ]]; then

  MP_CLUSTER_PROFILE=$(get_mp_minikube_profile) ;

  # Remove tsb completely mp cluster
  uninstall_tsb ${MP_CLUSTER_PROFILE} ;
  sleep 10 ;

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
