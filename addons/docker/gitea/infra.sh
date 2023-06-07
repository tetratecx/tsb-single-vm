# Helper functions to start, stop and remove gitea (a lightweight git server)
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

GITEA_HTTP_PORT=3000
GITEA_SSH_PORT=2222

GITEA_ADMIN_USER="gitea-admin"
GITEA_ADMIN_PASSWORD="gitea-admin"

# Print info messages
#   args:
#     (1) message
function print_info {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${GREENB_COLOR}${message}${END_COLOR}" ;
}

# Print error messages
#   args:
#     (1) message
function print_error {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${REDB_COLOR}${message}${END_COLOR}" ;
}

# Start gitea server in docker
#   args:
#     (1) container name (optional, default 'gitea')
#     (2) docker network (optional, default 'gitea')
#     (3) data folder (optional, default '/tmp/gitea')
#     (4) gitea version (optional, default 'latest')
function gitea_start_server {
  [[ -z "${1}" ]] && local container_name="gitea" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local docker_network="gitea" || local docker_network="${2}" ;
  [[ -z "${3}" ]] && local data_folder="/tmp/gitea" || local data_folder="${3}" ;
  [[ -z "${4}" ]] && local gitea_version="latest" || local gitea_version="${4}" ;

  if $(docker network ls --format "{{.Name}}" | grep "${docker_network}" &>/dev/null); then
    echo "Found docker network '${docker_network}'" ;
  else
    print_error "Cannot find docker network '${docker_network}'" ;
    return 1 ;
  fi

  # Start, restart or do nothing based on running state of container
  case $(docker container inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null) in
    "true")
      echo "Container '${container_name}' already running" ;
      ;;
    "false")
      echo "Restart container '${container_name}'" ;
      docker start "${container_name}" ;
      ;;
    *)
      echo "Start container '${container_name}' in docker network '${docker_network}'" ;
      mkdir -p ${data_folder} ;
      docker run --detach \
        --env USER_GID="1000" \
        --env USER_UID="1000" \
        --hostname "${container_name}" \
        --name "${container_name}" \
        --network "${docker_network}" \
        --publish ${GITEA_HTTP_PORT}:${GITEA_HTTP_PORT} --publish ${GITEA_SSH_PORT}:${GITEA_SSH_PORT} \
        --restart always \
        --volume /etc/localtime:/etc/localtime:ro \
        --volume /etc/timezone:/etc/timezone:ro \
        --volume ${data_folder}:/data \
        gitea/gitea:${gitea_version} ;
      ;;
  esac

  # Join container to proper network if it was connected to another network
  if $(docker network inspect "${docker_network}" -f '{{range.Containers}}{{println .Name}}{{end}}' | awk NF | grep "${container_name}" &>/dev/null); then
    echo "Container '${container_name}' already runnning in network '${docker_network}'" ;
  else
    echo "Connecting container '${container_name}' to docker network '${docker_network}'" ;
    docker network connect "${docker_network}" "${container_name}" ;
  fi

  print_info "Container '${container_name}' running in docker network '${docker_network}'" ;
}

# Stop gitea server in docker
#   args:
#     (1) container name (optional, default 'gitea')
function gitea_stop_server {
  [[ -z "${1}" ]] && local container_name="gitea" || local container_name="${1}" ;
  docker stop "${container_name}" 2>/dev/null ;
  print_info "Stopped container '${container_name}'" ;
}

# Remove gitea server in docker
#   args:
#     (1) container name (optional, default 'gitea')
#     (2) data folder (optional, default '/tmp/gitea')
function gitea_remove_server {
  [[ -z "${1}" ]] && local container_name="gitea" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local data_folder="/tmp/gitea" || local data_folder="${2}" ;

  docker stop "${container_name}" 2>/dev/null ;
  docker rm --volumes "${container_name}" 2>/dev/null ;
  print_info "Removed container '${container_name}'" ;
}

# Get gitea server http url
#   args:
#     (1) container name (optional, default 'gitea')
function gitea_get_http_url {
  [[ -z "${1}" ]] && local container_name="gitea" || local container_name="${1}" ;

  local gitea_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}" 2>/dev/null | awk NF) ;
  if [[ -z "${gitea_ip}" ]]; then
    print_error "Container '${container_name}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${gitea_ip}:${GITEA_HTTP_PORT}" ;
}

# Get gitea server http url with credentials
#   args:
#     (1) container name (optional, default 'gitea')
#     (2) admin user (optional, default 'gitea-admin')
#     (3) admin password (optional, default 'gitea-admin')
function gitea_get_http_url_with_credentials {
  [[ -z "${1}" ]] && local container_name="gitea" || local container_name="${1}" ;
  [[ -z "${2}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${2}" ;
  [[ -z "${3}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${3}" ;

  local gitea_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}" 2>/dev/null | awk NF) ;
  if [[ -z "${gitea_ip}" ]]; then
    print_error "Container '${container_name}' has no ip address or is not running" ;
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${gitea_ip}:${GITEA_HTTP_PORT}" ;
}

# Bootstrap gitea server
#   args:
#     (1) config file
#     (2) container name (optional, default 'gitea')
#     (3) data folder (optional, default '/tmp/gitea')
#     (4) admin user (optional, default 'gitea-admin')
#     (5) admin password (optional, default 'gitea-admin')
#     (6) admin email (optional, default 'gitea-admin@gitea.local')
function gitea_bootstrap_server {
  [[ -z "${1}" ]] && print_error "Please provide config file as 1st argument" && return 2 || local config_file="${1}" ;
  [[ ! -f "${1}" ]] && print_error "Config file does not exist" && return 2 || local config_file="${1}" ;
  [[ -z "${2}" ]] && local container_name="gitea" || local container_name="${2}" ;
  [[ -z "${3}" ]] && local data_folder="/tmp/gitea" || local data_folder="${3}" ;
  [[ -z "${4}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${4}" ;
  [[ -z "${5}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${5}" ;
  [[ -z "${6}" ]] && local admin_email="${admin_user}@gitea.local" || local admin_email="${6}" ;

  echo -n "Waiting for gitea config folder '${data_folder}/gitea/conf' to be ready: "
  while ! $(ls ${data_folder}/gitea/conf &>/dev/null); do echo -n "." ; sleep 1 ; done
  echo "DONE"

  cp ${config_file} ${data_folder}/gitea/conf/ ;
  docker restart gitea ; sleep 5 ;

  if $(docker exec --user git -it ${container_name} gitea admin user list --admin | grep "${admin_user}" &>/dev/null); then
    echo "Gitea admin user '${admin_user}' already exists"
  else
    echo "Create gitea admin user '${admin_user}'"
    docker exec --user git -it ${container_name} \
      gitea admin user create --username "${admin_user}" --password "${admin_password}" --email "${admin_email}" --admin ;
  fi

  print_info "Gitea server bootstrapped with config '${config_file}' and admin user '${admin_user}'"
}
