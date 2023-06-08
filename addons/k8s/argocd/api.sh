# Helper functions to manage argocd
#

ARGOCD_DEFAULT_ADMIN_PASSWORD="admin-pass"
ARGOCD_DEFAULT_NAMESPACE="argocd"

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

# Set argocd admin password
#   args:
#     (1) cluster context
#     (2) admin password (optional, default 'admin-pass')
#     (3) namespace (optional, default 'argocd')
function argocd_set_admin_password {
  [[ -z "${1}" ]] && print_error "Please provide kubernetes context as 1st argument" && return 2 || local kube_context="${1}" ;
  [[ -z "${2}" ]] && local admin_password="${ARGOCD_DEFAULT_ADMIN_PASSWORD}" || local admin_password="${2}" ;
  [[ -z "${3}" ]] && local argocd_namespace="${ARGOCD_DEFAULT_NAMESPACE}" || local argocd_namespace="${3}" ;

  echo -n "Waiting to fetch argocd initial password: "
  while ! unparsed_initial_password=$(argocd --kube-context ${kube_context} --insecure admin initial-password -n ${argocd_namespace} 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  initial_password=$(echo ${unparsed_initial_password} | cut -d " " -f1) ;
  echo "DONE [initial_password: ${initial_password}]" ;

  argocd_external_ip=$(argocd_get_external_ip ${kube_context} ${argocd_namespace}) ;
  if $(argocd --kube-context ${kube_context} --insecure login ${argocd_external_ip} --username admin --password "${initial_password}" &>/dev/null); then
    echo "Going to change initial password of argocd admin user" ;
    argocd --kube-context ${kube_context} --insecure account update-password --account admin --current-password "${initial_password}" --new-password "${admin_password}" ;
    sleep 2 ;
  fi

  if finished=$(argocd --kube-context ${kube_context} --insecure login "${argocd_external_ip}" --username admin --password "${admin_password}" 2>&1); then
    print_info "Success to login to argocd as admin with password '${admin_password}'" ;
  else
    print_error "Failed to login to argocd as admin with password '${admin_password}'" ;
    print_error "${finished}" ;
    return 1 ;
  fi
}
