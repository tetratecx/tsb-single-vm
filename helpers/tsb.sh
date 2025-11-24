#!/usr/bin/env bash
#
# Helper functions for TSB
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

CLUSTER_WAIT_TIMEOUT=120;

# Login as admin into tsb
#   args:
#     (1) organization
#     (2) username
#     (3) password
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide tsb organization as 1st argument" && return 2 || local organization="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide password as 3rd argument" && return 2 || local password="${3}" ;

  expect <<DONE
  spawn tctl login --username "${username}" --password "${password}" --org "${organization}"
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Wait for cluster to be onboarded
#   args:
#     (1) onboarding cluster name
#     (2) timeout in seconds (optional, default 120 aka 2 minutes)
function wait_cluster_onboarded() {
  [[ -z "${1}" ]] && print_error "Please provide the onboarding cluster name as 1st argument" && return 2 \
    || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && local timeout=${CLUSTER_WAIT_TIMEOUT} || local timeout="${2}" ;
  local start_time; start_time=$(date +%s) ;

  echo -n "Wait for cluster '${cluster_name}' to be onboarded (timeout: ${timeout}s): " ;
  while :; do
    local status_json; status_json=$(tctl status cluster "${cluster_name}" -o json 2>/dev/null || \
      tctl x status cluster "${cluster_name}" -o json ) ;
    local current_status; current_status=$(echo "${status_json}" | jq -r '.spec.status') ;
    local current_message; current_message=$(echo "${status_json}" | jq -r '.spec.message') ;
    if [[ "${current_status}" == "READY" && "${current_message}" == "Cluster onboarded" ]]; then
      echo "DONE" ;
      echo "Cluster '${cluster_name}' is ready" ;
      return 0 ;
    fi
    local current_time; current_time=$(date +%s) ;
    if (( current_time - start_time >= timeout )); then
      echo "DONE" ;
      print_warning "Timeout reached. Current status of '${cluster_name}': ${current_status}, ${current_message}" ;
      print_warning "$(tctl status cluster "${cluster_name}" -o yaml)" ;
      return 1 ;
    fi
    sleep 5 ;
    echo -n "." ;
  done
}

# Wait for mulitple cluster to be onboarded
#   args:
#     (1) list of onboarding cluster names
function wait_clusters_onboarded {
  local clusters=("$@") ;
  for cluster in "${clusters[@]}"; do
    wait_cluster_onboarded "${cluster}" ;
  done
}

# Get TSB API Server public exposed ip address
#   args:
#     (1) cluster context
function get_tsb_api_ip {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local tsb_api_ip; tsb_api_ip=$(kubectl --context "${cluster_ctx}" get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  echo "${tsb_api_ip}" ;
}

# Get TSB API Server public exposed tcp port
#   args:
#     (1) cluster context
function get_tsb_api_port {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local tsb_api_port; tsb_api_port=$(kubectl --context "${cluster_ctx}" get svc -n tsb envoy --output jsonpath='{.spec.ports[?(@.name=="https-ingress")].port}') ;
  echo "${tsb_api_port}" ;
}

# Wait for the management plane deployments to become available
#   args:
#     (1) cluster context
#     (2) management plane namespace
# 
# kubectl get deploy -n tsb --sort-by=.metadata.creationTimestamp --no-headers -o custom-columns=":metadata.name" | tr '\n' ' '

# IGNORED: oap
MP_COMPONENTS=( "tsb-operator-management-plane" "xcp-operator-central" "kubegres-controller-manager" "central" "envoy" "iam" "mpc" "tsb" "n2ac" "otel-collector" "web" )

function wait_mp_ready {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide management plane namespace as 2nd argument" && return 2 || local mp_namespace="${2}" ;

  for tsb_deployment in "${MP_COMPONENTS[@]}" ; do
    while ! kubectl --context "${cluster_ctx}" get deployment -n "${mp_namespace}" "${tsb_deployment}" &>/dev/null; do sleep 1; done ;
    echo "Waiting for deployment '${mp_namespace}/${tsb_deployment}' to become available in cluster '${cluster_ctx}'" ;
    kubectl --context "${cluster_ctx}" wait deployment -n "${mp_namespace}" "${tsb_deployment}" --for condition=Available=True --timeout=600s ;
    echo "Deployment '${mp_namespace}/${tsb_deployment}' is available in cluster '${cluster_ctx}'" ;
  done
}

# Wait for the control plane deployments to become available
#   args:
#     (1) cluster context
#     (2) control plane namespace
# 
# kubectl get deploy -n istio-system --sort-by=.metadata.creationTimestamp --no-headers -o custom-columns=":metadata.name" | tr '\n' ' '
#
function wait_cp_ready {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide control plane namespace as 2nd argument" && return 2 || local cp_namespace="${2}" ;

  for tsb_deployment in tsb-operator-control-plane istio-system-custom-metrics-apiserver onboarding-operator otel-collector wasmfetcher xcp-operator-edge istio-operator-prod-stable edge istio-operator istiod-prod-stable istiod vmgateway oap-deployment ; do
    while ! kubectl --context "${cluster_ctx}" get deployment -n "${cp_namespace}" "${tsb_deployment}" &>/dev/null; do sleep 1; done ;
    echo "Waiting for deployment '${cp_namespace}/${tsb_deployment}' to become available in cluster '${cluster_ctx}'" ;
    kubectl --context "${cluster_ctx}" wait deployment -n "${cp_namespace}" "${tsb_deployment}" --for condition=Available=True --timeout=600s ;
    echo "Deployment '${cp_namespace}/${tsb_deployment}' is available in cluster '${cluster_ctx}'" ;
  done
}

# Patch affinity rules of management plane (demo only!)
#   args:
#     (1) cluster context
function patch_remove_affinity_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  while ! kubectl --context "${cluster_ctx}" -n tsb get managementplane managementplane &>/dev/null; do
    sleep 0.1 ;
  done
  while ! kubectl --context "${cluster_ctx}" get -n tsb managementplane managementplane -ojsonpath='{.spec.components.apiServer.kubeSpec.deployment.affinity.podAntiAffinity}' --allow-missing-template-keys=false &>/dev/null  ; do
    sleep 0.1 ;
  done

  for tsb_component in apiServer collector frontEnvoy iamServer mpc ngac oap webUI ; do
    kubectl --context "${cluster_ctx}" patch managementplane managementplane -n tsb --type=json \
      -p="[{'op': 'replace', 'path': '/spec/components/${tsb_component}/kubeSpec/deployment/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution/0/labelSelector/matchExpressions/0/key', 'value': 'platform.tsb.tetrate.io/demo-dummy'}]" \
      &>/dev/null ;
  done
  echo "Managementplane sucessfully patched for affinity removal" ;
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}' ;
  kubectl --context "${cluster_ctx}" -n tsb patch managementplanes managementplane --type merge --patch "${oap_patch}" ;
  echo "Managementplane sucessfully patched for oap refresh rate" ;
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) cluster context
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}' ;
  kubectl --context "${cluster_ctx}" -n istio-system patch controlplanes controlplane --type merge --patch "${oap_patch}" ;
  echo "Controlplane sucessfully patched for oap refresh rate" ;
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) cluster context
function patch_jwt_token_expiration_mp {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local token_patch='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}' ;
  kubectl --context "${cluster_ctx}" -n tsb patch managementplanes managementplane --type merge --patch "${token_patch}" ;
  echo "Managementplane sucessfully patched for jwt token expiration" ;
}

# Expose tsb gui with kubectl port-forward
#   args:
#     (1) cluster context
function expose_tsb_gui {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local tsb_api_ip; tsb_api_ip=$(get_tsb_api_ip "${cluster_ctx}") ;
  local tsb_api_port; tsb_api_port=$(get_tsb_api_port "${cluster_ctx}") ;
  local tsb_api_host_port=8443 ; # Currently hardcoded in the tsb gui deployment

  sudo tee /etc/systemd/system/tsb-gui.service << EOF
[Unit]
Description=TSB GUI Exposure

[Service]
ExecStart=$(which kubectl) --kubeconfig ${HOME}/.kube/config --context "${cluster_ctx}" port-forward -n tsb service/envoy ${tsb_api_host_port}:${tsb_api_port} --address 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;

  echo "The tsb gui should be available at some of the following urls:" ;
  echo " - local host: https://127.0.0.1:${tsb_api_host_port}" ;
  echo " - docker network: https://${tsb_api_ip}:${tsb_api_port}" ;
  echo " - public ip: https://$(curl -s ifconfig.me):${tsb_api_host_port}" ;
}

# Dump TSB error logs
#   args:
#     (1) cluster context
dump_tsb_error_logs() {
  [[ -z "${1}" ]] && print_error "Please provide cluster context as 1st argument" && return 2 || local cluster_ctx="${1}" ;

  local namespaces=("istio-system" "tsb") ;
  for ns in "${namespaces[@]}"; do
    local pods; pods=$(kubectl --context "${cluster_ctx}" get pods -n "${ns}" -o jsonpath='{.items[*].metadata.name}') ;
    for pod in ${pods}; do
      local error_logs; error_logs=$(kubectl --context "${cluster_ctx}" logs "${pod}" -n "$ns" | grep -E '( |\t)error( |\t)') ;
      if [[ ! -z "${error_logs}" ]]; then
        echo "========== Dumping error logs from pod '${pod}' in namespace '${ns}' in cluster '${cluster_ctx}' ==========" ;
        echo "${error_logs}" ;
      fi
    done
  done
}