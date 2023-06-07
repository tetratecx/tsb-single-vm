# Helper functions to start, stop and delete local kubernetes cluster.
# Supported providers include:
#   - k3s from rancher
#   - kind
#   - minikube
#

# MetalLB original deployment yaml files
#  - https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
#  - https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
# Patched: removed PodSecurityPolicy (depricated)
METALLB_INSTALL_YAML=addons/k8s/metallb/resources/metallb-0.12.1.yaml

# MetalLB configmap configuration ready for envsubst
METALLB_POOLCONFIG_YAML=addons/k8s/metallb/config/metallb-poolconfig.yaml

# Metrics-Server original deployment yaml files
#  - https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.6.3/components.yaml
# Patched: added --kubelet-insecure-tls to metrics-server container command
METRICS_SERVER_INSTALL_YAML=addons/k8s/metrics-server/resources/metrics-server-0.6.3.yaml

# Docker and metallb ip addressing defaults
K8S_LOCAL_DOCKER_SUBNET_START="${K8S_LOCAL_DOCKER_SUBNET_START:-192.168.49.0/24}"
K8S_LOCAL_METALLB_STARTIP="${K8S_LOCAL_METALLB_STARTIP:-100}"
K8S_LOCAL_METALLB_STOPIP="${K8S_LOCAL_METALLB_STOPIP:-199}"

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

# Print info messages
#   args:
#     (1) message
function print_info {
  echo -e "${GREENB_COLOR}${1}${END_COLOR}" ;
}

# Print error messages
#   args:
#     (1) message
function print_error {
  echo -e "${REDB_COLOR}${1}${END_COLOR}" ;
}

# Helper function to do some prerequisite verifications
#   args:
#     (1) local kubernetes provider
function precheck {
  [[ -z "${1}" ]] && print_error "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;

  # Check if docker is installed
  if $(command -v docker &> /dev/null) ; then
    if ! $(docker ps &> /dev/null) ; then
      print_error "Cannot execute 'docker ps' without errors. Do you have the proper user permissions?" ;
      exit 1 ;
    fi
  else
    print_error "Executable 'docker' could not be found, please install this on your local system first" ;
    exit 1 ;
  fi

  # Check if a valid provider is configured and binary installed if needed
  case ${k8s_provider} in
    "k3s")
      if $(command -v k3d &> /dev/null) ; then true ; else
        print_error "? Executable 'k3d' for provider '${k8s_provider}' could not be found, please install this on your local system first" ;
        exit 2 ;
      fi
      ;;
    "kind")
      if $(command -v kind &> /dev/null) ; then true ; else
        print_error "? Executable 'kind' for provider '${k8s_provider}' could not be found, please install this on your local system first" ;
        exit 2 ;
      fi
      ;;
    "minikube")
      if $(command -v minikube &> /dev/null) ; then true ; else
        print_error "? Executable 'minikube' for provider '${k8s_provider}' could not be found, please install this on your local system first" ;
        exit 2 ;
      fi
      ;;
    *)
      print_error "Unknown local kubernetes provider '${k8s_provider}', quiting..." ;
      exit 2 ;
      ;;
  esac
}

# Get the local kubernetes provider type based on a given/configured kubectl context
#   args:
#     (1) kubectl context name
#   returns:
#     - prints provider string "k3d", "kind" or "minikube" with return value 0 if success
#     - prints string "unknown" with return value 1 if provider unknown based on context name
#     - prints string "notfound" with return value 1 if kubectl context does not exist
function get_provider_type_by_kubectl_context {
  [[ -z "${1}" ]] && echo "Please provide kubectl context name as 1st argument" && return 2 || local context_name="${1}" ;
  
  if output=$(kubectl config get-contexts ${context_name} --no-headers 2>/dev/null) ; then
    case ${output} in
      *"k3d"*)
        echo "k3s" ;
        return 0 ;
        ;;
      *"kind"*)
        echo "kind" ;
        return 0 ;
        ;;
      *"${context_name}"*)
        echo "minikube" ;
        return 0 ;
        ;;
      *)
        echo "unknown" ;
        return 1 ;
        ;;
    esac
  else
    echo "notfound" ;
    return 1 ;
  fi
}

# Get the local kubernetes provider type based on a given docker container
#   args:
#     (1) docker container name
#   returns:
#     - prints provider string "k3d", "kind" or "minikube" with return value 0 if success
#     - prints string "unknown" with return value 1 if provider unknown based on container name
#     - prints string "notfound" with return value 1 if container with this name does not exist
function get_provider_type_by_container_name {
  [[ -z "${1}" ]] && echo "Please provide docker container name as 1st argument" && return 2 || local container_name="${1}" ;
  
  if output=$(docker inspect ${container_name} -f '{{.Config.Image}}' 2>/dev/null) ; then
    case ${output} in
      *"k3s"*)
        echo "k3s" ;
        return 0 ;
        ;;
      *"kind"*)
        echo "kind" ;
        return 0 ;
        ;;
      *"kicbase"*)
        echo "minikube" ;
        return 0 ;
        ;;
      *)
        echo "unknown" ;
        return 1 ;
        ;;
    esac
  else
    echo "notfound" ;
    return 1 ;
  fi
}

# Check if a certain subnet is already in use
#   args:
#     (1) docker network subnet
#   return value:
#     0 : used
#     1 : not used
function is_docker_subnet_used {
  [[ -z "${1}" ]] && echo "Please provide network subnet as 1st argument" && return 2 || local subnet="${1}" ;
  docker network ls | tail -n +2 | awk '{ print $2 }' | \
    xargs -I {} -- docker network inspect {} --format '{{ if .IPAM.Config }}{{(index .IPAM.Config 0).Subnet}}{{ end }}' | \
    awk NF | grep ${subnet} &>/dev/null ;
}

# Get a docker subnet that is still free
function get_docker_subnet_free {
  local start=$(echo ${K8S_LOCAL_DOCKER_SUBNET_START} |  awk -F '.' '{ print $3;}') ;
  for i in $(seq ${start} 254) ; do
    local check_subnet=$(echo ${K8S_LOCAL_DOCKER_SUBNET_START} |  awk -F '.' "{ print \$1\".\"\$2\".\"${i}\".\"\$4;}") ;
    if ! $(is_docker_subnet_used "${check_subnet}") ; then
      echo "${check_subnet}" ;
      return
    fi
  done
}

# Get a docker container ip address
#   args:
#     (1) container name
#     (2) docker network name
function get_docker_container_ip {
  [[ -z "${1}" ]] && echo "Please provide container name as 1st argument" && return 2 || local container_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide network name as 2nd argument" && return 2 || local network_name="${2}" ;
  docker container inspect --format "{{(index .NetworkSettings.Networks \"${network_name}\").IPAddress}}" "${container_name}" ;
}

# Get kubernetes cluster apiserver address
#   args:
#     (1) cluster name
#     (2) docker network name
function get_apiserver_url {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide docker network name as 2nd argument" && return 2 || local network_name="${2}" ;
  local kubeapi_ip=$(get_docker_container_ip "${cluster_name}" "${network_name}") ;
  echo "https://${kubeapi_ip}:6443" ;
}

# Get kubernetes cluster apiserver address
#   args:
#     (1) cluster name
#     (2) docker network name
function deploy_metallb {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide docker network name as 2nd argument" && return 2 || local network_name="${2}" ;

  local network_subnet=$(docker network inspect --format '{{ if .IPAM.Config }}{{(index .IPAM.Config 0).Subnet}}{{ end }}' ${network_name}) ;
  local metallb_startip=$(echo ${network_subnet} |  awk -F '.' "{ print \$1\".\"\$2\".\"\$3\".\"${K8S_LOCAL_METALLB_STARTIP};}") ;
  local metallb_stopip=$(echo ${network_subnet} |  awk -F '.' "{ print \$1\".\"\$2\".\"\$3\".\"${K8S_LOCAL_METALLB_STOPIP};}") ;
  
  echo "Deploying and configuring metallb in cluster '${cluster_name}' with startip '${metallb_startip}' and endip '${metallb_stopip}'" ;
  kubectl --context ${cluster_name} apply -f ${METALLB_INSTALL_YAML} ;
  kubectl --context ${cluster_name} apply -f - <<EOF
$(metallb_startip=${metallb_startip} metallb_stopip=${metallb_stopip} envsubst < ${METALLB_POOLCONFIG_YAML})
EOF

}

# Start a docker network
#   args:
#     (1) docker network name
#     (2) docker network subnet
function start_docker_network {
  [[ -z "${1}" ]] && echo "Please provide network name as 1st argument" && return 2 || local network_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide network subnet as 2nd argument" && return 2 || local network_subnet="${2}" ;
  local network_gateway=$(echo ${network_subnet} |  awk -F '.' "{ print \$1\".\"\$2\".\"\$3\".\"1;}") ;
  echo "Starting docker bridge network '${network_name}' with subnet '${network_subnet}' and gateway '${network_gateway}'" ;
  docker network create \
    --driver="bridge" \
    --opt "com.docker.network.bridge.name=${network_name}0" \
    --opt "com.docker.network.driver.mtu=1500" \
    --gateway="${network_gateway}" \
    --subnet="${network_subnet}" \
    "${network_name}" ;
  echo "Flushing docker isolation iptable rules" ;
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;
}

# Remove a docker network
#   args:
#     (1) docker network name
function remove_docker_network {
  echo "Removing docker bridge network '${1}'" ;
  docker network rm "${1}" ;
}

# Start a local k3s cluster
#   args:
#     (1) cluster name
#     (2) k8s version
#     (3) docker network name
#     (4) docker network subnet
#     (5) docker insecure registry
function start_k3s_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide k8s version as 2nd argument" && return 2 || local k8s_version="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide docker network name as 3rd argument" && return 2 || local network_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide docker network subnet as 4th argument" && return 2 || local network_subnet="${4}" ;
  [[ -z "${5}" ]] && echo "No insecure registry provided" && local insecure_registry="" || local insecure_registry="${5}" ;

  if $(docker inspect -f '{{.State.Status}}' ${cluster_name} 2>/dev/null | grep "running" &>/dev/null) ; then
    echo "K3s cluster '${cluster_name}' already running" ;
  elif $(docker inspect -f '{{.State.Status}}' ${cluster_name} 2>/dev/null | grep "exited" &>/dev/null) ; then
    echo "Restarting k3s cluster '${cluster_name}'" ;
    docker start ${cluster_name} ;
  else
    local image="rancher/k3s:v${k8s_version}-k3s1" ;
    print_info "Starting k3s cluster '${cluster_name}':" ;
    print_info "  cluster_name: '${cluster_name}'" ;
    print_info "  image: '${image}'" ;
    print_info "  insecure_registry: '${insecure_registry}'" ;
    print_info "  k8s_version: '${k8s_version}'" ;
    print_info "  network_name: '${network_name}'" ;
    print_info "  network_subnet: '${network_subnet}'" ;
    start_docker_network "${network_name}" "${network_subnet}" ;

    if [[ -z "${insecure_registry}" ]]; then
      k3d cluster create \
        --agents 0 \
        --image ${image} \
        --k3s-arg "--disable=traefik,servicelb@server:0" \
        --network "${network_name}" \
        --no-lb "${cluster_name}" \
        --servers 1 ;
    else
      tee /tmp/k3d-${cluster_name}-registries.yaml <<EOF
mirrors:
  "${insecure_registry}":
    endpoint:
      - http://${insecure_registry}
EOF

      k3d cluster create \
        --agents 0 \
        --image ${image} \
        --k3s-arg "--disable=traefik,servicelb@server:0" \
        --network "${network_name}" \
        --no-lb "${cluster_name}" \
        --registry-config "/tmp/k3d-${cluster_name}-registries.yaml" \
        --servers 1 ;
    fi

    # Add consistency to docker container and kubectl context names
    docker rename "k3d-${cluster_name}-server-0" "${cluster_name}" ;
    kubectl config rename-context "k3d-${cluster_name}" "${cluster_name}" ;
    local apiserver_address=$(get_apiserver_url "${cluster_name}" "${network_name}") ;
    kubectl config set-cluster "k3d-${cluster_name}" --server="${apiserver_address}" ;

    echo "Deploying and configuring metallb in k3s cluster '${cluster_name}'" ;
    deploy_metallb "${cluster_name}" "${network_name}" ;
  fi
}

# Wait for all expected pods in local k3s cluster to be ready
#   args:
#     (1) cluster name
function wait_k3s_cluster_ready {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  print_info "Waiting for all expected pods in cluster '${cluster_name}' to become ready"

  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kube-dns 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector app=local-path-provisioner 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=metrics-server 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=controller 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=speaker 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;

  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kube-dns --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector app=local-path-provisioner --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=metrics-server --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=controller --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=speaker --timeout=300s ;
}

# Stop a local k3s cluster
#   args:
#     (1) cluster name
function stop_k3s_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  if $(docker inspect -f '{{.State.Status}}' ${cluster_name} | grep "running" &>/dev/null) ; then
    echo "Going to stop k3s cluster '${cluster_name}'" ;
    k3d cluster stop ${cluster_name} ;
  fi
}

# Remove a local k3s cluster
#   args:
#     (1) cluster name
#     (2) docker network
function remove_k3s_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide docker network name as 2nd argument" && return 2 || local network_name="${2}" ;
  if $(k3d cluster list | grep "${cluster_name}" &>/dev/null) ; then
    echo "Going to remove k3s cluster '${cluster_name}'" ;
    docker rename "${cluster_name}" "k3d-${cluster_name}-server-0" ;
    kubectl config rename-context "${cluster_name}" "k3d-${cluster_name}" ;
    k3d cluster delete "${cluster_name}" ;
    if $(docker network ls | grep ${network_name} &>/dev/null) ; then
      echo "Going to remove docker network '${network_name}'" ;
      docker network rm ${network_name} ;
    fi
  fi
}

# Start a local kind cluster
#   args:
#     (1) cluster name
#     (2) k8s version
#     (3) docker network name
#     (4) docker network subnet
#     (5) docker insecure registry
function start_kind_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide k8s version as 2nd argument" && return 2 || local k8s_version="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide docker network name as 3rd argument" && return 2 || local network_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide docker network subnet as 4th argument" && return 2 || local network_subnet="${4}" ;
  [[ -z "${5}" ]] && echo "No insecure registry provided" && local insecure_registry="" || local insecure_registry="${5}" ;

  if $(docker inspect -f '{{.State.Status}}' ${cluster_name} 2>/dev/null | grep "running" &>/dev/null) ; then
    echo "Kind cluster '${cluster_name}' already running" ;
  elif $(docker inspect -f '{{.State.Status}}' ${cluster_name} 2>/dev/null | grep "exited" &>/dev/null) ; then
    echo "Restarting kind cluster '${cluster_name}'" ;
    docker start ${cluster_name} ;
  else
    local image="kindest/node:v${k8s_version}" ;
    print_info "Starting kind cluster '${cluster_name}':" ;
    print_info "  cluster_name: '${cluster_name}'" ;
    print_info "  image: '${image}'" ;
    print_info "  insecure_registry: '${insecure_registry}'" ;
    print_info "  k8s_version: '${k8s_version}'" ;
    print_info "  network_name: '${network_name}'" ;
    print_info "  network_subnet: '${network_subnet}'" ;
    start_docker_network "${network_name}" "${network_subnet}" ;

    if [[ -z "${insecure_registry}" ]]; then
      KIND_EXPERIMENTAL_DOCKER_NETWORK=${network_name} kind create cluster \
        --name "${cluster_name}" \
        --image "${image}" ;
    else
      tee /tmp/kind-${cluster_name}-registries.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${insecure_registry}"] 
    endpoint = ["http://${insecure_registry}"]
EOF

      KIND_EXPERIMENTAL_DOCKER_NETWORK=${network_name} kind create cluster \
        --config /tmp/kind-${cluster_name}-registries.yaml \
        --image "${image}" \
        --name "${cluster_name}";
    fi

    # Add consistency to docker container and kubectl context names
    docker rename "${cluster_name}-control-plane" "${cluster_name}" ;
    kubectl config rename-context "kind-${cluster_name}" "${cluster_name}" ;
    local apiserver_address=$(get_apiserver_url "${cluster_name}" "${network_name}") ;
    kubectl config set-cluster "kind-${cluster_name}" --server="${apiserver_address}" ;

    echo "Deploying metrics-server in kind cluster '${cluster_name}'" ;
    kubectl --context ${cluster_name} apply -f ${METRICS_SERVER_INSTALL_YAML} ;

    echo "Deploying and configuring metallb in kind cluster '${cluster_name}'" ;
    deploy_metallb "${cluster_name}" "${network_name}" ;
  fi
}

# Wait for all expected pods in local kind cluster to be ready
#   args:
#     (1) cluster name
function wait_kind_cluster_ready {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  print_info "Waiting for all expected pods in cluster '${cluster_name}' to become ready"

  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kube-dns 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=etcd 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kindnet 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-apiserver 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-controller-manager 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kube-proxy 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-scheduler 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=metrics-server 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n local-path-storage --selector app=local-path-provisioner 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=controller 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=speaker 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;

  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kube-dns --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=etcd --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kindnet --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-apiserver --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-controller-manager --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kube-proxy --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-scheduler --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=metrics-server --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n local-path-storage --for condition=ready --selector app=local-path-provisioner --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=controller --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=speaker --timeout=300s ;
}

# Stop a local kind cluster
#   args:
#     (1) cluster name
function stop_kind_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  if $(docker inspect -f '{{.State.Status}}' ${cluster_name} | grep "running" &>/dev/null) ; then
    echo "Going to stop kind cluster '${cluster_name}'" ;
    docker stop ${cluster_name} ;
  fi
}

# Remove a local kind cluster
#   args:
#     (1) cluster name
#     (2) docker network
function remove_kind_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide docker network name as 2nd argument" && return 2 || local network_name="${2}" ;
  if $(kind get clusters | grep "${cluster_name}" &>/dev/null) ; then
    echo "Going to remove kind cluster '${cluster_name}'" ;
    docker rename "${cluster_name}" "${cluster_name}-control-plane" ;
    kubectl config rename-context "${cluster_name}" "kind-${cluster_name}" ;
    kind delete cluster --name "${cluster_name}" ;
    if $(docker network ls | grep ${network_name} &>/dev/null) ; then
      echo "Going to remove docker network '${network_name}'" ;
      docker network rm ${network_name} ;
    fi
  fi
}

# Start a local minikube cluster
#   args:
#     (1) cluster name
#     (2) k8s version
#     (3) docker network name
#     (4) docker network subnet
#     (5) docker insecure registry
function start_minikube_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide k8s version as 2nd argument" && return 2 || local k8s_version="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide docker network name as 3rd argument" && return 2 || local network_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide docker network subnet as 4th argument" && return 2 || local network_subnet="${4}" ;
  [[ -z "${5}" ]] && echo "No insecure registry provided" && local insecure_registry="" || local insecure_registry="${5}" ;
  if $(minikube --profile ${cluster_name} status 2>/dev/null | grep "host:" | grep "Running" &>/dev/null) ; then
    echo "Minikube cluster profile '${cluster_name}' already running" ;
  elif $(minikube --profile ${cluster_name} status 2>/dev/null | grep "host:" | grep "Stopped" &>/dev/null) ; then
    echo "Restarting minikube cluster profile '${cluster_name}'" ;
    minikube start --driver=docker --profile ${cluster_name} ;
  else
    print_info "Starting minikube cluster in minikube profile '${cluster_name}':" ;
    print_info "  cluster_name: '${cluster_name}'" ;
    print_info "  insecure_registry: '${insecure_registry}'" ;
    print_info "  k8s_version: '${k8s_version}'" ;
    print_info "  network_name: '${network_name}'" ;
    print_info "  network_subnet: '${network_subnet}'" ;
    start_docker_network "${network_name}" "${network_subnet}" ;

    if [[ -z "${insecure_registry}" ]]; then
      minikube start \
        --apiserver-port 6443 \
        --driver docker \
        --kubernetes-version v${k8s_version} \
        --network ${network_name} \
        --profile ${cluster_name} \
        --subnet ${network_subnet} ;
    else
      local insecure_registry_subnet=$(echo ${insecure_registry} |  awk -F '.' "{ print \$1\".\"\$2\".\"\$3\".0/24\";}") ;
      minikube start \
        --apiserver-port 6443 \
        --driver docker \
        --insecure-registry ${insecure_registry_subnet} \
        --kubernetes-version v${k8s_version} \
        --network ${network_name} \
        --profile ${cluster_name} \
        --subnet ${network_subnet} ;
    fi

    echo "Deploying metrics-server in minikube cluster '${cluster_name}'" ;
    kubectl --context ${cluster_name} apply -f ${METRICS_SERVER_INSTALL_YAML} ;

    echo "Deploying and configuring metallb in minikube cluster '${cluster_name}'" ;
    deploy_metallb "${cluster_name}" "${network_name}" ;
  fi
}

# Wait for all expected pods in local minikube cluster to be ready
#   args:
#     (1) cluster name
function wait_minikube_cluster_ready {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  print_info "Waiting for all expected pods in cluster '${cluster_name}' to become ready"

  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kube-dns 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=etcd 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-apiserver 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-controller-manager 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=kube-proxy 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector component=kube-scheduler 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector k8s-app=metrics-server 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n kube-system --selector integration-test=storage-provisioner 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=controller 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;
  while ! $(kubectl --context ${cluster_name} get pod -n metallb-system --selector app=metallb,component=speaker 2>&1 | grep -v "found" &>/dev/null) ; do sleep 0.1 ; done ;

  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kube-dns --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=etcd --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-apiserver --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-controller-manager --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=kube-proxy --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector component=kube-scheduler --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector k8s-app=metrics-server --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n kube-system --for condition=ready --selector integration-test=storage-provisioner --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=controller --timeout=300s ;
  kubectl --context ${cluster_name} wait pod -n metallb-system --for condition=ready --selector app=metallb,component=speaker --timeout=300s ;
}

# Stop a local minikube cluster
#   args:
#     (1) cluster name
function stop_minikube_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  if $(minikube --profile ${cluster_name} status 2>/dev/null | grep "host:" | grep "Running" &>/dev/null) ; then
    echo "Going to stop minikube cluster in minikube profile '${cluster_name}'" ;
    minikube stop --profile ${cluster_name} 2>/dev/null ;
  fi
}

# Remove a local minikube cluster
#   args:
#     (1) cluster name
#     (2) docker network
function remove_minikube_cluster {
  [[ -z "${1}" ]] && echo "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide docker network name as 2nd argument" && return 2 || local network_name="${2}" ;
  if $(minikube profile list --light=true 2>/dev/null | grep ${cluster_name} &>/dev/null) ; then
    echo "Going to remove minikube cluster in minikube profile '${cluster_name}'" ;
    minikube delete --profile ${cluster_name} 2>/dev/null ;
    if $(docker network ls | grep ${network_name} &>/dev/null) ; then
      echo "Going to remove docker network '${network_name}'" ;
      docker network rm ${network_name} ;
    fi
  fi
}

# Start a local kubernetes cluster
#   args:
#     (1) local kubernetes provider
#     (2) cluster name
#     (3) k8s version
#     (4) docker network name
#     (5) docker network subnet
#     (6) docker insecure registry
function start_cluster {
  [[ -z "${1}" ]] && echo "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide k8s version as 3rd argument" && return 2 || local k8s_version="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide docker network name as 4th argument" && return 2 || local network_name="${4}" ;
  [[ -z "${5}" ]] && local network_subnet=$(get_docker_subnet_free) && echo "No subnet provided, using a free one '${network_subnet}'" || local network_subnet="${5}" ;
  [[ -z "${6}" ]] && echo "No insecure registry provided" && local insecure_registry="" || local insecure_registry="${6}" ;
  precheck ${k8s_provider};

  local existing_context_provider=$(get_provider_type_by_kubectl_context "${cluster_name}") ;
  local existing_container_provider=$(get_provider_type_by_container_name "${cluster_name}") ;

  if ( [[ ${existing_context_provider} == ${k8s_provider} ]] && [[ ${existing_container_provider} == ${k8s_provider} ]] ) || \
     ( [[ ${existing_context_provider} == "notfound" ]] && [[ ${existing_container_provider} == "notfound" ]] ) ; then

    echo "Going to start ${k8s_provider} based kubernetes cluster '${cluster_name}'" ;
    case ${k8s_provider} in
      "k3s")
        start_k3s_cluster "${cluster_name}" "${k8s_version}" "${network_name}" "${network_subnet}" "${insecure_registry}";
        ;;
      "kind")
        start_kind_cluster "${cluster_name}" "${k8s_version}" "${network_name}" "${network_subnet}" "${insecure_registry}";
        ;;
      "minikube")
        start_minikube_cluster "${cluster_name}" "${k8s_version}" "${network_name}" "${network_subnet}" "${insecure_registry}";
        ;;
    esac

  else
    print_error "Detected an unexpected kubectl context '${existing_context_provider}' or docker container '${existing_container_provider}' state for desired cluster with name '${cluster_name}' and provider '${k8s_provider}'" ;
    kubectl config view ;
    docker ps ;
    docker network ls ;
    print_error "Please resolve this conflict manually" ;
    exit 1 ;
  fi
}

# Wait for all expected pods in local kubernetes cluster to be ready
#   args:
#     (1) local kubernetes provider
#     (2) cluster name
function wait_cluster_ready {
  [[ -z "${1}" ]] && echo "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  precheck ${k8s_provider};

  echo "Going to wait for ${k8s_provider} based kubernetes cluster '${cluster_name}' to be ready" ;
  echo -n "Waiting for kubectl context of cluster '${cluster_name}' to become available: "
  while ! $(kubectl config get-contexts | grep "${cluster_name}" &>/dev/null) ; do sleep 0.1 ; echo -n "." ; done ; echo "DONE" ;
  echo -n "Waiting for kubectl to be able to reach cluster apiserver of '${cluster_name}': "
  while ! $(kubectl --context ${cluster_name} get nodes &>/dev/null) ; do sleep 0.1 ; echo -n "." ; done ; echo "DONE" ;

  case ${k8s_provider} in
    "k3s")
      wait_k3s_cluster_ready "${cluster_name}" ;
      ;;
    "kind")
      wait_kind_cluster_ready "${cluster_name}" ;
      ;;
    "minikube")
      wait_minikube_cluster_ready "${cluster_name}" ;
      ;;
  esac
  kubectl --context ${cluster_name} get pods -A ;
}

# Stop a local kubernetes cluster
#   args:
#     (1) local kubernetes provider
#     (2) cluster name
function stop_cluster {
  [[ -z "${1}" ]] && echo "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  precheck ${k8s_provider};

  echo "Going to stop ${k8s_provider} based kubernetes cluster '${cluster_name}'" ;
  case ${k8s_provider} in
    "k3s")
      stop_k3s_cluster "${cluster_name}" ;
      ;;
    "kind")
      stop_kind_cluster "${cluster_name}" ;
      ;;
    "minikube")
      stop_minikube_cluster "${cluster_name}" ;
      ;;
  esac
}

# Remove a local kubernetes cluster
#   args:
#     (1) local kubernetes provider
#     (2) cluster name
#     (3) docker network
function remove_cluster {
  [[ -z "${1}" ]] && echo "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide docker network name as 3rd argument" && return 2 || local network_name="${3}" ;
  precheck ${k8s_provider};

  echo "Going to remove ${k8s_provider} based kubernetes cluster '${cluster_name}'" ;
  case ${k8s_provider} in
    "k3s")
      remove_k3s_cluster "${cluster_name}" "${network_name}" ;
      ;;
    "kind")
      remove_kind_cluster "${cluster_name}" "${network_name}" ;
      ;;
    "minikube")
      remove_minikube_cluster "${cluster_name}" "${network_name}" ;
      ;;
  esac
}

# Check if kubernetes version is available
#   args:
#     (1) local kubernetes provider
#     (2) k8s version
function is_k8s_version_available {
  [[ -z "${1}" ]] && echo "Please provide local kubernetes provider as 1st argument" && return 2 || local k8s_provider="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide k8s version as 2nd argument" && return 2 || local k8s_version="${2}" ;

  echo "Going to check if kubernetes version ${k8s_version} is available for provider '${k8s_provider}'" ;
  case ${k8s_provider} in
    "k3s")
      if $(docker images | grep "rancher/k3s" | grep "v${k8s_version}-k3s1" &>/dev/null) ; then
        return 0 ;
      else
        if $(curl --silent "https://hub.docker.com/v2/repositories/rancher/k3s/tags/?page_size=100" | jq -r '.results|.[]|.name' | grep "v${k8s_version}-k3s1" &>/dev/null) ; then
          return 0 ;
        else
          return 1 ;
        fi
      fi
      ;;
    "kind")
      if $(docker images | grep "kindest/node" | grep "v${k8s_version}" &>/dev/null) ; then
        return 0 ;
      else
        if $(curl --silent "https://hub.docker.com/v2/repositories/kindest/node/tags/?page_size=100" | jq -r '.results|.[]|.name' | grep "v${k8s_version}" &>/dev/null) ; then
          return 0 ;
        else
          return 1 ;
        fi
      fi
      ;;
    "minikube")
      if $(curl --silent "https://raw.githubusercontent.com/kubernetes/minikube/master/pkg/minikube/constants/constants_kubernetes_versions.go" | grep "v${k8s_version}" &>/dev/null) ; then
        return 0 ;
      else
        return 1 ;
      fi
      ;;
  esac
}
