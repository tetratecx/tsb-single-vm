#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh
source ${SCENARIO_ROOT_DIR}/gitea-api.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

GITEA_HOME="${ROOT_DIR}/output/gitea"
GITEA_CONFIG="${SCENARIO_ROOT_DIR}/gitea/app.ini"
GITEA_VERSION="1.19"

GITEA_ADMIN_USER="gitea-admin"
GITEA_ADMIN_PASSWORD="gitea-admin"

GITEA_REPOS_DIR="${SCENARIO_ROOT_DIR}/repositories"
GITEA_REPOS_TEMPDIR="/tmp/repositories"
GITEA_REPOS_CONFIG="${GITEA_REPOS_DIR}/repos.json"


# Start gitea server
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
  if ! IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' gitea  2>/dev/null ); then
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

  while ! $(ls ${data_folder}/gitea/conf &>/dev/null); do echo -n "." ; sleep 1 ; done
  cp ${GITEA_CONFIG} ${data_folder}/gitea/conf/ ;
  docker restart gitea ; sleep 5 ;
  output=$(docker exec --user git -it gitea gitea admin user create --username "${GITEA_ADMIN_USER}" --password "${GITEA_ADMIN_PASSWORD}" --email "${GITEA_ADMIN_USER}@local" --admin --access-token) ;
}

# Create and sync gitea repositories
function create_and_sync_gitea_repos {
  mkdir -p ${GITEA_REPOS_TEMPDIR}

  local gitea_http_url=$(get_gitea_http_url)
  local gitea_http_url_creds=$(get_gitea_http_url_with_credentials)

  # Project creation using gitea REST APIs
  local project_count=$(jq '. | length' ${GITEA_REPOS_CONFIG})
  local existing_project_full_name_list=$(gitea_get_repos_full_name_list "${gitea_http_url}" "${GITEA_ADMIN_USER}" "${GITEA_ADMIN_PASSWORD}")
  for ((project_index=0; project_index<${project_count}; project_index++)); do
    local project_description=$(jq -r '.['${project_index}'].description' ${GITEA_REPOS_CONFIG})
    local project_name=$(jq -r '.['${project_index}'].name' ${GITEA_REPOS_CONFIG})

    if $(echo ${existing_project_full_name_list} | grep "${project_name}" &>/dev/null); then
      print_info "Gitea project '${project_name}' already exists"
    else
      print_info "Going to create gitea project '${project_name}'"
      gitea_create_repo "${gitea_http_url}" "${GITEA_ADMIN_USER}" "${GITEA_ADMIN_PASSWORD}" "${project_name}" "${project_description}" ;
    fi
  done

  # Repo synchronization using git clone, add, commit and push
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG})
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG})

    print_info "Going to git clone repo '${repo_name}' to ${GITEA_REPOS_TEMPDIR}/${repo_name}"
    mkdir -p ${GITEA_REPOS_TEMPDIR}
    cd ${GITEA_REPOS_TEMPDIR}
    rm -rf ${GITEA_REPOS_TEMPDIR}/${repo_name}
    git clone ${gitea_http_url_creds}/${GITEA_ADMIN_USER}/${repo_name}.git

    print_info "Going add, commit and push new code to repo '${repo_name}'"
    cd ${GITEA_REPOS_TEMPDIR}/${repo_name}
    rm -rf ${GITEA_REPOS_TEMPDIR}/${repo_name}/*
    cp -a ${GITEA_REPOS_DIR}/${repo_name}/. ${GITEA_REPOS_TEMPDIR}/${repo_name}
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

  # Start gitea server in demo-cluster network
  start_gitea "demo-cluster" "${GITEA_HOME}" ;
  GITLAB_HTTP_URL=$(get_gitea_http_url) ;
  initialize_gitea "${GITEA_HOME}" ;
  create_and_sync_gitea_repos ;
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;

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
  kubectl --context demo-cluster wait deployment -n argocd argocd-server --for condition=Available=True --timeout=600s ;

  # Change argocd initias password if needed
  while ! INITIAL_ARGOCD_PW=$(argocd --insecure admin initial-password -n argocd | head -1 2>/dev/null) ; do
    sleep 1;
  done
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
  argocd app create app-abc --repo ${GITLAB_HTTP_URL}/${GITEA_ADMIN_USER}/app-abc.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd app create app-abc-tsb --repo ${GITLAB_HTTP_URL}/${GITEA_ADMIN_USER}/app-abc.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;

  exit 0
fi


if [[ ${ACTION} = "undeploy" ]]; then

  # Remove gitea server
  remove_gitea "${GITEA_HOME}" ;

  # Remove argocd
  kubectl --context demo-cluster delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml ;
  kubectl --context demo-cluster delete namespace argocd ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  GITEA_HTTP_URL=$(get_gitea_http_url) ;
  print_info "Gitea server web ui running at ${GITEA_HTTP_URL}" ;

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
