#!/usr/bin/env bash
#
# Helper script to create local docker repo with tsb images or push tsb images
# to another private repo.
#
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/helpers.sh

ACTION=${1}
TARGET_REPO=${2}

LOCAL_REPO_NETWORK="registry" 
LOCAL_REPO_NAME="registry"
LOCAL_REPO_SUBNET="192.168.48.0/24"
LOCAL_REPO_PORT=5000

# Start local docker repository
#   args:
#     (1) container name (optional, default 'registry')
#     (2) docker network name (optional, default 'registry')
#     (3) docker network subnet (optional, default '192.168.48.0/24')
function start_local_repo {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REPO_NAME}" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local network_name="${LOCAL_REPO_NETWORK}" || local network_name="${2}" ;
  [[ -z "${3}" ]] && local network_subnet="${LOCAL_REPO_SUBNET}" || local network_subnet="${3}" ;

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
        --publish ${LOCAL_REPO_PORT}:5000 \
        --restart always \
        registry:2 ;
        ;;
  esac
}

# Stop local docker repo
#   args:
#     (1) container name (optional, default 'registry')
function stop_local_repo {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REPO_NAME}" || local container_name="${1}" ;
  docker stop ${container_name} 2>/dev/null ;
  print_info "Local docker repository '${container_name}' stopped"
}

# Remove local docker repo
#   args:
#     (1) container name (optional, default 'registry')
#     (2) docker network name (optional, default 'registry')
function remove_local_repo {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REPO_NAME}" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local network_name="${LOCAL_REPO_NETWORK}" || local network_name="${2}" ;

  docker stop ${container_name} 2>/dev/null ;
  docker rm --volumes ${container_name} 2>/dev/null ;
  docker network rm ${network_name} 2>/dev/null ;
  print_info "Local docker repository '${container_name}' removed" ;
}

# Get local docker repo endpoint
#   args:
#     (1) container name (optional, default 'registry')
function get_repo_endpoint {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REPO_NAME}" || local container_name="${1}" ;

  local repo_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}" 2>/dev/null | awk NF) ;
  if [[ -z "${repo_ip}" ]]; then
    print_error "Container '${container_name}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "${repo_ip}:${LOCAL_REPO_PORT}" ;
}

# Add local docker repo as docker insecure registry
#   args:
#     (1) container name (optional, default 'registry')
function add_insecure_registry {
  [[ -z "${1}" ]] && local container_name="${LOCAL_REPO_NAME}" || local container_name="${1}" ;

  local repo_endpoint=$(get_repo_endpoint "${container_name}") ;
  local docker_json="{\"insecure-registries\" : [\"http://${repo_endpoint}\"]}" ;

  # In case no local docker configuration file yet, create new from scratch
  if [[ ! -f /etc/docker/daemon.json ]]; then
    sudo sh -c "echo '${docker_json}' > /etc/docker/daemon.json" ;
    sudo systemctl restart docker ;
    print_info "Insecure registry configured" ;
  elif cat /etc/docker/daemon.json | grep ${repo_endpoint} &>/dev/null; then
    print_info "Insecure registry already configured" ;
  else
    print_warning "File /etc/docker/daemon.json already exists" ;
    print_warning "Please merge ${docker_json} manually and restart docker with 'sudo systemctl restart docker'" ;
    exit 1 ;
  fi
}

# Sync a given container image to target repo
#   args:
#     (1) target repo
#     (2) image
function sync_single_image {
  [[ -z "${1}" ]] && print_error "Please provide target repo as 1st argument" && return 2 || local target_repo="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide image as 2nd argument" && return 2 || local image="${2}" ;

  local image_without_repo=$(echo ${image} | sed "s|containers.dl.tetrate.io/||") ;
  local image_name=$(echo ${image_without_repo} | awk -F: '{print $1}') ;
  local image_tag=$(echo ${image_without_repo} | awk -F: '{print $2}') ;

  if ! docker image inspect ${image} &>/dev/null ; then
    docker pull ${image} ;
  fi
  if ! docker image inspect ${target_repo}/${image_without_repo} &>/dev/null ; then
    docker tag ${image} ${target_repo}/${image_without_repo} ;
  fi
  if ! curl -s -X GET ${target_repo}/v2/${image_name}/tags/list | grep "${image_tag}" &>/dev/null ; then
    docker push ${target_repo}/${image_without_repo} ;
  fi
}

# Sync tsb container images to target repo (if not yet available)
#   args:
#     (1) target repo
function sync_tsb_images {
  [[ -z "${1}" ]] && print_error "Please provide target repo as 1st argument" && return 2 || local target_repo="${1}" ;
  echo "Going to sync tsb images to target repo '${target_repo}'"

  # Sync all tsb images to target repo
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    sync_single_image ${target_repo} ${image} ;
  done

  # Sync images for application deployment and debugging to target repo
  sync_single_image ${target_repo} "containers.dl.tetrate.io/obs-tester-server:1.0" ;
  sync_single_image ${target_repo} "containers.dl.tetrate.io/netshoot:latest" ;

  print_info "All tsb images synced and available in the target repo '${target_repo}'" ;
}


if [[ ${ACTION} = "info" ]]; then
  echo $(get_repo_endpoint) ;
  exit 0 ;
fi

if [[ ${ACTION} = "start" ]]; then
  start_local_repo ;
  add_insecure_registry ;
  exit 0 ;
fi

if [[ ${ACTION} = "stop" ]]; then
  stop_local_repo ;
  exit 0 ;
fi

if [[ ${ACTION} = "remove" ]]; then
  remove_local_repo ;
  exit 0 ;
fi

if [[ ${ACTION} = "sync" ]]; then
  [[ -z "${TARGET_REPO}" ]] && target_repo=$(get_repo_endpoint) || target_repo="${TARGET_REPO}" ;
  sync_tsb_images "${target_repo}" ;
  exit 0 ;
fi


echo "Please specify correct action:"
echo "  - info : get local docker repo url (default: 192.168.48.2:5000)"
echo "  - start : start local docker repo"
echo "  - stop : stop local docker repo"
echo "  - remove : remove local docker repo"
echo "  - sync <target-repo> : sync tsb images from official repo to provided target repo (default: 192.168.48.2:5000)"
exit 1
