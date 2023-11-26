#!/usr/bin/env bash
#
# Helper script to manage local docker registry and tsb images.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
source "${HELPERS_DIR}/print.sh" ;

LOCAL_REGISTRY_NAME="${LOCAL_REGISTRY_NAME:-registry}"
LOCAL_REGISTRY_NETWORK="${LOCAL_REGISTRY_NETWORK:-registry}"
LOCAL_REGISTRY_PORT="${LOCAL_REGISTRY_PORT:-5000}"
LOCAL_REGISTRY_SUBNET="${LOCAL_REGISTRY_SUBNET:-192.168.48.0/24}"
TETRATE_REGISTRY_URL="${TETRATE_REGISTRY_URL:-containers.dl.tetrate.io}"

# Start local docker registry
#   args:
#     (1) container name (optional, default 'registry')
#     (2) docker network name (optional, default 'registry')
#     (3) docker network subnet (optional, default '192.168.48.0/24')
function start_local_registry {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REGISTRY_NAME}" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local network_name="${LOCAL_REGISTRY_NETWORK}" || local network_name="${2}" ;
  [[ -z "${3}" ]] && local network_subnet="${LOCAL_REGISTRY_SUBNET}" || local network_subnet="${3}" ;

  if $(docker network ls --format "{{.Name}}" | grep "${network_name}" &>/dev/null); then
    echo "Found docker network '${network_name}'" ;
  else
    local network_gateway=$(echo ${network_subnet} |  awk -F '.' "{ print \$1\".\"\$2\".\"\$3\".\"1;}") ;
    echo "Starting docker network '${network_name}' (subnet: '${network_subnet}', gateway: '${network_gateway}')" ;
    docker network create \
      --driver="bridge" \
      --opt "com.docker.network.bridge.name=${network_name}0" \
      --opt "com.docker.network.driver.mtu=1500" \
      --gateway="${network_gateway}" \
      --subnet="${network_subnet}" \
      "${network_name}" ;
    echo "Flushing docker isolation iptable rules" ;
    sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;
  fi

  case $(docker container inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null) in
    "true")
      echo "Container '${container_name}' already running" ;
      ;;
    "false")
      echo "Restart container '${container_name}'" ;
      docker start "${container_name}" ;
      ;;
    *)
      echo "Start container '${container_name}' in docker network '${network_name}'" ;
      docker run --detach \
        --hostname ${container_name} \
        --name ${container_name} \
        --network ${network_name} \
        --publish ${LOCAL_REGISTRY_PORT}:5000 \
        --restart always \
        registry:2 ;
        ;;
  esac
}

# Stop local docker registry
#   args:
#     (1) container name (optional, default 'registry')
function stop_local_registry {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REGISTRY_NAME}" || local container_name="${1}" ;
  docker stop ${container_name} 2>/dev/null ;
  print_info "Local docker registry '${container_name}' stopped"
}

# Remove local docker registry
#   args:
#     (1) container name (optional, default 'registry')
#     (2) docker network name (optional, default 'registry')
function remove_local_registry {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REGISTRY_NAME}" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local network_name="${LOCAL_REGISTRY_NETWORK}" || local network_name="${2}" ;

  docker stop ${container_name} 2>/dev/null ;
  docker rm --volumes ${container_name} 2>/dev/null ;
  docker network rm ${network_name} 2>/dev/null ;
  print_info "Local docker registry '${container_name}' removed" ;
}

# Get local docker registry endpoint
#   args:
#     (1) container name (optional, default 'registry')
function get_local_registry_endpoint {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REGISTRY_NAME}" || local container_name="${1}" ;

  local registry_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}" 2>/dev/null | awk NF) ;
  if [[ -z "${registry_ip}" ]]; then
    print_error "Container '${container_name}' has no ip address or is not running" ;
    return 1 ;
  fi
  echo "${registry_ip}:${LOCAL_REGISTRY_PORT}" ;
}

# Add local docker registry as docker insecure registry
#   args:
#     (1) container name (optional, default 'registry')
function add_insecure_registry {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REGISTRY_NAME}" || local container_name="${1}" ;

  local registry_endpoint=$(get_local_registry_endpoint "${container_name}") ;
  local docker_json="{\"insecure-registries\" : [\"http://${registry_endpoint}\"]}" ;

  # In case no local docker configuration file yet, create new from scratch
  if [[ ! -f /etc/docker/daemon.json ]]; then
    sudo sh -c "echo '${docker_json}' > /etc/docker/daemon.json" ;
    sudo systemctl restart docker ;
    print_info "Insecure registry configured" ;
  elif cat /etc/docker/daemon.json | grep ${registry_endpoint} &>/dev/null; then
    print_info "Insecure registry already configured" ;
  else
    print_warning "File /etc/docker/daemon.json already exists" ;
    print_warning "Please merge ${docker_json} manually and restart docker with 'sudo systemctl restart docker'" ;
    exit 1 ;
  fi
}

# Sync a given container image to local registry
#   args:
#     (1) local registry
#     (2) image (format: <registry>/<image>:<tag>)
function sync_single_image {
  [[ -z "${1}" ]] && print_error "Please provide local registry as 1st argument" && return 2 || local local_registry="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide image as 2nd argument" && return 2 || local image="${2}" ;

  local image_without_registry=$(echo ${image} | sed "s|containers.dl.tetrate.io/||") ;
  local image_name=$(echo ${image_without_registry} | awk -F: '{print $1}') ;
  local image_tag=$(echo ${image_without_registry} | awk -F: '{print $2}') ;

  if ! docker image inspect ${image} &>/dev/null ; then
    docker pull ${image} ;
  fi
  if ! docker image inspect ${local_registry}/${image_without_registry} &>/dev/null ; then
    docker tag ${image} ${local_registry}/${image_without_registry} ;
  fi
  if ! curl -s -X GET ${local_registry}/v2/${image_name}/tags/list | grep "${image_tag}" &>/dev/null ; then
    docker push ${local_registry}/${image_without_registry} ;
  fi

  echo "Image '${image}' synced to '${local_registry}'" ;
}

# Sync tsb container images to local registry (if not yet available)
#   args:
#     (1) local registry
#     (2) tetrate registry username
#     (3) tetrate registry password
#     (4) tetrate registry url (optional, default: containers.dl.tetrate.io)
function sync_tsb_images {
  [[ -z "${1}" ]] && print_error "Please provide local registry as 1st argument" && return 2 || local local_registry="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide tsb source registry username as 2nd argument" && return 2 || local tetrate_registry_user="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide tsb source registry password as 3rd argument" && return 2 || local tetrate_registry_password="${3}" ;
  [[ -z "${4}" ]] && local tetrate_registry_url="${TETRATE_REGISTRY_URL}" || local tetrate_registry_url="${4}" ;


  echo "Going to sync tetrate's tsb images to local registry '${local_registry}'" ;
  if ! command -v tctl &>/dev/null ; then print_error "Error: tctl could not be found. Please install it to continue." ; exit 1 ; fi
  if ! docker login "${tetrate_registry_url}" --username "${tetrate_registry_user}" --password "${tetrate_registry_password}" 2>/dev/null; then
    echo "Failed to login to docker registry at '${tetrate_registry_url}'. Check your credentials" ; exit 1 ;
  else
    echo "Docker registry is reachable and credentials valid: ok" ;
  fi

  # Sync all tsb images to local repo
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    sync_single_image "${local_registry}" "${image}" ;
  done

  # Sync images for application deployment and debugging to local repo
  sync_single_image "${local_registry}" "containers.dl.tetrate.io/obs-tester-server:1.0" ;
  sync_single_image "${local_registry}" "containers.dl.tetrate.io/netshoot:latest" ;

  print_info "All tsb images synced and available in the local registry '${local_registry}'" ;
}
