#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}


LOCAL_REPO_MIRROR_ENABLED=$(local_mirror_enabled) ;
LOCAL_REPO_NETWORK="registry" 
LOCAL_REPO_NAME="registry"



# Start local docker repo
#   args:
#     (1) repo docker network
#     (2) repo name
function start_local_repo {
  if ! docker network inspect ${1} &>/dev/null ; then
    docker network create ${1} --subnet=192.168.48.0/24 ;
  fi

  if docker ps --filter "status=running" | grep ${2} &>/dev/null ; then
    echo "Do nothing, local repo ${2} in docker network ${1} is already running"
  elif docker ps --filter "status=exited" | grep ${2} &>/dev/null ; then
    print_info "Going to start local repo ${2} in docker network ${1} again"
    docker start ${2} ;
  else
    print_info "Going to start local repo ${2} in docker network ${1} for the first time"
    docker run -d -p 5000:5000 --restart=always --net ${1} --name ${2} registry:2 ;
  fi
}

# Stop local docker repo
#   args:
#     (1) repo name
function stop_local_repo {
  if docker inspect ${1} &>/dev/null ; then
    docker stop ${1} &>/dev/null ;
    print_info "Local docker repo ${1} stopped"
  fi
}

# Stop local docker repo
#   args:
#     (1) repo docker network
#     (2) repo name
function remove_local_repo {
  if docker inspect ${2} &>/dev/null ; then
    docker stop ${2} &>/dev/null ;
    docker rm ${2} &>/dev/null ;
    print_info "Local docker repo stopped and removed"
  fi
  if docker network inspect ${1} &>/dev/null ; then
    docker network rm ${1} &>/dev/null ;
    print_info "Local docker repo network removed"
  fi
}

# Get local docker repo endpoint
#   args:
#     (1) repo name
function get_repo_endpoint {
  IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1}) ;
  echo "${IP}:5000" ;
}

# Add local docker repo as docker insecure registry
#   args:
#     (1) repo endpoint
function add_insecure_registry {
  DOCKER_JSON="{\"insecure-registries\" : [\"http://${1}\"]}"   
  # In case no local docker configuration file yet, create new from scratch
  if [[ ! -f /etc/docker/daemon.json ]]; then
    sudo sh -c "echo '${DOCKER_JSON}' > /etc/docker/daemon.json"
    sudo systemctl restart docker 
    print_info "Insecure registry configured"
  elif cat /etc/docker/daemon.json | grep ${1} &>/dev/null; then
    print_info "Insecure registry already configured"
    return
  else
    print_warning "File /etc/docker/daemon.json already exists"
    print_warning "Please merge ${DOCKER_JSON} manually and restart docker with 'sudo systemctl restart docker'"
    exit 1
  fi
}

# Sync tsb docker images locally (if not yet available)
#   args:
#     (1) repo endpoint
function sync_tsb_images {
    # Sync all tsb images locally
    for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
      image_without_repo=$(echo ${image} | sed "s|containers.dl.tetrate.io/||")
      image_name=$(echo ${image_without_repo} | awk -F: '{print $1}')
      image_tag=$(echo ${image_without_repo} | awk -F: '{print $2}')
      if ! docker image inspect ${image} &>/dev/null ; then
        docker pull ${image} ;
      fi
      if ! docker image inspect ${1}/${image_without_repo} &>/dev/null ; then
        docker tag ${image} ${1}/${image_without_repo} ;
      fi
      if ! curl -s -X GET ${1}/v2/${image_name}/tags/list | grep "${image_tag}" &>/dev/null ; then
        docker push ${1}/${image_without_repo} ;
      fi
    done

    # Sync image for application deployment
    if ! docker image inspect containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
      docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
    fi
    if ! docker image inspect ${1}/obs-tester-server:1.0 &>/dev/null ; then
      docker tag ${image} ${1}/obs-tester-server:1.0 ;
    fi
    if ! curl -s -X GET ${1}/v2/obs-tester-server/tags/list | grep "1.0" &>/dev/null ; then
      docker push ${1}/obs-tester-server:1.0 ;
    fi
    
    # Sync image for debugging
    if ! docker image inspect containers.dl.tetrate.io/netshoot &>/dev/null ; then
      docker pull containers.dl.tetrate.io/netshoot ;
    fi
    if ! docker image inspect ${1}/netshoot &>/dev/null ; then
      docker tag ${image} ${1}/netshoot ;
    fi
    if ! curl -s -X GET ${1}/v2/netshoot/tags/list | grep "latest" &>/dev/null ; then
      docker push ${1}/netshoot ;
    fi

    print_info "All tsb images synced and avaiable in the local repo"
}


if [[ ${ACTION} = "start" ]]; then
  if [[ ${LOCAL_REPO_MIRROR_ENABLED} == "true" ]]; then
    # Start local docker repo if not running
    start_local_repo ${LOCAL_REPO_NETWORK} ${LOCAL_REPO_NAME} ;
    REPO_ENDPOINT=$(get_repo_endpoint ${LOCAL_REPO_NAME})

    # Add local docker repo as insecure registry
    add_insecure_registry ${REPO_ENDPOINT} ;

    # Sync docker images if needed
    sync_tsb_images ${REPO_ENDPOINT} ;
  fi
  exit 0
fi

if [[ ${ACTION} = "stop" ]]; then
  stop_local_repo ${LOCAL_REPO_NAME} ;
  exit 0
fi

if [[ ${ACTION} = "remove" ]]; then
  remove_local_repo ${LOCAL_REPO_NETWORK} ${LOCAL_REPO_NAME} ;
  exit 0
fi


echo "Please specify correct action:"
echo "  - start"
echo "  - stop"
echo "  - remove"
exit 1