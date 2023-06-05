#!/usr/bin/env bash
#
# Helper functions for gitlab API actions
#

# Set gitlab user token
#   args:
#     (1) gitlab container name
#     (2) gitlab api url
#     (3) gitlab root api token
function gitlab_set_root_api_token {
  [[ -z "${1}" ]] && echo "Please provide gitlab container name as 1st argument" && return 2 || local container_name="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api url as 2nd argument" && return 2 || local base_url="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab root api token as 3rd argument" && return 2 || local api_token="${3}" ;
  if [[ $(curl --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" --header 'Content-Type: application/json' --url "${base_url}/api/v4/metadata" -w "%{http_code}" -o /dev/null) == "200" ]] ; then
    echo "Gitlab root api token already configured and working"
  else
    echo "Going to configure gitlab root api token"
    docker exec ${container_name} gitlab-rails runner \
      "token = User.find_by_username('root').personal_access_tokens.create(scopes: [:api, :sudo], name: 'Root API Token'); 
       token.set_token('${api_token}');
       token.save"
  fi
}

# Set gitlab shared runner token
#   args:
#     (1) gitlab container name
function gitlab_get_shared_runner_token {
  [[ -z "${1}" ]] && echo "Please provide gitlab container name as 1st argument" && return 2 || local container_name="${1}" ;
  docker exec -it ${container_name} gitlab-rails runner "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token"
}

# Get gitlab shared runner id
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (2) gitlab runner description
function gitlab_get_shared_runner_id {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab runner description as 3rd argument" && return 2 || local runner_description="${3}" ;
  curl --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v4/runners/all?type=instance_type" | jq ".[] | select(.description==\"${runner_description}\")" | jq -r '.id'
}

# Get gitlab group id
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group name
#     (4) gitlab group path
function gitlab_get_group_id {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group name as 3rd argument" && return 2 || local group_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab group path as 4th argument" && return 2 || local group_path="${4}" ;
  curl --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v4/groups?per_page=100" | jq ".[] | select(.name==\"${group_name}\") | select(.full_path==\"${group_path}\")" | jq -r '.id'
}

# Get gitlab groups full path list
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
function gitlab_get_groups_full_path_list {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  curl --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v4/groups?per_page=100" | jq -r '.[].full_path'
}

# Check if gitlab group with full path already exists
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group path
#   returns:
#     - 0 if found
#     - 1 if not found
function gitlab_has_group_full_path {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group path as 3rd argument" && return 2 || local group_path="${3}" ;
  gitlab_get_groups_full_path_list "${base_url}" "${api_token}" | grep "${group_path}" &>/dev/null
}

# Create gitlab group
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group name
#     (4) gitlab group path
#     (5) gitlab group description
function gitlab_create_group {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group name as 3rd argument" && return 2 || local group_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab group path as 4th argument" && return 2 || local group_path="${4}" ;
  [[ -z "${5}" ]] && echo "Please provide gitlab group description as 5th argument" && return 2 || local group_description="${5}" ;
  group_id=$(gitlab_get_group_id ${base_url} ${api_token} ${group_name} ${group_path})

  if [[ ${group_id} == "" ]] ; then
    if [[ "${group_name}" == "${group_path}" ]] ; then
      # Toplevel group
      echo "Going to create toplevel gitlab group '${group_name}'"
      response=`curl --url "${base_url}/api/v4/groups" --silent --request POST --header "PRIVATE-TOKEN: ${api_token}" \
        --header "Content-Type: application/json" \
        --data @- <<BODY
{
  "description": "${group_description}",
  "path": "${group_name}",
  "name": "${group_name}",
  "visibility": "public"
}
BODY`

      echo ${response} | jq
    else
      # Subgroup
      parent_group_path=$(echo ${group_path} | rev | cut -d"/" -f2-  | rev)
      parent_group_name=$(echo ${parent_group_path} | rev | cut -d"/" -f1  | rev)
      parent_group_id=$(gitlab_get_group_id ${base_url} ${api_token} ${parent_group_name} ${parent_group_path})

      if [[ ${parent_group_id} == "" ]] ; then
        echo "Gitlab parent group '${parent_group_name}' with path '${parent_group_path}' does not exist"
      else
        echo "Going to create gitlab subgroup '${group_name}' in path '${parent_group_path}'"
        response=`curl --url "${base_url}/api/v4/groups" --silent --request POST --header "PRIVATE-TOKEN: ${api_token}" \
          --header "Content-Type: application/json" \
          --data @- <<BODY
{
  "description": "${group_description}",
  "parent_id": "${parent_group_id}",
  "path": "${group_name}",
  "name": "${group_name}",
  "visibility": "public"
}
BODY`

        echo ${response} | jq
      fi
    fi
  else
    echo "Gitlab group with name '${3}' and path '${4}' already exists (group_id: ${group_id})"
  fi
}

# Get gitlab project id in group
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group path
#     (4) gitlab project name
function gitlab_get_project_id_in_group_path {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group path as 3rd argument" && return 2 || local group_path="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab project name as 4th argument" && return 2 || local project_name="${4}" ;
  curl --url "${base_url}/api/v4/projects?per_page=100" --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    | jq ".[] | select(.name==\"${project_name}\") | select(.namespace.full_path==\"${group_path}\")" | jq -r '.id'
}

# Get gitlab project id without group
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab project name
function gitlab_get_project_id {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab project name as 3rd argument" && return 2 || local project_name="${3}" ;
  curl --url "${base_url}/api/v4/projects?per_page=100" --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    | jq ".[] | select(.name==\"${project_name}\")" | jq -r '.id'
}

# Get gitlab project full path list
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
function gitlab_get_projects_full_path_list {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  curl --silent --request GET --header "PRIVATE-TOKEN: ${api_token}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v4/projects?per_page=100" | jq -r '.[].path_with_namespace'
}

# Check if gitlab project with full path already exists
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group path
#     (4) gitlab project name
#   returns:
#     - 0 if found
#     - 1 if not found
function gitlab_has_project_full_path {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group path as 3rd argument" && return 2 || local group_path="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab project name as 4th argument" && return 2 || local project_name="${4}" ;
  gitlab_get_projects_full_path_list "${base_url}" "${api_token}" | grep "${group_path}/${project_name}" &>/dev/null
}

# Create gitlab project
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab group path
#     (4) gitlab project name
#     (5) gitlab project description
function gitlab_create_project_in_group_path {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab group path as 3rd argument" && return 2 || local group_path="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab project name as 4th argument" && return 2 || local project_name="${4}" ;
  [[ -z "${5}" ]] && echo "Please provide gitlab project description as 5th argument" && return 2 || local project_description="${5}" ;
  group_name=$(echo ${group_path} | rev | cut -d"/" -f1  | rev)
  group_id=$(gitlab_get_group_id ${base_url} ${api_token} ${group_name} ${group_path})

  if [[ ${group_id} == "" ]] ; then
    echo "Gitlab group '${group_name}' with path '${group_path}' does not exist"
  else
    project_id=$(gitlab_get_project_id_in_group_path ${base_url} ${api_token} ${group_path} ${project_name})
    if [[ ${project_id} == "" ]]; then
      echo "Going to create gitlab project '${project_name}' in group with path '${group_path}'"
      response=`curl --url "${base_url}/api/v4/projects" --silent --request POST --header "PRIVATE-TOKEN: ${api_token}" \
        --header "Content-Type: application/json" \
        --data @- <<BODY
{
  "description": "${project_description}",
  "name": "${project_name}",
  "namespace_id": "${group_id}",
  "path": "${project_name}",
  "visibility": "public"
}
BODY`

      echo ${response} | jq
    else
      echo "Gitlab project '${project_name}' (project_id: ${project_id}) already exists in group with path '${group_path}' (group_id: ${group_id})"
    fi
  fi
}

# Create gitlab project
#   args:
#     (1) gitlab api url
#     (2) gitlab api token
#     (3) gitlab project name
#     (4) gitlab project description
#     (5) gitlab auto devops enabled
function gitlab_create_project {
  [[ -z "${1}" ]] && echo "Please provide gitlab api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && echo "Please provide gitlab api token as 2nd argument" && return 2 || local api_token="${2}" ;
  [[ -z "${3}" ]] && echo "Please provide gitlab project name as 3rd argument" && return 2 || local project_name="${3}" ;
  [[ -z "${4}" ]] && echo "Please provide gitlab project description as 4th argument" && return 2 || local project_description="${4}" ;
  [[ -z "${5}" ]] && echo "Please provide gitlab auto devops enabled as 5th argument" && return 2 || local auto_devops="${5}" ;

  project_id=$(gitlab_get_project_id ${base_url} ${api_token} ${project_name})
  if [[ ${project_id} == "" ]]; then
    echo "Going to create gitlab project '${project_name}'"
    response=`curl --url "${base_url}/api/v4/projects" --silent --request POST --header "PRIVATE-TOKEN: ${api_token}" \
      --header "Content-Type: application/json" \
      --data @- <<BODY
{
"auto_devops_enabled": ${auto_devops},
"description": "${project_description}",
"name": "${project_name}",
"path": "${project_name}",
"visibility": "public"
}
BODY`

    echo ${response} | jq
  else
    echo "Gitlab project '${project_name}' (project_id: ${project_id}) already exists"
  fi
}