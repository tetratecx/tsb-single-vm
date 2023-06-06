# Helper functions to manage gitea (a lightweight git server)
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

# Get gitea repository by name from owner
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if repo exists (prints returned json)
#     - 1 : if repo does not exist
function gitea_has_repo_by_name_from_owner {
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
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository description as 3th argument" && return 2 || local repo_description="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  repo_owner=$(echo ${basic_auth} | cut -d ':' -f1)
  if $(gitea_has_repo_by_name_from_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' already exists"
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/user/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": false}" | jq ;
    print_info "Created repository '${repo_name}' with owner '${repo_owner}'"
  fi
}

# Delete gitea repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${4}" ;

  if $(gitea_has_repo_by_name_from_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    curl --fail --silent --request DELETE --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}" | jq ;
    print_info "Deleted gitea repository '${repo_name}' with owner '${repo_owner}'"
  else
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exists"
  fi
}

# Get gitlab project full path list
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_repos_full_name_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="gitea-admin:gitea-admin" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].full_name'
}
