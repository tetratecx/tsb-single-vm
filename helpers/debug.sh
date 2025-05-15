#!/usr/bin/env bash
#
# Helper functions for debugging
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;

# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

function docker_remove_isolation() {
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2
}

function restart_clusters_cps() {
  if [ -z "${1}" ]]; then
    print_warning "Please provide cluster names array as 1st argument. Using default ( c1 c2 t1 )" \
      || local clusters=( c1 c2 t1 ) ;
  else
    local clusters=("${1[@]}")
  fi

  for cluster in "${clusters[@]}"
  do
    kubectl rollout restart deploy edge tsb-operator-control-plane oap-deployment xcp-operator-edge \
      -n istio-system --context "$cluster"
    sleep 5;
  done
}

# TODO: receive as arg the MP cluster name
function tctl_fix_timeout {
  tctl config profiles set-current tsb-profile
  tctl config clusters set t1 --timeout 30s
}