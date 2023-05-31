#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}

INSTALL_REPO_PW=$(get_install_repo_password) ;
INSTALL_REPO_URL=$(get_install_repo_url) ;
INSTALL_REPO_USER=$(get_install_repo_user) ;

# Patch deployment still using dockerhub: tsb/ratelimit-redis
#   args:
#     (1) cluster name
function patch_dockerhub_dep_redis {
  while ! kubectl --context ${1} -n tsb set image deployment/ratelimit-redis redis=${INSTALL_REPO_URL}/redis:7.0.7-alpine3.17 &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment tsb/ratelimit-redis sucessfully patched"
}

# Patch deployment still using dockerhub: istio-system/ratelimit-server
#   args:
#     (1) cluster name
function patch_dockerhub_dep_ratelimit {
  while ! kubectl --context ${1} -n istio-system set image deployment/ratelimit-server ratelimit=${INSTALL_REPO_URL}/ratelimit:f28024e3 &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment istio-system/ratelimit-server sucessfully patched"
}

# Login as admin into tsb
#   args:
#     (1) cluster name
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
#     (1) cluster name
function patch_oap_refresh_rate_mp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n tsb patch managementplanes managementplane --type merge --patch ${OAP_PATCH}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster name
function patch_oap_refresh_rate_cp {
  OAP_PATCH='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${1} -n istio-system patch controlplanes controlplane --type merge --patch ${OAP_PATCH}
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) cluster name
function patch_jwt_token_expiration_mp {
  TOKEN_PATCH='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}'
  kubectl --context ${1} -n tsb patch managementplanes managementplane --type merge --patch ${TOKEN_PATCH}
}

# Expose tsb gui with kubectl port-forward
#   args:
#     (1) cluster name
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
  echo "The tsb gui should be available locally at https://127.0.0.1:8443"
  echo "The tsb gui should be available remotely at https://$(curl -s ifconfig.me):8443"
}


if [[ ${ACTION} = "install" ]]; then

  MP_CLUSTER_NAME=$(get_mp_name) ;
  print_info "Start installation of tsb demo management/control plane in cluster ${MP_CLUSTER_NAME}"

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  generate_istio_cert ${MP_CLUSTER_NAME} ;
  CERTS_BASE_DIR=$(get_certs_base_dir) ;

  if ! kubectl --context ${MP_CLUSTER_NAME} get ns istio-system &>/dev/null; then
    kubectl --context ${MP_CLUSTER_NAME} create ns istio-system ;
  fi
  if ! kubectl --context ${MP_CLUSTER_NAME} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${MP_CLUSTER_NAME} create secret generic cacerts -n istio-system \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/ca-cert.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/ca-key.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/root-cert.pem \
      --from-file=${CERTS_BASE_DIR}/${MP_CLUSTER_NAME}/cert-chain.pem ;
  fi
  
  # start patching deployments that depend on dockerhub asynchronously
  patch_dockerhub_dep_redis ${MP_CLUSTER_NAME} &
  patch_dockerhub_dep_ratelimit ${MP_CLUSTER_NAME} &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane in a demo cluster!
  kubectl config use-context ${MP_CLUSTER_NAME} ;
  tctl install demo --registry ${INSTALL_REPO_URL} --admin-password admin ;

  # Wait for the management, control and data plane to become available
  kubectl --context ${MP_CLUSTER_NAME} wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_NAME} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_NAME} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --context ${MP_CLUSTER_NAME} get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl --context ${MP_CLUSTER_NAME} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --context ${MP_CLUSTER_NAME} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${MP_CLUSTER_NAME} ;
  patch_oap_refresh_rate_cp ${MP_CLUSTER_NAME} ;
  patch_jwt_token_expiration_mp ${MP_CLUSTER_NAME} ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  MP_OUTPUT_DIR=$(get_mp_output_dir) ;
  kubectl --context ${MP_CLUSTER_NAME} get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/mp-certs.pem ;
  kubectl --context ${MP_CLUSTER_NAME} get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/es-certs.pem ;
  kubectl --context ${MP_CLUSTER_NAME} get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${MP_OUTPUT_DIR}/xcp-central-ca-certs.pem ;

  expose_tsb_gui ${MP_CLUSTER_NAME} ;

  print_info "Finished installation of tsb demo management/control plane in cluster ${MP_CLUSTER_NAME}"
  exit 0
fi

if [[ ${ACTION} = "uninstall" ]]; then

  MP_CLUSTER_NAME=$(get_mp_name) ;
  print_info "Start removing installation of tsb demo management/control plane in cluster ${MP_CLUSTER_NAME}"

  # Put operators to sleep
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} scale deployment {} -n ${NS} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete deployment {} -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${MP_CLUSTER_NAME} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_NAME} delete --all jobs -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_NAME} delete --all statefulset -n ${NS} --timeout=10s --wait=false ;
    kubectl --context ${MP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} patch deployment {} -n ${NS} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --context ${MP_CLUSTER_NAME} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${MP_CLUSTER_NAME} delete namespace ${NS} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --context ${MP_CLUSTER_NAME} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_NAME} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_NAME} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --context ${MP_CLUSTER_NAME} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --context ${MP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --context ${MP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --context ${MP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${MP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${MP_CLUSTER_NAME} get namespace ${NS} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --context ${MP_CLUSTER_NAME} replace --raw /api/v1/namespaces/${NS}/finalize -f - ;
  done

  sleep 10 ;

  print_info "Finished removing installation of tsb demo management/control plane in cluster ${MP_CLUSTER_NAME}"
  exit 0
fi


if [[ ${ACTION} = "reset" ]]; then

  MP_CLUSTER_NAME=$(get_mp_name) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin ${MP_CLUSTER_NAME} tetrate ;

  # Remove all TSB configuration objects
  kubectl config use-context ${MP_CLUSTER_NAME} ;
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects
  kubectl --context ${MP_CLUSTER_NAME} get -A egressgateways.install.tetrate.io,ingressgateways.install.tetrate.io,tier1gateways.install.tetrate.io -o yaml \
   | kubectl --context ${MP_CLUSTER_NAME} delete -f - ;

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - install"
echo "  - uninstall"
echo "  - reset"
exit 1
