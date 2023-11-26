#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/certs.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh" ;

ACTION=${1} ;

TSB_HELM_REPO="https://charts.dl.tetrate.io/public/helm/charts" ;
MP_HELM_CHART="tetrate-tsb-charts/managementplane" ;
CP_HELM_CHART="tetrate-tsb-charts/controlplane" ;


# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --install: install tsb management plane" ;
  echo "  --uninstall: uninstall tsb management plane" ;
  echo "  --reset: reset all tsb configuration objects" ;
}

# This function installs the tsb management plane using tctl.
#
function install_tctl() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local install_repo_url; install_repo_url=$(get_local_registry_endpoint) ;
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;
  local mp_output_dir; mp_output_dir=$(get_mp_output_dir) ;

  print_info "Start installation of tsb demo management/control plane in cluster ${mp_cluster_name}" ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  generate_istio_cert "${certs_base_dir}" "${mp_cluster_name}" ;
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
  
  # start patching managementplane CR asynchronously
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
  # Apply JWT token expiration patch
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

  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;
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

# This function installs the tsb management and control plane using helm.
#
function install_helm {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local cp_helm_template_file; cp_helm_template_file=$(get_mp_cp_helm_template_file) ;
  local install_repo_url; install_repo_url=$(get_local_registry_endpoint) ;
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;
  local mp_helm_template_file; mp_helm_template_file=$(get_mp_mp_helm_template_file) ;
  local mp_output_dir; mp_output_dir=$(get_mp_output_dir) ;
  local tsb_version; tsb_version=$(get_tsb_version) ;

  if ! helm repo list | grep -q 'tetrate-tsb-charts'; then
    helm repo add tetrate-tsb-charts "${TSB_HELM_REPO}" ;
  fi
  helm repo update tetrate-tsb-charts ;

  export TSB_API_SERVER_PORT=8443 ;
  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  export TSB_VERSION="${tsb_version}" ;
  envsubst < "${mp_helm_template_file}" > "${mp_output_dir}/mp-helm-values.yaml" ;

  # start patching managementplane CR asynchronously
  patch_remove_affinity_mp "${mp_cluster_name}" &

  # install tsb management plane using helm
  helm upgrade --install tsb-mp "${MP_HELM_CHART}" \
    --create-namespace \
    --kube-context "${mp_cluster_name}" \
    --namespace "tsb" \
    --values "${mp_output_dir}/mp-helm-values.yaml" \
    --wait ;

  # Wait for the management plane deployments to become available
  print_info "Waiting for tsb management plane deployments to become available" ;
  wait_mp_ready "${mp_cluster_name}" "tsb" ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp "${mp_cluster_name}" ;
  # Apply JWT token expiration patch
  patch_jwt_token_expiration_mp "${mp_cluster_name}" ;

  # Configure tctl
  tctl config clusters set "${mp_cluster_name}" --tls-insecure --bridge-address "$(get_tsb_api_ip ${mp_cluster_name}):$(get_tsb_api_port ${mp_cluster_name})" ;
  tctl config users set tsb-admin --username admin --password admin --org tetrate ;
  tctl config profiles set tsb-profile --cluster "${mp_cluster_name}" --username tsb-admin ;
  tctl config profiles set-current tsb-profile ;

  # Extract the tsb ca certificate from the mgmt cluster
  kubectl --context "${mp_cluster_name}" get -n tsb secret tsb-certs -o jsonpath="{.data.ca\.crt}" | base64 --decode > "${mp_output_dir}/tsb-ca-cert.pem"

  # Generate a service account private key for the mgmt cp cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  if [ ! -f "${mp_output_dir}/cluster-service-account.jwk" ]; then
    tctl install cluster-service-account --cluster "${mp_cluster_name}" > "${mp_output_dir}/cluster-service-account.jwk"
  fi

  TSB_API_SERVER_IP=$(get_tsb_api_ip "${mp_cluster_name}") ; export TSB_API_SERVER_IP ;
  TSB_API_SERVER_PORT=$(get_tsb_api_port "${mp_cluster_name}") ; export TSB_API_SERVER_PORT ;
  export TSB_INSTALL_REPO_URL="${install_repo_url}" ;
  export TSB_VERSION="${tsb_version}" ;
  envsubst < "${cp_helm_template_file}" > "${mp_output_dir}/cp-helm-values.yaml" ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  generate_istio_cert "${certs_base_dir}" "${mp_cluster_name}" ;
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

  # install tsb control plane using helm
  helm upgrade --install tsb-cp "${CP_HELM_CHART}" \
    --create-namespace \
    --kube-context "${mp_cluster_name}" \
    --namespace "istio-system" \
    --set-file secrets.elasticsearch.cacert="${mp_output_dir}/tsb-ca-cert.pem" \
    --set-file secrets.tsb.cacert="${mp_output_dir}/tsb-ca-cert.pem" \
    --set-file secrets.xcp.rootca="${mp_output_dir}/tsb-ca-cert.pem" \
    --set-file secrets.clusterServiceAccount.JWK="${mp_output_dir}/cluster-service-account.jwk" \
    --values "${mp_output_dir}/cp-helm-values.yaml" \
    --wait ;

  print_info "Waiting for tsb control plane deployments to become available" ;
  wait_cp_ready "${mp_cluster_name}" "istio-system" ;

  # Expose tsb gui with kubectl port-forward
  expose_tsb_gui "${mp_cluster_name}" ;

  kubectl --context "${mp_cluster_name}" get pods -A ;
  print_info "Finished installation of tsb management/control plane in cluster ${mp_cluster_name}" ;
}

# This function uninstalls the tsb management and control plane using helm.
#
function uninstall_helm {
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;

  helm uninstall tsb-cp \
    --kube-context "${mp_cluster_name}" \
    --namespace "istio-system" ;
  kubectl --context "${mp_cluster_name}" delete namespace "istio-system" ;

  helm uninstall tsb-mp \
    --kube-context "${mp_cluster_name}" \
    --namespace "tsb" ;
  kubectl --context "${mp_cluster_name}" delete namespace "tsb" ;

  print_info "Uninstalled helm chart for tsb management/control plane" ;
}

# This function removes all tsb configuration objects.
#
function reset() {

  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Remove all TSB configuration objects
  kubectl config use-context "${mp_cluster_name}" ;
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects
  kubectl --context "${mp_cluster_name}" get -A egressgateways.install.tetrate.io,ingressgateways.install.tetrate.io,tier1gateways.install.tetrate.io -o yaml \
    | kubectl --context "${mp_cluster_name}" delete -f - ;

  print_info "Removed all tsb configuration objects" ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --install)
    if [[ "$(get_tsb_install_method)" == "helm" ]]; then
      print_stage "Going to install tsb management plane using helm" ;
      install_helm ;
    elif [[ "$(get_tsb_install_method)" == "tctl" ]]; then
      print_stage "Going to install tsb management plane using tctl" ;
      install_tctl ;
    else
      print_error "Invalid tsb install method. Choose 'helm' or 'tctl'" ;
      help ;
    fi
    ;;
  --uninstall)
    if [[ "$(get_tsb_install_method)" == "helm" ]]; then
      print_stage "Going to uninstall tsb management plane using helm" ;
      uninstall_helm ;
    elif [[ "$(get_tsb_install_method)" == "tctl" ]]; then
      print_stage "Going to uninstall tsb management plane using tctl" ;
      uninstall_tctl ;
    else
      print_error "Invalid tsb install method. Choose 'helm' or 'tctl'" ;
      help ;
    fi
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
