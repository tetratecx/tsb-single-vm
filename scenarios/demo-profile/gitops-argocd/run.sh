#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${SCENARIO_ROOT_DIR}/gitlab-api.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

GITEA_HOME="${ROOT_DIR}/output/gitea"
GITEA_CONFIG="${SCENARIO_ROOT_DIR}/gitea/app.ini"
GITEA_VERSION="1.19"

GITEA_ADMIN_USER="gitea-admin"
GITEA_ADMIN_PASSWORD="gitea-admin"

GITLAB_REPOSITORIES_DIR=${SCENARIO_ROOT_DIR}/repositories
GITLAB_REPOSITORIES_TEMPDIR=/tmp/repositories
GITLAB_PROJECTS_CONFIG=${GITLAB_REPOSITORIES_DIR}/projects.json


# Start gitlab server
#   args:
#     (1) docker network
#     (2) data folder
function start_gitea {
  [[ -z "${1}" ]] && echo "Please provide docker network as 1st argument" && return 2 || local docker_network="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide data folder as 2nd argument" && return 2 || local data_folder="${2}" ;

  if docker ps --filter "status=running" | grep gitea &>/dev/null ; then
    echo "Do nothing, container 'gitea' in docker network '${docker_network}' is already running"
  elif docker ps --filter "status=exited" | grep gitea &>/dev/null ; then
    print_info "Going to start container 'gitea' in docker network '${docker_network}' again"
    docker start gitea ;
  else
    print_info "Going to start container 'gitea' in docker network '${docker_network}' for the first time"
    mkdir -p ${data_folder} ;
    docker run --detach \
      --env USER_UID="1000" \
      --env USER_GID="1000" \
      --hostname "gitea" \
      --publish 3000:3000 --publish 2222:2222 \
      --name "gitea" \
      --network ${docker_network} \
      --restart always \
      --volume ${data_folder}:/data \
      --volume /etc/timezone:/etc/timezone:ro \
      --volume /etc/localtime:/etc/localtime:ro \
      gitea/gitea:${GITEA_VERSION} ;
  fi
}

# Remove gitea server
#   args:
#     (1) data folder
function remove_gitea {
  [[ -z "${1}" ]] && echo "Please provide data folder as 1st argument" && return 2 || local data_folder="${1}" ;

  if docker inspect gitea &>/dev/null ; then
    docker stop gitea &>/dev/null ;
    docker rm gitea &>/dev/null ;
    echo "Local gitea container stopped and removed"
  fi
  sudo rm -rf ${data_folder} ;
  print_info "Removed gitea container and local data"
}

# Get local gitea http endpoint
function get_gitea_http_url {
  if ! IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' gitea  2>/dev/null ); then
    print_error "Local gitea container not running" ; 
    return 1 ;
  fi
  echo "http://${IP}:3000" ;
}

# Get local gitea http endpoint with credentials
function get_gitea_http_url_with_credentials {
  if ! IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' gitlab-ee  2>/dev/null ); then
    print_error "Local gitea container not running" ; 
    exit 1 ;
  fi
  echo "http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@${IP}:3000" ;
}

# Initialize local gitea
#   args:
#     (1) data folder
function initialize_gitea {
  [[ -z "${1}" ]] && echo "Please provide data folder as 1st argument" && return 2 || local data_folder="${1}" ;

  while ! $(ls ${data_folder}/gitea/conf &>/dev/null); do sleep 1 ; done
  cp ${GITEA_CONFIG} ${data_folder}/gitea/conf/ ;
  docker exec -it gitea bash -c "killall -SIGHUP gitea"
  cat <<EOF | docker exec --user git --interactive gitea bash
sleep 5 ;
ls /app/gitea/gitea ;
result=`/app/gitea/gitea admin user create --username "${GITEA_ADMIN_USER}" --password "${GITEA_ADMIN_PASSWORD}" --email "${GITEA_ADMIN_USER}@local" --admin --access-token` ;
echo ${result} | awk '{ print $NF }' > /data/gitea/conf/${GITEA_ADMIN_USER}.token ;
echo ${result} > /data/gitea/conf/${GITEA_ADMIN_USER}.token.bis ;
sleep 5 ;
EOF

}

# Get local gitlab docker endpoint
#   args:
#     (1) container name
function get_gitlab_docker_endpoint {
  [[ -z "${1}" ]] && echo "Please provide container name as 1st argument" && return 2 || local container_name="${1}" ;

  if ! IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' gitlab-ee  2>/dev/null ); then
    print_error "Local gitlab container not running" ; 
    exit 1 ;
  fi
  echo "${IP}:${GITLAB_DOCKER_PORT}" ;
}

# Add local docker repo as docker insecure registry
#   args:
#     (1) repo endpoint
function add_insecure_registry {
  [[ -z "${1}" ]] && echo "Please provide repo endpoint as 1st argument" && return 2 || local repo_endpoint="${1}" ;

  local docker_json="{\"insecure-registries\" : [\"http://${repo_endpoint}\"]}"   
  # In case no local docker configuration file yet, create new from scratch
  if [[ ! -f /etc/docker/daemon.json ]]; then
    sudo sh -c "echo '${docker_json}' > /etc/docker/daemon.json"
    sudo systemctl restart docker 
    print_info "Insecure registry configured"
  elif cat /etc/docker/daemon.json | grep ${repo_endpoint} &>/dev/null; then
    print_info "Insecure registry already configured"
  else
    print_warning "File /etc/docker/daemon.json already exists"
    print_warning "Please merge ${docker_json} manually and restart docker with 'sudo systemctl restart docker'"
    exit 1
  fi
}


# Create and sync gitlab repositories
#   args:
#     (1) container name
function create_and_sync_gitlab_repos {
  [[ -z "${1}" ]] && echo "Please provide container name as 1st argument" && return 2 || local container_name="${1}" ;

  mkdir -p ${GITLAB_REPOSITORIES_TEMPDIR}

  local gitlab_http_url=$(get_gitlab_http_url gitlab-ee)
  local gitlab_http_url_creds=$(get_gitlab_http_url_with_credentials gitlab-ee)

  # Project creation using Gitlab REST APIs
  local project_count=$(jq '. | length' ${GITLAB_PROJECTS_CONFIG})
  local existing_project_full_path_list=$(gitlab_get_projects_full_path_list ${gitlab_http_url} ${GITLAB_ROOT_TOKEN})
  for ((project_index=0; project_index<${project_count}; project_index++)); do
    local project_description=$(jq -r '.['${project_index}'].description' ${GITLAB_PROJECTS_CONFIG})
    local project_name=$(jq -r '.['${project_index}'].name' ${GITLAB_PROJECTS_CONFIG})

    if $(echo ${existing_project_full_path_list} | grep "${project_name}" &>/dev/null); then
      print_info "Gitlab project '${project_name}' already exists"
    else
      print_info "Going to create gitlab project '${project_name}'"
      gitlab_create_project ${gitlab_http_url} ${GITLAB_ROOT_TOKEN} ${project_name} "${project_description}" "false" ;
    fi
  done

  # Repo synchronization using git clone, add, commit and push
  local repo_count=$(jq '. | length' ${GITLAB_PROJECTS_CONFIG})
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITLAB_PROJECTS_CONFIG})

    print_info "Going to git clone repo '${repo_name}' to ${GITLAB_REPOSITORIES_TEMPDIR}/${repo_name}"
    mkdir -p ${GITLAB_REPOSITORIES_TEMPDIR}
    cd ${GITLAB_REPOSITORIES_TEMPDIR}
    rm -rf ${GITLAB_REPOSITORIES_TEMPDIR}/${repo_name}
    git clone ${gitlab_http_url_creds}/root/${repo_name}.git

    print_info "Going add, commit and push new code to repo '${repo_name}'"
    cd ${GITLAB_REPOSITORIES_TEMPDIR}/${repo_name}
    rm -rf ${GITLAB_REPOSITORIES_TEMPDIR}/${repo_name}/*
    cp -a ${GITLAB_REPOSITORIES_DIR}/${repo_name}/. ${GITLAB_REPOSITORIES_TEMPDIR}/${repo_name}
    git add -A
    git commit -m "This is an automated commit"
    git push -u origin main
  done
}

# Login as admin into tsb
#   args:
#     (1) tsb organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide tsb organization as 1st argument" && return 2 || local organization="${1}" ;

  expect <<DONE
  spawn tctl login --username admin --password admin --org ${organization}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

if [[ ${ACTION} = "deploy" ]]; then

  # Start gitlab server in demo-cluster network
  start_gitea "demo-cluster" "${GITEA_HOME}" ;
  GITLAB_HTTP_URL=$(get_gitea_http_url) ;
  initialize_gitea "${GITEA_HOME}" ;
  exit
  GITLAB_DOCKER_ENDPOINT=$(get_gitlab_docker_endpoint ${GITLAB_CONTAINER_NAME}) ;
  add_insecure_registry ${GITLAB_DOCKER_ENDPOINT} ;
  gitlab_set_root_api_token ${GITLAB_CONTAINER_NAME} ${GITLAB_HTTP_URL} ${GITLAB_ROOT_TOKEN} ;
  create_and_sync_gitlab_repos ${GITLAB_CONTAINER_NAME} ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Enable gitops in the CP cluster
  print_info "Enabling GitOps in the CP demo-cluster" ;
  GITOPS_PATCH='{"spec":{"components":{"gitops":{"enabled":true,"reconcileInterval":"30s"}}}}' ;
  kubectl --context demo-cluster -n istio-system patch controlplane/controlplane --type merge --patch ${GITOPS_PATCH} ;
  tctl x gitops grant demo-cluster ;

  # Install argocd
  if $(kubectl --context demo-cluster get namespace argocd &>/dev/null) ; then
    echo "Namespace 'argocd' already exists" ;
  else
    kubectl --context demo-cluster create namespace argocd ;
  fi
  kubectl --context demo-cluster apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml ;
  kubectl --context demo-cluster patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' ;
  while ! ARGOCD_IP=$(kubectl --context demo-cluster -n argocd get svc argocd-server --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  # Change argocd initias password if needed
  INITIAL_ARGOCD_PW=$(argocd --insecure admin initial-password -n argocd | head -1) ;
  if $(argocd --insecure login "${ARGOCD_IP}" --username admin --password "${INITIAL_ARGOCD_PW}" &>/dev/null); then
    print_info "Going to change initial password of argocd admin user" ;
    argocd --insecure account update-password --account admin --current-password "${INITIAL_ARGOCD_PW}" --new-password "admin123." ;
  else
    if $(argocd --insecure login "${ARGOCD_IP}" --username admin --password "admin123." &>/dev/null); then
      print_info "Successfully logged in with argocd admin user and new password" ;
    else
      print_error "Failed to login with inital password and new password for argocd admin user" ;
    fi
  fi
  
  argocd --insecure cluster add demo-cluster --yes ;
  argocd app create app-abc --repo ${GITLAB_HTTP_URL}/root/app-abc.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd app create app-abc-tsb --repo ${GITLAB_HTTP_URL}/root/app-abc.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;

  exit 0
fi


if [[ ${ACTION} = "undeploy" ]]; then

  # Remove gitlab server
  # remove_gitlab "${GITLAB_HOME}" ;
  remove_gitea "${GITEA_HOME}" ;

  # Remove argocd
  kubectl --context demo-cluster delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml ;
  kubectl --context demo-cluster delete namespace argocd ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  GITEA_HTTP_URL=$(get_gitea_http_url) ;
  print_info "Gitlab server web ui running at ${GITLAB_HTTP_URL}" ;

  ARGOCD_IP=$(kubectl --context demo-cluster -n argocd get svc argocd-server --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ;
  print_info "ArgoCD web ui running at https://${ARGOCD_IP}" ;

  while ! INGRESS_GW_IP=$(kubectl --context demo-cluster get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  print_info "****************************"
  print_info "*** ABC Traffic Commands ***"
  print_info "****************************"
  echo
  echo "Traffic to Ingress Gateway"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${INGRESS_GW_IP}\" \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${INGRESS_GW_IP}\" \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"
  sleep 1 ;
done"
  echo

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
