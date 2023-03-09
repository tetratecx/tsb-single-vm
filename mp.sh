#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/env.sh
source ${ROOT_DIR}/certs.sh

ACTION=${1}

# Patch deployment still using dockerhub: tsb/ratelimit-redis
#   args:
#     (1) cluster kubeconfig context
function patch_dockerhub_dep_redis {
  while ! kubectl --context ${1} -n tsb set image deployment/ratelimit-redis redis=containers.dl.tetrate.io/redis:7.0.5-alpine &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment tsb/ratelimit-redis sucessfully patched"
}

# Patch deployment still using dockerhub: istio-system/ratelimit-server
#   args:
#     (1) cluster kubeconfig context
function patch_dockerhub_dep_ratelimit {
  while ! kubectl --context ${1} -n istio-system set image deployment/ratelimit-server ratelimit=containers.dl.tetrate.io/ratelimit:5e9a43f9 &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment istio-system/ratelimit-server sucessfully patched"
}

# Login as admin into tsb
#   args:
#     (1) cluster kubeconfig context
#     (2) organization
function login_tsb_admin {
  kubectl config use-context ${1} ;
  expect <<DONE
  spawn tctl login --username admin --password admin --org ${2}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) cluster kubeconfig context
function patch_oap_refresh_rate_mp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n tsb patch managementplanes managementplane --type merge --patch ${OAP_PATCH}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster kubeconfig context
function patch_oap_refresh_rate_cp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n istio-system patch controlplanes controlplane --type merge --patch ${OAP_PATCH}
}

# Expose tsb gui with kubectl port-forward
#   args:
#     (1) cluster kubeconfig context
function expose_tsb_gui {
  if ! [[ -f "/etc/systemd/system/tsb-gui.service" ]] ; then
    sudo tee /etc/systemd/system/tsb-gui.service << EOF
[Unit]
Description=TSB GUI Exposure

[Service]
ExecStart=$(which kubectl) --kubeconfig ${HOME}/.kube/config --context ${1} port-forward -n tsb service/envoy 8443:8443 --address 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  fi

  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;
  echo "The tsb gui should be available at https://$(curl -s ifconfig.me):8443"
}


if [[ ${ACTION} = "install" ]]; then

  MP_CLUSTER_CONTEXT=$(get_mp_minikube_profile) ;
  MP_CLUSTER_NAME=$(get_mp_name) ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  generate_istio_cert ${MP_CLUSTER_NAME} ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  if ! kubectl --context ${MP_CLUSTER_CONTEXT} get ns istio-system &>/dev/null; then
    kubectl --context ${MP_CLUSTER_CONTEXT} create ns istio-system ; 
  fi
  if ! kubectl --context ${MP_CLUSTER_CONTEXT} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${MP_CLUSTER_CONTEXT} create secret generic cacerts -n istio-system \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/ca-cert.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/ca-key.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/root-cert.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/cert-chain.pem ;
  fi
  
  # start patching deployments that depend on dockerhub asynchronously
  patch_dockerhub_dep_redis ${MP_CLUSTER_CONTEXT} &
  patch_dockerhub_dep_ratelimit ${MP_CLUSTER_CONTEXT} &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane in a demo cluster!
  kubectl config use-context ${MP_CLUSTER_CONTEXT} ;
  tctl install demo --registry containers.dl.tetrate.io --admin-password admin --set spec.managementPlane.clusterName=${MP_CLUSTER_NAME};

  # Wait for the management, control and data plane to become available
  kubectl --context ${MP_CLUSTER_CONTEXT} wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_CONTEXT} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_CONTEXT} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --context ${MP_CLUSTER_CONTEXT} get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl --context ${MP_CLUSTER_CONTEXT} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${MP_CLUSTER_CONTEXT} ;
  patch_oap_refresh_rate_cp ${MP_CLUSTER_CONTEXT} ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  MP_OUTPUT_DIR=$(get_mp_output_dir) ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/mp-certs.pem ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/es-certs.pem ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/xcp-central-ca-certs.pem ;

  expose_tsb_gui ${MP_CLUSTER_CONTEXT} ;

  exit 0
fi

if [[ ${ACTION} = "uninstall" ]]; then

  MP_CLUSTER_CONTEXT=$(get_mp_minikube_profile) ;

  # Put operators to sleep
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_CONTEXT} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} scale deployment {} -n ${NS} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_CONTEXT} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete deployment {} -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${MP_CLUSTER_CONTEXT} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_CONTEXT} delete --all jobs -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_CONTEXT} delete --all statefulset -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_CONTEXT} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} patch deployment {} -n ${NS} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --context ${MP_CLUSTER_CONTEXT} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${MP_CLUSTER_CONTEXT} delete namespace ${NS} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --context ${MP_CLUSTER_CONTEXT} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete crd {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --context ${MP_CLUSTER_CONTEXT} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --context ${MP_CLUSTER_CONTEXT} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_CONTEXT} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_CONTEXT} get namespace ${NS} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --context ${MP_CLUSTER_CONTEXT} replace --raw /api/v1/namespaces/${NS}/finalize -f - ;
  done

  sleep 10 ;

  exit 0
fi


if [[ ${ACTION} = "reset" ]]; then

  MP_CLUSTER_CONTEXT=$(get_mp_minikube_profile) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin ${MP_CLUSTER_CONTEXT} tetrate ;

  # Remove all TSB configuration objects
  kubectl config use-context ${MP_CLUSTER_CONTEXT} ;
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects
  kubectl --context ${MP_CLUSTER_CONTEXT} get -A egressgateways.install.tetrate.io,ingressgateways.install.tetrate.io,tier1gateways.install.tetrate.io -o yaml \
   | kubectl --context ${MP_CLUSTER_CONTEXT} delete -f - ;

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - install"
echo "  - uninstall"
echo "  - reset"
exit 1
