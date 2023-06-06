#!/usr/bin/env bash
TEST_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${TEST_DIR}/api.sh
source ${TEST_DIR}/infra.sh

START_GITEA=false

# Infra tests
if ${START_GITEA} ; then
  gitea_start_server ;
  gitea_get_http_url ;
  gitea_bootstrap_server "${TEST_DIR}/config/app.ini" ;
fi

# API tests
gitea_wait_api_ready "localhost:3000" ;
gitea_get_repos_full_name_list "localhost:3000" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "dummy-repo" "dummy-user" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "dummy-repo" "gitea-admin" ;
read -p "Press enter to continue" ;
gitea_create_repo "localhost:3000" "test1" "test1 description bis" ;
gitea_create_repo "localhost:3000" "test2" "test2 description" ;
gitea_create_repo "localhost:3000" "test3" "test3 description" ;
gitea_create_repo "localhost:3000" "test4" "test4 description" ;
read -p "Press enter to continue" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test1" "gitea-admin" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test2" "gitea-admin" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test3" "gitea-admin" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test4" "gitea-admin" ;
gitea_get_repos_full_name_list "localhost:3000" ;
read -p "Press enter to continue" ;
gitea_delete_repo "localhost:3000" "test1" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test2" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test3" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test4" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test5" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test4" "gitea-admin" ;
