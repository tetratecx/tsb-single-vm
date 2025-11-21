#!/usr/bin/env bash

BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

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
  echo "  --install: install tsb control and data plane" ;
  echo "  --uninstall: uninstall tsb control and data plane" ;
}

# This function installs the tsb control and data plane using tctl.
#
function install_tctl() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local install_repo_url; install_repo_url=$(get_local_registry_endpoint) ;
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;
  local mp_output_dir; mp_output_dir=$(get_mp_output_dir) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;


  cp_count=$(get_cp_count) ;
  cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_cr_template_file=$(get_cp_cr_template_file_by_index ${cp_index}) ;
    cp_output_dir=$(get_cp_output_dir ${cp_index}) ;
    print_info "Start installation of tsb control plane in cluster ${cp_cluster_name}" ;

    # Generate a service account private key for the active cluster
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
    if [ ! -f "${cp_output_dir}/cluster-service-account.jwk" ]; then
      tctl install cluster-service-account --cluster "${cp_cluster_name}" > "${cp_output_dir}/cluster-service-account.jwk" ;
    fi

    # Create control plane secrets
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
    kubectl config use-context "${mp_cluster_name}" ;
    tctl install manifest control-plane-secrets \
      --cluster "${cp_cluster_name}" \
      --cluster-service-account="$(cat ${cp_output_dir}/cluster-service-account.jwk)" \
      --elastic-ca-certificate="$(cat ${mp_output_dir}/es-certs.pem)" \
      --management-plane-ca-certificate="$(cat ${mp_output_dir}/mp-certs.pem)" \
      --xcp-certs="$(cat ${mp_output_dir}/xcp-central-ca-certs.pem)" \
      > "${cp_output_dir}/controlplane-secrets.yaml" ;

    # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
    TSB_API_SERVER_IP=$(get_tsb_api_ip "${mp_cluster_name}") ; export TSB_API_SERVER_IP ;
    TSB_API_SERVER_PORT=$(get_tsb_api_port "${mp_cluster_name}") ; export TSB_API_SERVER_PORT ;
    export TSB_INSTALL_REPO_URL=${install_repo_url} ;
    envsubst < "${cp_cr_template_file}" > "${cp_output_dir}/controlplane.yaml" ;
    # TSB MP demo install xcp central cert name is demo.tsb.tetrate.io 
    sed -i 's/central\.xcp\.tetrate\.io/demo.tsb.tetrate.io/g' "${cp_output_dir}/controlplane.yaml" ;

    # bootstrap cluster with self signed certificate that share a common root certificate
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
    generate_istio_cert "${certs_base_dir}" "${cp_cluster_name}" ;
    if ! kubectl --context "${cp_cluster_name}" get ns istio-system &>/dev/null; then
      kubectl --context "${cp_cluster_name}" create ns istio-system ;
    fi
    if ! kubectl --context "${cp_cluster_name}" -n istio-system get secret cacerts &>/dev/null; then
      kubectl --context "${cp_cluster_name}" create secret generic cacerts -n istio-system \
        --from-file="${certs_base_dir}/${cp_cluster_name}/ca-cert.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/ca-key.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/root-cert.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/cert-chain.pem" ;
    fi

    # Deploy operators
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
    login_tsb_admin "tetrate" "admin" "admin" ;
    tctl install manifest cluster-operators --registry ${install_repo_url} > ${cp_output_dir}/clusteroperators.yaml ;

    # Applying operator, secrets and control plane configuration
    kubectl --context "${cp_cluster_name}" apply -f "${cp_output_dir}/clusteroperators.yaml" ;
    kubectl --context "${cp_cluster_name}" wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=120s ;
    kubectl --context "${cp_cluster_name}" apply -f "${cp_output_dir}/controlplane-secrets.yaml" ;
    while ! kubectl --context "${cp_cluster_name}" get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
    until kubectl --context "${cp_cluster_name}" apply -f "${cp_output_dir}/controlplane.yaml" &>/dev/null; do
      sleep 5 ;
    done
    print_info "Bootstrapped installation of tsb control plane in cluster ${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done


  cp_count=$(get_cp_count) ;
  cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    print_info "Wait installation of tsb control plane in cluster '${cp_cluster_name}' to finish" ;

    # Wait for the control and data plane to become available
    kubectl --context "${cp_cluster_name}" wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
#    kubectl --context "${cp_cluster_name}" wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
    while ! kubectl --context "${cp_cluster_name}" get deployment -n istio-system edge &>/dev/null; do sleep 5; done ;
    kubectl --context "${cp_cluster_name}" wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
    kubectl --context "${cp_cluster_name}" get pods -A ;

    # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
    patch_oap_refresh_rate_cp "${cp_cluster_name}" ;

    print_info "Finished installation of tsb control plane in cluster ${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done
}

# This function installs the tsb control and data plane using tctl.
#
function uninstall_tctl() {

  local cp_count; cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    print_info "Start removing installation of tsb control plane in cluster ${cp_cluster_name}" ;

    # Put operators to sleep
    for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context "${cp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context "${cp_cluster_name}" scale deployment {} -n ${namespace} --replicas=0 ;
    done

    sleep 5 ;

    # Clean up namespace specific resources
    for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context "${cp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context "${cp_cluster_name}" delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
      sleep 5 ;
      kubectl --context "${cp_cluster_name}" delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
      kubectl --context "${cp_cluster_name}" delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
      kubectl --context "${cp_cluster_name}" delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
      kubectl --context "${cp_cluster_name}" get deployments -n ${namespace} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context "${cp_cluster_name}" patch deployment {} -n ${namespace} --type json \
        --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
      kubectl --context "${cp_cluster_name}" delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
      sleep 5 ;
      kubectl --context "${cp_cluster_name}" delete namespace ${namespace} --timeout=10s --wait=false ;
    done 

    # Clean up cluster wide resources
    kubectl --context "${cp_cluster_name}" get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
    kubectl --context "${cp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete crd {} --timeout=10s --wait=false ;
    kubectl --context "${cp_cluster_name}" get validatingwebhookconfigurations -o custom-columns=:metadata.name \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
    kubectl --context "${cp_cluster_name}" get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete clusterrole {} --timeout=10s --wait=false ;
    kubectl --context "${cp_cluster_name}" get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete clusterrolebinding {} --timeout=10s --wait=false ;

    # Cleanup custom resource definitions
    kubectl --context "${cp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete crd {} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context "${cp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    sleep 5 ;
    kubectl --context "${cp_cluster_name}" get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context "${cp_cluster_name}" delete crd {} --timeout=10s --wait=false ;

    # Clean up pending finalizer namespaces
    for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context "${cp_cluster_name}" get namespace ${namespace} -o json \
        | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
        | kubectl --context "${cp_cluster_name}" replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
    done

    sleep 10 ;

    print_info "Finished removing installation of tsb control plane in cluster ${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done
}

# This function installs the tsb control plane using helm.
#
function install_helm {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local install_repo_url; install_repo_url=$(get_local_registry_endpoint) ;
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;
  local mp_output_dir; mp_output_dir=$(get_mp_output_dir) ;
  local tsb_version; tsb_version=$(get_tsb_version) ;

  if ! helm repo list | grep -q 'tetrate-tsb-charts'; then
    helm repo add tetrate-tsb-charts "${TSB_HELM_REPO}" ;
  fi
  helm repo update tetrate-tsb-charts ;

  cp_count=$(get_cp_count) ;
  cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_helm_template_file=$(get_cp_helm_template_file_by_index ${cp_index}) ;
    cp_output_dir=$(get_cp_output_dir ${cp_index}) ;
    print_info "Start installation of tsb control plane in cluster ${cp_cluster_name}" ;

    # Generate a service account private key for the mgmt cp cluster
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
    tctl install cluster-service-account --cluster "${cp_cluster_name}" > "${cp_output_dir}/cluster-service-account.jwk" ;

    TSB_API_SERVER_IP=$(get_tsb_api_ip "${mp_cluster_name}") ; export TSB_API_SERVER_IP ;
    TSB_API_SERVER_PORT=$(get_tsb_api_port "${mp_cluster_name}") ; export TSB_API_SERVER_PORT ;
    TSB_INSTALL_REPO_URL="${install_repo_url}" ; export TSB_INSTALL_REPO_URL ;
    export TSB_VERSION="${tsb_version}" ;
    envsubst < "${cp_helm_template_file}" > "${cp_output_dir}/cp-helm-values.yaml" ;

    # bootstrap cluster with self signed certificate that share a common root certificate
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
    generate_istio_cert "${certs_base_dir}" "${cp_cluster_name}" ;
    if ! kubectl --context "${cp_cluster_name}" get ns istio-system &>/dev/null; then
      kubectl --context "${cp_cluster_name}" create ns istio-system ;
    fi
    if ! kubectl --context "${cp_cluster_name}" -n istio-system get secret cacerts &>/dev/null; then
      kubectl --context "${cp_cluster_name}" create secret generic cacerts -n istio-system \
        --from-file="${certs_base_dir}/${cp_cluster_name}/ca-cert.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/ca-key.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/root-cert.pem" \
        --from-file="${certs_base_dir}/${cp_cluster_name}/cert-chain.pem" ;
    fi

    # install tsb control plane using helm
    helm upgrade --install tsb-cp "${CP_HELM_CHART}" \
      --create-namespace \
      --kube-context "${cp_cluster_name}" \
      --namespace "istio-system" \
      --set-file secrets.elasticsearch.cacert="${mp_output_dir}/tsb-ca-cert.pem" \
      --set-file secrets.tsb.cacert="${mp_output_dir}/tsb-ca-cert.pem" \
      --set-file secrets.xcp.rootca="${mp_output_dir}/tsb-ca-cert.pem" \
      --set-file secrets.clusterServiceAccount.JWK="${cp_output_dir}/cluster-service-account.jwk" \
      --values "${cp_output_dir}/cp-helm-values.yaml" \
      --version "${TSB_VERSION}";
      # --wait ;
    cp_index=$((cp_index+1)) ;
  done

  cp_count=$(get_cp_count) ;
  cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    # print_info "Waiting for tsb control plane deployments to become available" ;
    # wait_cp_ready "${cp_cluster_name}" "istio-system" ;

    kubectl --context "${cp_cluster_name}" get pods -A ;
    print_info "Finished installation of tsb control plane in cluster ${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done
}

# This function uninstalls the tsb control plane using helm.
#
function uninstall_helm {
  local mp_cluster_name; mp_cluster_name=$(get_mp_name) ;

  cp_count=$(get_cp_count) ;
  cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    echo "Uninstalling helm chart for tsb management/control plane in cluster ${cp_cluster_name}" ;
    helm uninstall tsb-cp \
      --kube-context "${cp_cluster_name}" \
      --namespace "istio-system" ;
    kubectl --context "${cp_cluster_name}" delete namespace "istio-system" ;
    cp_index=$((cp_index+1)) ;
  done

  print_info "Uninstalled helm chart for tsb management/control plane" ;
}

# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --install)
    if [[ "$(get_tsb_install_method)" == "helm" ]]; then
      print_stage "Going to install tsb control and data plane using helm" ;
      start_time=$(date +%s); install_helm; elapsed_time=$(( $(date +%s) - start_time )) ;
      print_stage "Installed tsb control and data plane using helm in ${elapsed_time} seconds" ;
    elif [[ "$(get_tsb_install_method)" == "tctl" ]]; then
      print_stage "Going to install tsb control and data plane using tctl" ;
      start_time=$(date +%s); install_tctl; elapsed_time=$(( $(date +%s) - start_time )) ;
      print_stage "Installed tsb control and data plane using tctl in ${elapsed_time} seconds" ;
    else
      print_error "Invalid tsb install method. Choose 'helm' or 'tctl'" ;
      help ;
    fi
    ;;
  --uninstall)
    if [[ "$(get_tsb_install_method)" == "helm" ]]; then
      print_stage "Going to uninstall tsb control and data plane using helm" ;
      start_time=$(date +%s); uninstall_helm; elapsed_time=$(( $(date +%s) - start_time )) ;
      print_stage "Uninstalled tsb control and data plane using helm in ${elapsed_time} seconds" ;
    elif [[ "$(get_tsb_install_method)" == "tctl" ]]; then
      print_stage "Going to uninstall tsb control and data plane using tctl" ;
      start_time=$(date +%s); uninstall_tctl; elapsed_time=$(( $(date +%s) - start_time )) ;
      print_stage "Uninstalled tsb control and data plane using tctl in ${elapsed_time} seconds" ;
    else
      print_error "Invalid tsb install method. Choose 'helm' or 'tctl'" ;
      help ;
    fi
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac
