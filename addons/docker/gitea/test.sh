#!/usr/bin/env bash
# Test script to test infra and api functions for gitea (a lightweight git server)
#
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
gitea_has_repo_by_name_from_owner "localhost:3000" "dummy-repo" "dummy-user" ; echo $? ;
gitea_has_repo_by_name_from_owner "localhost:3000" "dummy-repo" "gitea-admin" ; echo $? ;
read -p "Press enter to continue" ;
gitea_create_repo "localhost:3000" "test1" "test1 description" ;
gitea_create_repo "localhost:3000" "test2" "test2 description" ;
gitea_create_repo "localhost:3000" "test3" "test3 description" ;
gitea_create_repo "localhost:3000" "test4" "test4 description" ;
read -p "Press enter to continue" ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test1" "gitea-admin" ; echo $? ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test2" "gitea-admin" ; echo $? ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test3" "gitea-admin" ; echo $? ;
gitea_has_repo_by_name_from_owner "localhost:3000" "test4" "gitea-admin" ; echo $? ;
gitea_get_repos_full_name_list "localhost:3000" ;
read -p "Press enter to continue" ;
gitea_delete_repo "localhost:3000" "test1" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test2" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test3" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test4" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test5" "gitea-admin" ;
gitea_delete_repo "localhost:3000" "test4" "gitea-admin" ;
read -p "Press enter to continue" ;
gitea_has_org "localhost:3000" "barclays" ; echo $? ;
gitea_has_org "localhost:3000" "tetrate" ; echo $? ;
gitea_has_org "localhost:3000" "notexist" ; echo $? ;
read -p "Press enter to continue" ;
gitea_create_org "localhost:3000" "org1" "org1 description" ;
gitea_create_org "localhost:3000" "org2" "org2 description" ;
gitea_create_org "localhost:3000" "org3" "org3 description" ;
read -p "Press enter to continue" ;
gitea_has_org "localhost:3000" "org1" ; echo $? ;
gitea_has_org "localhost:3000" "org2" ; echo $? ;
gitea_has_org "localhost:3000" "org3" ; echo $? ;
read -p "Press enter to continue" ;
gitea_delete_org "localhost:3000" "org1" ; echo $? ;
gitea_delete_org "localhost:3000" "org2" ; echo $? ;
gitea_delete_org "localhost:3000" "org3" ; echo $? ;
gitea_delete_org "localhost:3000" "orgnotexist" ; echo $? ;
gitea_get_org_list "localhost:3000" ;