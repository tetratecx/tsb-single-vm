#!/usr/bin/env bash
SCENARIO_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;

if [[ -z "${BASE_DIR}" ]]; then
    echo "BASE_DIR environment variable is not set or is empty" ;
    exit 1 ;
fi

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/certs.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/addons/docker/gitea/api.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/addons/docker/gitea/infra.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/addons/k8s/argocd/api.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/addons/k8s/argocd/infra.sh" ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --deploy: delpoy the scenario" ;
  echo "  --undeploy: undeploy the scenario" ;
  echo "  --info: print info about the scenario" ;
}

INSTALL_REPO_URL=$(get_local_registry_endpoint) ;

GITEA_CONFIG_FILE="${SCENARIO_ROOT_DIR}/gitea/app.ini"
GITEA_REPOS_DIR="${SCENARIO_ROOT_DIR}/repositories"
GITEA_REPOS_CONFIG="${GITEA_REPOS_DIR}/repos.json"
GITEA_REPOS_TEMPDIR="/tmp/gitea-repos"

# Create and sync gitea repositories
function create_and_sync_gitea_repos {
  mkdir -p ${GITEA_REPOS_TEMPDIR}
  local gitea_http_url=$(gitea_get_http_url)
  local gitea_http_url_creds=$(gitea_get_http_url_with_credentials)

  # Gitea repository creation
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG})
  local existing_repo_list=$(gitea_get_repos_list "${gitea_http_url}")
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_description=$(jq -r '.['${repo_index}'].description' ${GITEA_REPOS_CONFIG})
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG})

    if $(echo ${existing_repo_list} | grep "${repo_name}" &>/dev/null); then
      print_info "Gitea repository '${repo_name}' already exists"
    else
      print_info "Going to create gitea repository '${repo_name}'"
      gitea_create_repo_current_user "${gitea_http_url}" "${repo_name}" "${repo_description}" ;
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


# This function deploys the scenario.
#
function deploy() {

  # Start gitea server
  gitea_start_server "" "demo " ;
  gitea_bootstrap_server "${GITEA_CONFIG_FILE}" ;
  gitea_http_url=$(gitea_get_http_url) ;
  gitea_wait_api_ready "${gitea_http_url}" ;
  create_and_sync_gitea_repos "${gitea_http_url}" ;
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Enable gitops in the CP cluster
  print_info "Enabling GitOps in the CP cluster 'demo'" ;
  GITOPS_PATCH='{"spec":{"components":{"gitops":{"enabled":true,"reconcileInterval":"30s"}}}}' ;
  kubectl --context demo  -n istio-system patch controlplane/controlplane --type merge --patch ${GITOPS_PATCH} ;
  tctl x gitops grant demo  ;

  # Deploy argocd in kubernetes
  argocd_deploy "demo " ;
  argocd_set_admin_password "demo " ;

  # Configure argocd for application gitops  
  argocd --insecure cluster add "demo " --yes ;
  argocd --insecure app create tsb-admin --upsert --repo ${gitea_http_url}/${GITEA_ADMIN_USER}/tsb-admin.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;
  argocd --insecure app create app-abc --upsert --repo ${gitea_http_url}/${GITEA_ADMIN_USER}/app-abc.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd --insecure app create app-abc-tsb --upsert --repo ${gitea_http_url}/${GITEA_ADMIN_USER}/app-abc.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;
  argocd --insecure app create app-openapi --upsert --repo ${gitea_http_url}/${GITEA_ADMIN_USER}/app-openapi.git --path k8s --dest-server https://kubernetes.default.svc ;
  argocd --insecure app create app-openapi-tsb --upsert --repo ${gitea_http_url}/${GITEA_ADMIN_USER}/app-openapi.git --path tsb --dest-server https://kubernetes.default.svc --dest-namespace argocd ;

  argocd --insecure app set tsb-admin --sync-policy automated ;
  argocd --insecure app set app-abc --sync-policy automated ;
  argocd --insecure app set app-abc-tsb --sync-policy automated ;
  argocd --insecure app set app-openapi --sync-policy automated ;
  argocd --insecure app set app-openapi-tsb --sync-policy automated ;

  # argocd --insecure app sync tsb-admin ;
  # argocd --insecure app sync app-abc ;
  # argocd --insecure app sync app-abc-tsb ;
  # argocd --insecure app sync app-openapi ;
  # argocd --insecure app sync app-openapi-tsb ;

}


# This function undeploys the scenario.
#
function undeploy() {

  # Remove gitea server
  gitea_remove_server ;

  # Undeploy argocd from kubernetes
  argocd_undeploy demo  ;
}


# This function prints info about the scenario.
#
function info() {

  GITEA_HTTP_URL=$(gitea_get_http_url) ;
  print_info "Gitea server web ui running at ${GITEA_HTTP_URL}" ;

  ARGOCD_IP=$(kubectl --context demo  -n argocd get svc argocd-server --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ;
  print_info "ArgoCD web ui running at https://${ARGOCD_IP}" ;

  while ! APPABC_INGRESS_GW_IP=$(kubectl --context demo  get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! APP1_INGRESS_GW_IP=$(kubectl --context demo  get svc -n app1 app1-ingress --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done
  while ! APP2_INGRESS_GW_IP=$(kubectl --context demo  get svc -n app2 app2-ingress --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
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
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --deploy)
    deploy ;
    ;;
  --undeploy)
    undeploy ;
    ;;
  --info)
    info ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac