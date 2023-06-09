#!/usr/bin/env bash

ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${ROOT_DIR}/tsb-helpers.sh

ACTION=${1}
INSTALL_REPO_URL=$(get_install_repo_url) ;

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${cluster_ctx} -n istio-system patch controlplanes controlplane --type merge --patch ${oap_patch}
}


if [[ ${ACTION} = "install" ]]; then

  MP_CLUSTER_NAME=$(get_mp_name) ;
  MP_OUTPUT_DIR=$(get_mp_output_dir) ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  export TSB_API_ENDPOINT=$(kubectl --context ${MP_CLUSTER_NAME} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  export TSB_INSTALL_REPO_URL=${INSTALL_REPO_URL}

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    CP_CONFIG_DIR=$(get_cp_config_dir ${CP_INDEX}) ;
    CP_OUTPUT_DIR=$(get_cp_output_dir ${CP_INDEX}) ;
    print_info "Start installation of tsb control plane in cluster ${CP_CLUSTER_NAME}"

    # Generate a service account private key for the active cluster
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
    kubectl config use-context ${MP_CLUSTER_NAME} ;
    tctl install cluster-service-account --cluster ${CP_CLUSTER_NAME} > ${CP_OUTPUT_DIR}/cluster-service-account.jwk ;

    # Create control plane secrets
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
    kubectl config use-context ${MP_CLUSTER_NAME} ;
    tctl install manifest control-plane-secrets \
      --cluster ${CP_CLUSTER_NAME} \
      --cluster-service-account="$(cat ${CP_OUTPUT_DIR}/cluster-service-account.jwk)" \
      --elastic-ca-certificate="$(cat ${MP_OUTPUT_DIR}/es-certs.pem)" \
      --management-plane-ca-certificate="$(cat ${MP_OUTPUT_DIR}/mp-certs.pem)" \
      --xcp-central-ca-bundle="$(cat ${MP_OUTPUT_DIR}/xcp-central-ca-certs.pem)" \
      > ${CP_OUTPUT_DIR}/controlplane-secrets.yaml ;

    # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
    envsubst < ${CP_CONFIG_DIR}/controlplane-template.yaml > ${CP_OUTPUT_DIR}/controlplane.yaml ;

    # bootstrap cluster with self signed certificate that share a common root certificate
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
    generate_istio_cert ${CP_CLUSTER_NAME} ;
    CERTS_BASE_DIR=$(get_certs_base_dir) ;

    if ! kubectl --context ${CP_CLUSTER_NAME} get ns istio-system &>/dev/null; then
      kubectl --context ${CP_CLUSTER_NAME} create ns istio-system ; 
    fi
    if ! kubectl --context ${CP_CLUSTER_NAME} -n istio-system get secret cacerts &>/dev/null; then
      kubectl --context ${CP_CLUSTER_NAME} create secret generic cacerts -n istio-system \
        --from-file=${CERTS_BASE_DIR}/${CP_CLUSTER_NAME}/ca-cert.pem \
        --from-file=${CERTS_BASE_DIR}/${CP_CLUSTER_NAME}/ca-key.pem \
        --from-file=${CERTS_BASE_DIR}/${CP_CLUSTER_NAME}/root-cert.pem \
        --from-file=${CERTS_BASE_DIR}/${CP_CLUSTER_NAME}/cert-chain.pem ;
    fi

    # Deploy operators
    #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
    login_tsb_admin tetrate ;
    tctl install manifest cluster-operators --registry ${INSTALL_REPO_URL} > ${CP_OUTPUT_DIR}/clusteroperators.yaml ;

    # Applying operator, secrets and control plane configuration
    kubectl --context ${CP_CLUSTER_NAME} apply -f ${CP_OUTPUT_DIR}/clusteroperators.yaml ;
    kubectl --context ${CP_CLUSTER_NAME} apply -f ${CP_OUTPUT_DIR}/controlplane-secrets.yaml ;
    while ! kubectl --context ${CP_CLUSTER_NAME} get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
    kubectl --context ${CP_CLUSTER_NAME} apply -f ${CP_OUTPUT_DIR}/controlplane.yaml ;
    print_info "Bootstrapped installation of tsb control plane in cluster ${CP_CLUSTER_NAME}"
    CP_INDEX=$((CP_INDEX+1))
  done


  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    print_info "Wait installation of tsb control plane in cluster ${CP_CLUSTER_NAME} to finish"

    # Wait for the control and data plane to become available
    kubectl --context ${CP_CLUSTER_NAME} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
    kubectl --context ${CP_CLUSTER_NAME} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
    while ! kubectl --context ${CP_CLUSTER_NAME} get deployment -n istio-system edge &>/dev/null; do sleep 5; done ;
    kubectl --context ${CP_CLUSTER_NAME} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
    kubectl --context ${CP_CLUSTER_NAME} get pods -A ;

    # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
    patch_oap_refresh_rate_cp ${CP_CLUSTER_NAME} ;

    print_info "Finished installation of tsb control plane in cluster ${CP_CLUSTER_NAME}"
    CP_INDEX=$((CP_INDEX+1))
  done

  exit 0
fi

if [[ ${ACTION} = "uninstall" ]]; then

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    print_info "Start removing installation of tsb control plane in cluster ${CP_CLUSTER_NAME}"

    # Put operators to sleep
    for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context ${CP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} scale deployment {} -n ${NS} --replicas=0 ; 
    done

    sleep 5 ;

    # Clean up namespace specific resources
    for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context ${CP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete deployment {} -n ${NS} --timeout=10s --wait=false ;
      sleep 5 ;
      kubectl --context ${CP_CLUSTER_NAME} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
      kubectl --context ${CP_CLUSTER_NAME} delete --all jobs -n ${NS} --timeout=10s --wait=false ;
      kubectl --context ${CP_CLUSTER_NAME} delete --all statefulset -n ${NS} --timeout=10s --wait=false ;
      kubectl --context ${CP_CLUSTER_NAME} get deployments -n ${NS} -o custom-columns=:metadata.name \
        | grep operator | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} patch deployment {} -n ${NS} --type json \
        --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
      kubectl --context ${CP_CLUSTER_NAME} delete --all deployments -n ${NS} --timeout=10s --wait=false ;
      sleep 5 ;
      kubectl --context ${CP_CLUSTER_NAME} delete namespace ${NS} --timeout=10s --wait=false ;
    done 

    # Clean up cluster wide resources
    kubectl --context ${CP_CLUSTER_NAME} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
    kubectl --context ${CP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;
    kubectl --context ${CP_CLUSTER_NAME} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
    kubectl --context ${CP_CLUSTER_NAME} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete clusterrole {} --timeout=10s --wait=false ;
    kubectl --context ${CP_CLUSTER_NAME} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete clusterrolebinding {} --timeout=10s --wait=false ;

    # Cleanup custom resource definitions
    kubectl --context ${CP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${CP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    sleep 5 ;
    kubectl --context ${CP_CLUSTER_NAME} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
      | xargs -I {} kubectl --context ${CP_CLUSTER_NAME} delete crd {} --timeout=10s --wait=false ;

    # Clean up pending finalizer namespaces
    for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
      kubectl --context ${CP_CLUSTER_NAME} get namespace ${NS} -o json \
        | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
        | kubectl --context ${CP_CLUSTER_NAME} replace --raw /api/v1/namespaces/${NS}/finalize -f - ;
    done

    sleep 10 ;

    print_info "Finished removing installation of tsb control plane in cluster ${CP_CLUSTER_NAME}"
    CP_INDEX=$((CP_INDEX+1))
  done

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - install"
echo "  - uninstall"
exit 1
