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

# Wait for gitea api to be ready
#   args:
#     (1) gitea api url
function wait_gitea_api_ready {
  [[ -z "${1}" ]] && echo "Please provide gitea api url as 1st argument" && return 2 || local base_url="${1}" ;
  echo "Waiting for gitea rest api to become ready"
  while ! out=$(gitea_get_version "${base_url}" "${GITEA_ADMIN_USER}" "${GITEA_ADMIN_PASSWORD}" &>/dev/null); do
    echo -n "." ; sleep 1 ;
  done
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
  GITEA_HTTP_URL=$(get_gitea_http_url) ;
  initialize_gitea "${GITEA_HOME}" ;
  wait_gitea_api_ready "${GITEA_HTTP_URL}" ;
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
    echo -n "."; sleep 1;
  done
  kubectl --context demo-cluster wait deployment -n argocd argocd-server --for condition=Available=True --timeout=600s ;

  # Change argocd initial password if needed
  while ! INITIAL_ARGOCD_PW=$(argocd --insecure admin initial-password -n argocd | head -1 2>/dev/null) ; do
    echo -n "."; sleep 1;
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
  argocd --insecure app create tsb-admin --repo ${GITEA_HTTP_URL}/${GITEA_ADMIN_USER}/tsb-admin.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;
  argocd --insecure app create app-abc --repo ${GITEA_HTTP_URL}/${GITEA_ADMIN_USER}/app-abc.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd --insecure app create app-abc-tsb --repo ${GITEA_HTTP_URL}/${GITEA_ADMIN_USER}/app-abc.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;
  argocd --insecure app create app-openapi --repo ${GITEA_HTTP_URL}/${GITEA_ADMIN_USER}/app-openapi.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd --insecure app create app-openapi-tsb --repo ${GITEA_HTTP_URL}/${GITEA_ADMIN_USER}/app-openapi.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;

  argocd --insecure app set tsb-admin --sync-policy automated ;
  argocd --insecure app set app-abc --sync-policy automated ;
  argocd --insecure app set app-abc-tsb --sync-policy automated ;
  argocd --insecure app set app-openapi --sync-policy automated ;
  argocd --insecure app set app-openapi-tsb --sync-policy automated ;

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

  while ! APPABC_INGRESS_GW_IP=$(kubectl --context demo-cluster get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done
  while ! APP1_INGRESS_GW_IP=$(kubectl --context demo-cluster get svc -n app1 app1-ingress --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done
  while ! APP2_INGRESS_GW_IP=$(kubectl --context demo-cluster get svc -n app2 app2-ingress --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1;
  done

  # Example JWT tokens to be used in the different examples.
  # The following tokens are generated with the following JWKS:
  # {"keys":[{"kid":"18102303-6b9b-40dc-9bf0-cedca433914d","kty":"oct","alg":"HS256","k":"c2lnbmluZy1rZXk="}]}
  # Claims: sub=ignasi, aud=demo, group=engineering, iss=http://jwt.tetrate.io, exp=2034-06-11
  ENG_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOlsiZGVtbyJdLCJleHAiOjIwMzM1OTkxNDksImdyb3VwIjoiZW5naW5lZXJpbmciLCJpYXQiOjE2NzM1OTkxNDksImlzcyI6Imh0dHA6Ly9qd3QudGV0cmF0ZS5pbyIsInN1YiI6ImlnbmFzaSJ9.ptOmyLr2p6Ftd4AvIeHGxkndCsVVatlgxv-XlPro4Jo
  # Claims: sub=bart, aud=demo, group=field, iss=http://jwt.tetrate.io, exp=2034-06-11
  FIELD_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOlsiZGVtbyJdLCJleHAiOjIwMzM1OTkyMDMsImdyb3VwIjoiZmllbGQiLCJpYXQiOjE2NzM1OTkyMDMsImlzcyI6Imh0dHA6Ly9qd3QudGV0cmF0ZS5pbyIsInN1YiI6ImJhcnQifQ.HQeEzDyP5ODgs3WUDQHvJKRG5gZ2_1fb8G7qpBkZFSg

  print_info "************************"
  print_info "*** Traffic Commands ***"
  print_info "************************"
  echo
  echo "Traffic to Application ABC"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${APPABC_INGRESS_GW_IP}\" \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo "Traffic to Application App1"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"app1.demo.tetrate.io:80:${APP1_INGRESS_GW_IP}\" \"http://app1.demo.tetrate.io\""
  echo "Traffic to Application App1 with field token"
  print_command "curl -v -H \"X-B3-Sampled: 1\" -H \"Authorization: Bearer ${FIELD_TOKEN}\" --resolve \"app1.demo.tetrate.io:80:${APP1_INGRESS_GW_IP}\" \"http://app1.demo.tetrate.io/eng\""
  echo "Traffic to Application App1 with eng token"
  print_command "curl -v -H \"X-B3-Sampled: 1\" -H \"Authorization: Bearer ${ENG_TOKEN}\" --resolve \"app1.demo.tetrate.io:80:${APP1_INGRESS_GW_IP}\" \"http://app1.demo.tetrate.io/eng\""
  echo "Traffic to Application App2"
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"app2.demo.tetrate.io:80:${APP2_INGRESS_GW_IP}\" \"http://app2.demo.tetrate.io\""
  echo
  echo "All at once in a loop"
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${APPABC_INGRESS_GW_IP}\" \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"
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
