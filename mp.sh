#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

source "${BASE_DIR}/env.sh" "${BASE_DIR}" ;
source "${BASE_DIR}/certs.sh" "${BASE_DIR}" ;
source "${BASE_DIR}/helpers.sh" ;
source "${BASE_DIR}/tsb-helpers.sh" ;

ACTION=${1} ;


# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --install: install tsb management plane" ;
  echo "  --uninstall: uninstall tsb management plane" ;
  echo "  --reset: reset all tsb configuration objects" ;
}

# Patch affinity rules of management plane (demo only!)
#   args:
#     (1) cluster context
function patch_remove_affinity_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  while ! kubectl --context "${cluster_ctx}" -n tsb get managementplane managementplane &>/dev/null; do
    sleep 1 ;
  done
  for tsb_component in apiServer collector frontEnvoy iamServer mpc ngac oap webUI ; do
    kubectl patch managementplane managementplane -n tsb --type=json \
      -p="[{'op': 'replace', 'path': '/spec/components/${tsb_component}/kubeSpec/deployment/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution/0/labelSelector/matchExpressions/0/key', 'value': 'platform.tsb.tetrate.io/demo-dummy'}]" \
      &>/dev/null ;
  done
  echo "Managementplane tsb/managementplane sucessfully patched" ;
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}' ;
  kubectl --context "${cluster_ctx}" -n tsb patch managementplanes managementplane --type merge --patch "${oap_patch}" ;
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}' ;
  kubectl --context "${cluster_ctx}" -n istio-system patch controlplanes controlplane --type merge --patch "${oap_patch}" ;
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) cluster context
function patch_jwt_token_expiration_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local token_patch='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}' ;
  kubectl --context "${cluster_ctx}" -n tsb patch managementplanes managementplane --type merge --patch "${token_patch}" ;
}

# Expose tsb gui with kubectl port-forward
#   args:
#     (1) cluster context
function expose_tsb_gui {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local tsb_api_endpoint=$(kubectl --context "${cluster_ctx}" get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  sudo tee /etc/systemd/system/tsb-gui.service << EOF
[Unit]
Description=TSB GUI Exposure

[Service]
ExecStart=$(which kubectl) --kubeconfig ${HOME}/.kube/config --context "${cluster_ctx}" port-forward -n tsb service/envoy 8443:8443 --address 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;
  print_info "The tsb gui should be available at some of the following urls:" ;
  echo " - local host: https://127.0.0.1:8443" ;
  echo " - docker network: https://${tsb_api_endpoint}:8443" ;
  echo " - public ip: https://$(curl -s ifconfig.me):8443" ;
}

# This function installs the tsb management plane using tctl.
#
function install_tctl() {

  local certs_base_dir=$(get_certs_base_dir) ;
  local install_repo_url=$(get_install_repo_url) ;
  local mp_cluster_name=$(get_mp_name) ;
  local mp_output_dir=$(get_mp_output_dir) ;

  print_info "Start installation of tsb demo management/control plane in cluster ${mp_cluster_name}" ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  generate_istio_cert "${mp_cluster_name}" ;
  if ! kubectl --context "${mp_cluster_name}" get ns istio-system &>/dev/null; then
    kubectl --context "${mp_cluster_name}" create ns istio-system ;
  fi
  if ! kubectl --context "${mp_cluster_name}" -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context "${mp_cluster_name}" create secret generic cacerts -n istio-system \
      --from-file="${certs_base_dir}/${mp_cluster_name}/ca-cert.pem" \
      --from-file="${certs_base_dir}/${mp_cluster_name}/ca-key.pem" \
      --from-file="${certs_base_dir}/${mp_cluster_name}/root-cert.pem" \
      --from-file="${certs_base_dir}/${mp_cluster_name}/cert-chain.pem" ;
  fi
  
  # start patching deployments that depend on dockerhub asynchronously
  patch_remove_affinity_mp "${mp_cluster_name}" &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane!
  kubectl config use-context "${mp_cluster_name}" ;
  tctl install demo --cluster "${mp_cluster_name}" --registry "${install_repo_url}" --admin-password admin ;

  # Wait for the management, control and data plane to become available
  kubectl --context "${mp_cluster_name}" wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl --context "${mp_cluster_name}" wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --context "${mp_cluster_name}" wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --context "${mp_cluster_name}" get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl --context "${mp_cluster_name}" wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --context "${mp_cluster_name}" get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp "${mp_cluster_name}" ;
  patch_oap_refresh_rate_cp "${mp_cluster_name}" ;
  patch_jwt_token_expiration_mp "${mp_cluster_name}" ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  kubectl --context "${mp_cluster_name}" get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > "${mp_output_dir}/mp-certs.pem" ;
  kubectl --context "${mp_cluster_name}" get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > "${mp_output_dir}/es-certs.pem" ;
  kubectl --context "${mp_cluster_name}" get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > "${mp_output_dir}/xcp-central-ca-certs.pem" ;

  expose_tsb_gui "${mp_cluster_name}" ;

  print_info "Finished installation of tsb demo management/control plane in cluster ${mp_cluster_name}" ;
}

# This function uninstalls the tsb management plane using tctl.
#
function uninstall_tctl() {

  local mp_cluster_name=$(get_mp_name) ;
  print_info "Start removing installation of tsb demo management/control plane in cluster ${mp_cluster_name}" ;

  # Put operators to sleep
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context "${mp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context "${mp_cluster_name}" scale deployment {} -n ${namespace} --replicas=0 ;
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context "${mp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context "${mp_cluster_name}" delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context "${mp_cluster_name}" delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context "${mp_cluster_name}" delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context "${mp_cluster_name}" delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context "${mp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context "${mp_cluster_name}" patch deployment {} -n ${namespace} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --context "${mp_cluster_name}" delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context "${mp_cluster_name}" delete namespace ${namespace} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --context "${mp_cluster_name}" get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --context "${mp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete crd {} --timeout=10s --wait=false ;
  kubectl --context "${mp_cluster_name}" get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --context "${mp_cluster_name}" get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --context "${mp_cluster_name}" get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --context "${mp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --context "${mp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --context "${mp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context "${mp_cluster_name}" delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context "${mp_cluster_name}" get namespace ${namespace} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --context "${mp_cluster_name}" replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
  done

  sleep 10 ;

  print_info "Finished removing installation of tsb demo management/control plane in cluster ${mp_cluster_name}" ;
}

# This function removes all tsb configuration objects.
#
function reset() {

  local mp_cluster_name=$(get_mp_name) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Remove all TSB configuration objects
  kubectl config use-context "${mp_cluster_name}" ;
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects
  kubectl --context "${mp_cluster_name}" get -A egressgateways.install.tetrate.io,ingressgateways.install.tetrate.io,tier1gateways.install.tetrate.io -o yaml \
    | kubectl --context "${mp_cluster_name}" delete -f - ;

}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --install)
    print_stage "Going to install tsb management plane" ;
    install_tctl ;
    ;;
  --uninstall)
    print_stage "Going to uninstall tsb management plane" ;
    uninstall_tctl ;
    ;;
  --reset)
    print_stage "Going to reset all tsb configuration objects" ;
    reset ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac