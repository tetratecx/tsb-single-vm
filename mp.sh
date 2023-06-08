#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}

INSTALL_REPO_PW=$(get_install_repo_password) ;
INSTALL_REPO_URL=$(get_install_repo_url) ;
INSTALL_REPO_USER=$(get_install_repo_user) ;


# Patch affinity rules of management plane (demo only!)
#   args:
#     (1) cluster context
function patch_remove_affinity_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  while ! kubectl --context ${cluster_ctx} -n tsb get managementplane managementplane &>/dev/null; do
    sleep 1 ;
  done
  for tsb_component in apiServer collector frontEnvoy iamServer mpc ngac oap webUI ; do
    kubectl patch managementplane managementplane -n tsb --type=json \
      -p="[{'op': 'replace', 'path': '/spec/components/${tsb_component}/kubeSpec/deployment/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution/0/labelSelector/matchExpressions/0/key', 'value': 'platform.tsb.tetrate.io/demo-dummy'}]" \
      &>/dev/null;
  done
  echo "Managementplane tsb/managementplane sucessfully patched"
}

# Login as admin into tsb
#   args:
#     (1) cluster context
#     (2) tsb organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide tsb organization as 2nd argument" && return 2 || local tsb_org="${2}" ;

  kubectl config use-context ${cluster_ctx} ;
  expect <<DONE
  spawn tctl login --username admin --password admin --org ${tsb_org}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${cluster_ctx} -n tsb patch managementplanes managementplane --type merge --patch ${oap_patch}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${cluster_ctx} -n istio-system patch controlplanes controlplane --type merge --patch ${oap_patch}
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) cluster context
function patch_jwt_token_expiration_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local token_patch='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}'
  kubectl --context ${cluster_ctx} -n tsb patch managementplanes managementplane --type merge --patch ${token_patch}
}

# Expose tsb gui with kubectl port-forward
#   args:
#     (1) cluster context
function expose_tsb_gui {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local tsb_api_endpoint=$(kubectl --context ${cluster_ctx} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  sudo tee /etc/systemd/system/tsb-gui.service << EOF
[Unit]
Description=TSB GUI Exposure

[Service]
ExecStart=$(which kubectl) --kubeconfig ${HOME}/.kube/config --context ${cluster_ctx} port-forward -n tsb service/envoy 8443:8443 --address 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;
  print_info "The tsb gui should be available at some of the following urls:"
  echo " - local host: https://127.0.0.1:8443"
  echo " - docker network: https://${tsb_api_endpoint}:8443"
  echo " - public ip: https://$(curl -s ifconfig.me):8443"
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
  patch_remove_affinity_mp ${MP_CLUSTER_NAME} &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane!
  kubectl config use-context ${MP_CLUSTER_NAME} ;
  tctl install demo --cluster ${MP_CLUSTER_NAME} --registry ${INSTALL_REPO_URL} --admin-password admin ;

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
