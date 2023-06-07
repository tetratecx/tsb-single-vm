# Helper functions to start, stop and remove argocd
#

ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

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

# Deploy argocd in kubernetes
#   args:
#     (1) cluster context
#     (2) namespace (optional, default 'argocd')
function argocd_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubernetes context as 1st argument" && return 2 || local kube_context="${1}" ;
  [[ -z "${2}" ]] && local argocd_namespace="argocd" || local argocd_namespace="${2}" ;

  if $(kubectl --context ${kube_context} get namespace ${argocd_namespace} &>/dev/null) ; then
    echo "Namespace '${argocd_namespace}' already exists" ;
  else
    echo "Creating namespace '${argocd_namespace}' for argocd deployment" ;
    kubectl --context ${kube_context} create namespace ${argocd_namespace} ;
  fi

  echo "Deploying argocd manifest and patching service" ;
  kubectl --context ${kube_context} apply -n ${argocd_namespace} -f ${ARGOCD_MANIFEST} ;
  kubectl --context ${kube_context} patch svc argocd-server -n ${argocd_namespace} -p '{"spec": {"type": "LoadBalancer"}}' ;

  echo -n "Waiting for argocd service to get external loadbalancer ip: "  
  while ! argocd_external_ip=$(argocd_get_external_ip "${kube_context}" "${argocd_namespace}" 2>&1) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE [argocd_external_ip: ${argocd_external_ip}]" ;

  if finished=$(kubectl --context ${kube_context} wait deployment argocd-server -n ${argocd_namespace} --for condition=Available=True --timeout=600s 2>&1); then
    print_info "Successfully deployed argocd in namespace '${argocd_namespace}' of cluster '${kube_context}'" ;
  else
    print_error "Failed to deploy argocd in namespace '${argocd_namespace}' of cluster '${kube_context}'" ;
    print_error "${finished}" ;
    return 1 ;
  fi
}

# Undeploy argocd in kubernetes
#   args:
#     (1) cluster context
#     (2) namespace (optional, default 'argocd')
function argocd_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubernetes context as 1st argument" && return 2 || local kube_context="${1}" ;
  [[ -z "${2}" ]] && local argocd_namespace="argocd" || local argocd_namespace="${2}" ;

  if $(kubectl --context ${kube_context} get namespace ${argocd_namespace} &>/dev/null) ; then 
    kubectl --context ${kube_context} delete -n ${argocd_namespace} -f ${ARGOCD_MANIFEST} ;
    if finished=$(kubectl --context ${kube_context} delete namespace ${argocd_namespace} 2>&1); then
      print_info "Successfully undeployed argocd from namespace '${argocd_namespace}' of cluster '${kube_context}'" ;
    else
      print_error "Failed to undeploy argocd from namespace '${argocd_namespace}' of cluster '${kube_context}'" ;
      print_error "${finished}" ;
      return 1 ;
    fi
  fi
}

# Get argocd external ip address
#   args:
#     (1) cluster context
#     (2) namespace (optional, default 'argocd')
function argocd_get_external_ip {
  [[ -z "${1}" ]] && print_error "Please provide kubernetes context as 1st argument" && return 2 || local kube_context="${1}" ;
  [[ -z "${2}" ]] && local argocd_namespace="argocd" || local argocd_namespace="${2}" ;

  kubectl --context ${kube_context} -n ${argocd_namespace} get svc argocd-server --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

# Set argocd admin password
#   args:
#     (1) cluster context
#     (2) admin password (optional, default 'admin-pass')
#     (3) namespace (optional, default 'argocd')
function argocd_set_admin_password {
  [[ -z "${1}" ]] && print_error "Please provide kubernetes context as 1st argument" && return 2 || local kube_context="${1}" ;
  [[ -z "${2}" ]] && local admin_password="admin-pass" || local admin_password="${2}" ;
  [[ -z "${3}" ]] && local argocd_namespace="argocd" || local argocd_namespace="${3}" ;

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
  fi

  if finished=$(argocd --kube-context ${kube_context} --insecure login "${argocd_external_ip}" --username admin --password "${admin_password}" 2>&1); then
    print_info "Success to login to argocd as admin with password '${admin_password}'" ;
  else
    print_error "Failed to login to argocd as admin with password '${admin_password}'" ;
    print_error "${finished}" ;
    return 1 ;
  fi
}
