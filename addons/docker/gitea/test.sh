#!/usr/bin/env bash
# Test script to test infra and api functions for gitea (a lightweight git server)
#
TEST_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

source ${TEST_DIR}/api.sh
source ${TEST_DIR}/infra.sh

# START_GITEA=true
START_GITEA=false

# Infra tests
if ${START_GITEA} ; then
  gitea_start_server ;
  gitea_get_http_url ;
  gitea_bootstrap_server "${TEST_DIR}/config/app.ini" ;
fi

api_endpoint="localhost:3000"

# API tests
# gitea_create_from_json_file "${api_endpoint}" "${TEST_DIR}/config/test-gitea.json" ;
# read -p "Press enter to continue" ;
# gitea_delete_from_json_file "${api_endpoint}" "${TEST_DIR}/config/test-gitea.json" ;
# read -p "Press enter to continue" ;

# gitea_wait_api_ready "${api_endpoint}" ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-dummy" "user-dummy" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-dummy" "gitea-admin" ; echo $? ;
# read -p "Press enter to continue" ;

# gitea_create_repo_current_user "${api_endpoint}" "repo1-admin" "repo1-admin description" ;
# gitea_create_repo_current_user "${api_endpoint}" "repo2-admin" "repo2-admin description" ;
# gitea_create_repo_current_user "${api_endpoint}" "repo3-admin" "repo3-admin description" ;
# gitea_create_repo_current_user "${api_endpoint}" "repo4-admin" "repo4-admin description" ;
# read -p "Press enter to continue" ;

# gitea_has_repo_by_owner "${api_endpoint}" "repo1-admin" "gitea-admin" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo2-admin" "gitea-admin" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo3-admin" "gitea-admin" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo4-admin" "gitea-admin" ; echo $? ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo1-admin" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo2-admin" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo3-admin" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo4-admin" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo5-admin" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo4-admin" ;
# read -p "Press enter to continue" ;

# gitea_has_org "${api_endpoint}" "barclays" ; echo $? ;
# gitea_has_org "${api_endpoint}" "tetrate" ; echo $? ;
# gitea_has_org "${api_endpoint}" "notexist" ; echo $? ;
# read -p "Press enter to continue" ;

# gitea_create_org "${api_endpoint}" "org1" "org1 description" ;
# gitea_create_org "${api_endpoint}" "org2" "org2 description" ;
# gitea_create_org "${api_endpoint}" "org3" "org3 description" ;
# read -p "Press enter to continue" ;

# gitea_has_org "${api_endpoint}" "org1" ; echo $? ;
# gitea_has_org "${api_endpoint}" "org2" ; echo $? ;
# gitea_has_org "${api_endpoint}" "org3" ; echo $? ;
# read -p "Press enter to continue" ;

# gitea_create_repo_in_org "${api_endpoint}" "org1" "repo-org1" "repo-org1 description" ;
# gitea_create_repo_in_org "${api_endpoint}" "org2" "repo-org2" "repo-org2 description" ;
# gitea_create_repo_in_org "${api_endpoint}" "org3" "repo-org3" "repo-org3 description" ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_has_repo_by_owner "${api_endpoint}" "repo-org1" "org1" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-org2" "org2" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-org3" "org3" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-org4" "org3" ; echo $? ;
# gitea_has_repo_by_owner "${api_endpoint}" "repo-org3" "org4" ; echo $? ;
# read -p "Press enter to continue" ;

# gitea_delete_org "${api_endpoint}" "org1" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "org2" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "org3" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "orgnotexist" ; echo $? ;
# gitea_get_org_list "${api_endpoint}" ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_delete_repo "${api_endpoint}" "org1" "repo-org1" ; echo $? ;
# gitea_delete_repo "${api_endpoint}" "org2" "repo-org2" ; echo $? ;
# gitea_delete_repo "${api_endpoint}" "org3" "repo-org3" ; echo $? ;
# gitea_delete_repo "${api_endpoint}" "org4" "repo-org3" ; echo $? ;
# gitea_get_org_list "${api_endpoint}" ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_delete_org "${api_endpoint}" "org1" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "org2" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "org3" ; echo $? ;
# gitea_delete_org "${api_endpoint}" "orgnotexist" ; echo $? ;
# gitea_get_org_list "${api_endpoint}" ;
# gitea_get_repos_full_name_list "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_delete_all_repos "${api_endpoint}" ;
# gitea_delete_all_orgs "${api_endpoint}" ;
# gitea_delete_all_repos "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_create_user "${api_endpoint}" "user1" "user1-pass" ;
# gitea_create_user "${api_endpoint}" "user2" "user2-pass" ;
# gitea_create_user "${api_endpoint}" "user3" "user3-pass" ;
# gitea_create_user "${api_endpoint}" "user3" "user3-pass" ;
# read -p "Press enter to continue" ;

# gitea_delete_user "${api_endpoint}" "user1" ;
# gitea_delete_user "${api_endpoint}" "user2" ;
# gitea_delete_user "${api_endpoint}" "user3" ;
# gitea_delete_user "${api_endpoint}" "dummy-user" ;
# read -p "Press enter to continue" ;

# gitea_delete_all_users "${api_endpoint}" ;
# read -p "Press enter to continue" ;

# gitea_create_org "${api_endpoint}" "org1" "org1 description" ;
# gitea_create_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1 description" ;
# gitea_create_org_team "${api_endpoint}" "org1" "org1-team2" "org1-team2 description" ;
# gitea_create_org_team "${api_endpoint}" "org1" "org1-team3" "org1-team3 description" ;
# read -p "Press enter to continue" ;
# gitea_delete_org_team "${api_endpoint}" "org1" "org1-team1" ;
# gitea_delete_org_team "${api_endpoint}" "org2" "org1-team1" ;
# gitea_delete_org_team "${api_endpoint}" "org1" "org1-team4" ;
# gitea_has_org_team "${api_endpoint}" "org1" "org1-team4" ; echo $? ;
# read -p "Press enter to continue" ;
# gitea_delete_all_org_teams "${api_endpoint}" "org1" ;

# gitea_create_org "${api_endpoint}" "org1" "org1 description" ;
# gitea_create_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1 description" ;
# read -p "Press enter to continue" ;
# gitea_create_user "${api_endpoint}" "org1-team1-user1" "org1-team1-user1-pass" ;
# gitea_create_user "${api_endpoint}" "org1-team1-user2" "org1-team1-user2-pass" ;
# gitea_create_user "${api_endpoint}" "org1-team1-user3" "org1-team1-user3-pass" ;
# read -p "Press enter to continue" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1-user1" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1-user2" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1-user3" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org-not-exist" "org1-team1" "org1-team1-user3" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "team-not-exist" "org1-team1-user3" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "org1-team1" "user-not-exist" ;
# read -p "Press enter to continue" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo1" "org1-repo1 description" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo2" "org1-repo2 description" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo3" "org1-repo3 description" ;
# read -p "Press enter to continue" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-repo1" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-repo2" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org1" "org1-team1" "org1-repo3" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org-not-exist" "org1-team1" "org1-repo3" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org1" "team-not-exist" "org1-repo3" ;
# gitea_add_repo_to_org_team "${api_endpoint}" "org1" "org1-team1" "repo-not-exist" ;
# read -p "Press enter to continue" ;
# gitea_remove_user_from_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1-user3" ;
# gitea_remove_repo_from_org_team "${api_endpoint}" "org1" "org1-team1" "org1-repo1" ;
# gitea_remove_user_from_org_team "${api_endpoint}" "org1" "org1-team1" "org1-team1-user3" ;
# gitea_remove_repo_from_org_team "${api_endpoint}" "org1" "org1-team1" "org1-repo1" ;

# gitea_create_repo_current_user "${api_endpoint}" "repo1" "repo1 description" ;
# gitea_create_user "${api_endpoint}" "user1" "user1-pass" ;
# gitea_add_collaborator_to_repo "${api_endpoint}" "repo1" "gitea-admin" "user1" ;
# read -p "Press enter to continue" ;
# gitea_remove_collaborator_from_repo "${api_endpoint}" "repo1" "gitea-admin" "user1" ;
# gitea_delete_repo "${api_endpoint}" "gitea-admin" "repo1" ;
# gitea_delete_user "${api_endpoint}" "user1" ;
# read -p "Press enter to continue" ;

# gitea_create_org "${api_endpoint}" "org1" "org1 description" ;
# gitea_create_org_team "${api_endpoint}" "org1" "team1" "team1 description" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "repo1" "repo1 description" ;
# gitea_create_user "${api_endpoint}" "user1" "user1-pass" ;
# gitea_add_user_to_org_team "${api_endpoint}" "org1" "team1" "user1" ;
# gitea_add_org_team_to_repo "${api_endpoint}" "repo1" "org1" "team1" ;
# read -p "Press enter to continue" ;
# gitea_remove_org_team_from_repo "${api_endpoint}" "repo1" "org1" "team1" ;
# gitea_remove_user_from_org_team "${api_endpoint}" "org1" "team1" "user1" ;
# gitea_delete_repo "${api_endpoint}" "org1" "repo1" ;
# gitea_delete_user "${api_endpoint}" "user1" ;
# read -p "Press enter to continue" ;

# gitea_create_org "${api_endpoint}" "org1" "org1 description" "private";
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo1-private" "org1-repo1-private description" "true" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo2-public" "org1-repo2-public description" "false" ;
# gitea_create_repo_in_org "${api_endpoint}" "org1" "org1-repo3-public" "org1-repo3-public description" ;
# gitea_create_org "${api_endpoint}" "org2" "org2 description" "public" ;
# gitea_create_repo_in_org "${api_endpoint}" "org2" "org2-repo1-private" "org2-repo1-private description" "true" ;
# gitea_create_repo_in_org "${api_endpoint}" "org2" "org2-repo2-public" "org2-repo2-public description" "false" ;
# gitea_create_repo_in_org "${api_endpoint}" "org2" "org2-repo3-public" "org2-repo3-public description" ;
# gitea_create_repo_current_user "${api_endpoint}" "user-repo1-private" "user-repo1-private description" "true" ;
# gitea_create_repo_current_user "${api_endpoint}" "user-repo2-public" "user-repo2-public description" "false" ;
# gitea_create_repo_current_user "${api_endpoint}" "user-repo3-public" "user-repo3-public description" ;
# read -p "Press enter to continue" ;
