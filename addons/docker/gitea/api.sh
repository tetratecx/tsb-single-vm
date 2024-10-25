# Helper functions to manage gitea (a lightweight git server)
# API Docs at https://try.gitea.io/api/swagger#
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

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

# Get gitea version
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_version {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/version" ;
}

# Wait for gitea api to be ready
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#     (3) timeout in seconds (optional, default '120')
function gitea_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;
  [[ -z "${3}" ]] && local timeout="120" || local timeout="${3}" ;

  local count=0 ;
  echo -n "Waiting for gitea rest api to become ready at url '${base_url}' (basic auth credentials '${basic_auth}'): "
  while ! $(gitea_get_version "${base_url}" "${basic_auth}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for gitea api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}

# Check if gitea owner has repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if repo exists (prints returned json)
#     - 1 : if repo does not exist
function gitea_has_repo_by_owner {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository description
#     (4) repository private (optional, default 'false')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_repo_current_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository description as 3th argument" && return 2 || local repo_description="${3}" ;
  [[ -z "${4}" ]] && local repo_private="false" || local repo_private="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  repo_owner=$(echo ${basic_auth} | cut -d ':' -f1)
  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/user/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": ${repo_private}}" | jq ;
    print_info "Created repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Create gitea repository in organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) repository name
#     (4) repository description
#     (5) repository private (optional, default 'false')
#     (6) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_repo_in_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3th argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository description as 4th argument" && return 2 || local repo_description="${4}" ;
  [[ -z "${5}" ]] && local repo_private="false" || local repo_private="${5}" ;
  [[ -z "${6}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${6}" ;

  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea repository '${repo_name}' in organization '${org_name}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs/${org_name}/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": ${repo_private}}" | jq ;
    print_info "Created repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Delete gitea repository
#   args:
#     (1) api url
#     (2) repository owner (can be a user or an organization)
#     (3) repository name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository owner as 3th argument" && return 2 || local repo_owner="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea repository '${repo_name}' with owner '${repo_owner}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exists" ;
  fi
}

# Get gitea repository list (name only, without owner/org prefix)
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_repos_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].name' ;
}

# Get gitea repository full path list (includes owner/org prefix)
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_repos_full_name_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].full_name' ;
}

# Check if gitea organization exists
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if organization exists (prints returned json)
#     - 1 : if organization does not exist
function gitea_has_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/orgs/${org_name}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) organization description
#     (4) organization visibility (optional, default 'public')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization description as 3th argument" && return 2 || local org_description="${3}" ;
  [[ -z "${4}" ]] && local org_visibility="public" || local org_visibility="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  if $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea organization '${org_name}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs" \
      -d "{ \"name\": \"${org_name}\", \"username\": \"${org_name}\", \"description\": \"${org_description}\", \"visibility\": \"${org_visibility}\"}" | jq ;
    print_info "Created organization '${org_name}' with username '${org_name}'" ;
  fi
}

# Delete gitea organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  if $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/orgs/${org_name}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea organization '${org_name}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea organization '${org_name}'" ;
  else
    echo "Gitea organization '${org_name}' does not exists" ;
  fi
}

# Get gitea organization list
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_org_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/orgs?limit=100" | jq -r '.[].name' ;
}

# Delete all gitea organizations
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_orgs {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  for org in $(gitea_get_org_list "${base_url}" "${basic_auth}"); do
    gitea_delete_org "${base_url}" "${org}" "${basic_auth}" ;
  done
}

# Delete all gitea repositories
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_repos {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  for repo_full_name in $(gitea_get_repos_full_name_list "${base_url}" "${basic_auth}"); do
    repo_owner=$(echo "${repo_full_name}" | cut -d '/' -f1) ;
    repo_name=$(echo "${repo_full_name}" | cut -d '/' -f2) ;
    gitea_delete_repo "${base_url}" "${repo_owner}" "${repo_name}" "${basic_auth}" ;
  done
}

# Check if gitea user exists
#   args:
#     (1) api url
#     (2) username
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if user exists (prints returned json)
#     - 1 : if user does not exist
function gitea_has_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/users/${username}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea user
#   args:
#     (1) api url
#     (2) username
#     (3) password
#     (4) email (optional, default 'username@gitea.local')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide password as 3rd argument" && return 2 || local password="${3}" ;
  [[ -z "${4}" ]] && local email="${username}@gitea.local" || local email="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  if $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    echo "Gitea user '${username}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/admin/users" \
      -d "{ \"username\": \"${username}\", \"password\": \"${password}\", \"email\": \"${email}\", \"must_change_password\": false}" | jq ;
    print_info "Created user '${username}' with password '${password}' and email '${email}'" ;
  fi
}

# Delete gitea user
#   args:
#     (1) api url
#     (2) username
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  if $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/admin/users/${username}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea user '${username}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea user '${username}'" ;
  else
    print_error "Gitea user '${username}' does not exists" ;
  fi
}

# Get gitea user list
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_user_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/admin/users?limit=100" | jq -r '.[].username' ;
}

# Delete all gitea users
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_users {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  for user in $(gitea_get_user_list "${base_url}" "${basic_auth}"); do
    gitea_delete_user "${base_url}" "${user}" "${basic_auth}" ;
  done
}

# Check if gitea organization team exists
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if organization team exists (prints returned json)
#     - 1 : if organization team does not exist
function gitea_has_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/orgs/${org_name}/teams" | \
                jq -e ".[] | select(.name==\"${team_name}\")" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) team description
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team description as 4th argument" && return 2 || local team_description="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  if $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea team '${team_name}' already exists in organization '${org_name}'" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs/${org_name}/teams" \
      -d "{ \"name\": \"${team_name}\", \"organization\": \"${org_name}\", \"description\": \"${team_description}\", \"permission\": \"admin\"}" | jq ;
    print_info "Created team '${team_name}' in organization '${org_name}'" ;
  fi
}

# Delete gitea organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if team=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}"); then
    team_id=$(echo ${team} | jq ".id") ;
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/teams/${team_id}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea team '${team_name}' (team_id=${team_id}) in organization '${org_name}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea team '${team_name}' in organization '${org_name}'" ;
  else
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exists" ;
  fi
}

# Get gitea organization team list
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_org_team_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/orgs/${org_name}/teams?limit=100" | jq -r '.[].name' ;
}

# Delete all gitea organization teams
#   args:
#     (1) api url
#     (2) organization name
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_org_teams {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  for team in $(gitea_get_org_team_list "${base_url}" "${org_name}" "${basic_auth}"); do
    gitea_delete_org_team "${base_url}" "${org_name}" "${team}" "${basic_auth}" ;
  done
}

# Add gitea user as member to organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) username
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_user_to_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if (curl --fail --silent --request PUT --user "${basic_auth}" \
           --header 'Content-Type: application/json' \
           --url "${base_url}/api/v1/teams/${team_id}/members/${username}") ; then
    print_info "Added user '${username}' to team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to add user '${username}' to team '${team_name} in organization '${org_name}'" ;
  fi
}

# Remove gitea user as member from organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) username
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_user_from_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if (curl --fail --silent --request DELETE --user "${basic_auth}" \
           --header 'Content-Type: application/json' \
           --url "${base_url}/api/v1/teams/${team_id}/members/${username}") ; then
    print_info "Removed user '${username}' from team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to remove user '${username}' from team '${team_name} in organization '${org_name}'" ;
  fi
}

# Add gitea repository to organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) repository name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_repo_to_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/teams/${team_id}/repos/${org_name}/${repo_name}") ; then
    print_info "Added repository '${repo_name}' to team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to add repository '${repo_name}' to team '${team_name} in organization '${org_name}'" ;
  fi
}

# Remove gitea repository from organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) repository name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_repo_from_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/teams/${team_id}/repos/${org_name}/${repo_name}") ; then
    print_info "Removed repository '${repo_name}' from team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to remove repository '${repo_name}' from team '${team_name} in organization '${org_name}'" ;
  fi
}

# Add gitea collaborator to repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (3) username
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_collaborator_to_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repo owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}/collaborators/${username}" \
            -d "{ \"permission\": \"admin\"}"); then
    print_info "Added collaborator '${username}' to repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    print_error "Failed to add collaborator '${username}' to repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Remove gitea collaborator from repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (3) username
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_collaborator_from_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repo owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}/collaborators/${username}"); then
    print_info "Removed collaborator '${username}' from repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    print_error "Failed to remove collaborator '${username}' from repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Add gitea organization team to repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) organization name
#     (4) team name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_org_team_to_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization name as 3th argument" && return 2 || local org_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team name as 4th argument" && return 2 || local team_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${org_name}/${repo_name}/teams/${team_name}"); then
    print_info "Added team '${team_name}' to repository '${repo_name}' in organization '${org_name}'" ;
  else
    print_error "Failed to add team '${team_name}' to repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Remove gitea organization team from repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) organization name
#     (4) team name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_org_team_from_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization name as 4th argument" && return 2 || local org_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team name as 5th argument" && return 2 || local team_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${org_name}/${repo_name}/teams/${team_name}") ; then
    print_info "Removed team '${team_name}' from repository '${repo_name}' in organization '${org_name}'" ;
  else
    print_error "Failed to remove team '${team_name}' from repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Create gitea configuration objets from a json file
#   args:
#     (1) api url
#     (2) configuration file
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_from_json_file {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide config file as 1st argument" && return 2 || local config_file="${2}" ;
  [[ ! -f "${2}" ]] && print_error "Config file does not exist" && return 2 || local config_file="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  user_count=$(jq '.users | length' ${config_file}) ;
  for ((user_index=0; user_index<${user_count}; user_index++)); do
    user_name=$(jq -r '.users['${user_index}'].name' ${config_file}) ;
    user_password=$(jq -r '.users['${user_index}'].password' ${config_file}) ;
    print_info "Going to create user with username '${user_name}' and password '${user_password}'" ;
    gitea_create_user "${base_url}" "${user_name}" "${user_password}" "${user_name}@gitea.local" "${basic_auth}" ;
  done

  org_count=$(jq '.organizations | length' ${config_file})
  for ((org_index=0; org_index<${org_count}; org_index++)); do
    org_description=$(jq -r '.organizations['${org_index}'].description' ${config_file}) ;
    org_name=$(jq -r '.organizations['${org_index}'].name' ${config_file}) ;
    print_info "Going to create organization with name '${org_name}' and description '${org_description}'" ;
    gitea_create_org "${base_url}" "${org_name}" "${org_description}" "${basic_auth}" ;

    org_repo_count=$(jq '.organizations['${org_index}'].repositories | length' ${config_file}) ;
    for ((org_repo_index=0; org_repo_index<${org_repo_count}; org_repo_index++)); do
      org_repo_description=$(jq -r '.organizations['${org_index}'].repositories['${org_repo_index}'].description' ${config_file}) ;
      org_repo_name=$(jq -r '.organizations['${org_index}'].repositories['${org_repo_index}'].name' ${config_file}) ;
      print_info "Going to create repository with name '${org_repo_name}' and description '${org_repo_description}' in organization '${org_name}'" ;
      gitea_create_repo_in_org "${base_url}" "${org_name}" "${org_repo_name}" "${org_repo_description}" "${basic_auth}" ;
    done

    team_count=$(jq '.organizations['${org_index}'].teams | length' ${config_file}) ;
    for ((team_index=0; team_index<${team_count}; team_index++)); do
      team_description=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].description' ${config_file}) ;
      team_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].name' ${config_file}) ;
      print_info "Going to create organization team with name '${team_name}' and description '${team_description}'" ;
      gitea_create_org_team "${base_url}" "${org_name}" "${team_name}" "${team_description}" "${basic_auth}" ;

      team_member_count=$(jq '.organizations['${org_index}'].teams['${team_index}'].members | length' ${config_file}) ;
      for ((team_member_index=0; team_member_index<${team_member_count}; team_member_index++)); do
        team_member_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].members['${team_member_index}']' ${config_file}) ;
        print_info "Going to add user '${team_member_name}' as member to team '${team_name}' in organization '${org_name}'" ;
        gitea_add_user_to_org_team "${base_url}" "${org_name}" "${team_name}" "${team_member_name}" "${basic_auth}" ;
      done

      team_repo_count=$(jq '.organizations['${org_index}'].teams['${team_index}'].repositories | length' ${config_file}) ;
      for ((team_repo_index=0; team_repo_index<${team_repo_count}; team_repo_index++)); do
        team_repo_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].repositories['${team_repo_index}']' ${config_file}) ;
        print_info "Going to add repository '${team_repo_name}' from organization '${org_name}' to team '${team_name}' in organization '${org_name}'" ;
        gitea_add_repo_to_org_team "${base_url}" "${org_name}" "${team_name}" "${team_repo_name}" "${basic_auth}" ;
      done
    done
  done
}


# Delete gitea configuration objets from a json file
#   args:
#     (1) api url
#     (2) configuration file
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_from_json_file {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide config file as 1st argument" && return 2 || local config_file="${2}" ;
  [[ ! -f "${2}" ]] && print_error "Config file does not exist" && return 2 || local config_file="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${3}" ;

  org_count=$(jq '.organizations | length' ${config_file})
  for ((org_index=0; org_index<${org_count}; org_index++)); do
    org_name=$(jq -r '.organizations['${org_index}'].name' ${config_file}) ;

    team_count=$(jq '.organizations['${org_index}'].teams | length' ${config_file}) ;
    for ((team_index=0; team_index<${team_count}; team_index++)); do
      team_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].name' ${config_file}) ;

      team_member_count=$(jq '.organizations['${org_index}'].teams['${team_index}'].members | length' ${config_file}) ;
      for ((team_member_index=0; team_member_index<${team_member_count}; team_member_index++)); do
        team_member_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].members['${team_member_index}']' ${config_file}) ;
        print_info "Going to remove user '${team_member_name}' as member to team '${team_name}' in organization '${org_name}'" ;
        gitea_remove_user_from_org_team "${base_url}" "${org_name}" "${team_name}" "${team_member_name}" "${basic_auth}" ;
      done

      team_repo_count=$(jq '.organizations['${org_index}'].teams['${team_index}'].repositories | length' ${config_file}) ;
      for ((team_repo_index=0; team_repo_index<${team_repo_count}; team_repo_index++)); do
        team_repo_name=$(jq -r '.organizations['${org_index}'].teams['${team_index}'].repositories['${team_repo_index}']' ${config_file}) ;
        print_info "Going to remove repository '${team_repo_name}' from organization '${org_name}' to team '${team_name}' in organization '${org_name}'" ;
        gitea_remove_repo_from_org_team "${base_url}" "${org_name}" "${team_name}" "${team_repo_name}" "${basic_auth}" ;
      done

      print_info "Going to delete organization team with name '${team_name}'" ;
      gitea_delete_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" ;
    done

    org_repo_count=$(jq '.organizations['${org_index}'].repositories | length' ${config_file}) ;
    for ((org_repo_index=0; org_repo_index<${org_repo_count}; org_repo_index++)); do
      org_repo_name=$(jq -r '.organizations['${org_index}'].repositories['${org_repo_index}'].name' ${config_file}) ;
      print_info "Going to delete repository with name '${org_repo_name}' in organization '${org_name}'" ;
      gitea_delete_repo "${base_url}" "${org_name}" "${org_repo_name}" "${basic_auth}" ;
    done

    print_info "Going to delete organization with name '${org_name}'" ;
    gitea_delete_org "${base_url}" "${org_name}" "${basic_auth}" ;
  done

  user_count=$(jq '.users | length' ${config_file}) ;
  for ((user_index=0; user_index<${user_count}; user_index++)); do
    user_name=$(jq -r '.users['${user_index}'].name' ${config_file}) ;
    print_info "Going to delete user with username '${user_name}'" ;
    gitea_delete_user "${base_url}" "${user_name}" "${basic_auth}" ;
  done
}
