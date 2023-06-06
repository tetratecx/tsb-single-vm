#!/usr/bin/env bash
#
# Helper functions for gitea API actions
#


# Get gitlab version
#   args:
#     (1) gitea api url
#     (2) gitea username
#     (3) gitea password
function gitea_get_version {
  [[ -z "${1}" ]] && echo "Please provide gitea api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitea username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitea password as 3rd argument" && return 2 || local password="${3}" ;

  curl --fail --silent --request GET --user "${username}:${password}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/version"
}

# Create gitea repository
#   args:
#     (1) gitea api url
#     (2) gitea username
#     (3) gitea password
#     (4) gitea repository name
#     (5) gitea repository user
function gitea_get_repo_from_user {
  [[ -z "${1}" ]] && echo "Please provide gitea api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitea username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitea password as 3rd argument" && return 2 || local password="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitea repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && echo "Please provide gitea repository user as 5th argument" && return 2 || local repo_user="${5}" ;

  curl --fail --silent --request GET --user "${username}:${password}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/${repo_user}/${repo_name}" ;
}

# Create gitea repository
#   args:
#     (1) gitea api url
#     (2) gitea username
#     (3) gitea password
#     (4) gitea repository name
#     (5) gitea repository description
function gitea_create_repo {
  [[ -z "${1}" ]] && echo "Please provide gitea api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitea username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitea password as 3rd argument" && return 2 || local password="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitea repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && echo "Please provide gitea repository description as 5th argument" && return 2 || local repo_description="${5}" ;

  if $(gitea_get_repo_from_user "${base_url}" "${username}" "${password}" "${repo_name}" "${username}"); then
    echo "Gitea repository '${repo_name}' for user '${username}' already exists"
  else
    curl --fail --silent --request POST --user "${username}:${password}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/user/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": false}" ;
  fi
}

# Get gitlab project full path list
#   args:
#     (1) gitea api url
#     (2) gitea username
#     (3) gitea password
function gitea_get_repos_full_name_list {
  [[ -z "${1}" ]] && echo "Please provide gitea api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitea username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitea password as 3rd argument" && return 2 || local password="${3}" ;

  curl --fail --silent --request GET --user "${username}:${password}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].full_name'
}
