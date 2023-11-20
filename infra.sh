#!/usr/bin/env bash
BASE_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${BASE_DIR}/env.sh ${BASE_DIR} ;
source ${BASE_DIR}/helpers.sh ;
source ${BASE_DIR}/k8s-local.sh ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  - up: bring up the local instrastructure" ;
  echo "  - down: bring down the local instrastructure" ;
  echo "  - info: print info about the local instrastructure" ;
  echo "  - clean: remove the local instrastructure" ;
}

# This function brings up the local instrastructure.
#
function up() {

  ######################## mp cluster ########################
  local install_repo_url=$(get_install_repo_url) ;
  local mp_cluster_name=$(get_mp_name) ;
  local mp_cluster_region=$(get_mp_region) ;
  local mp_cluster_zone=$(get_mp_zone) ;
  local mp_k8s_provider=$(get_mp_k8s_provider) ;
  local mp_k8s_version=$(get_mp_k8s_version) ;
  local mp_vm_count=$(get_mp_vm_count) ;

  # Start kubernetes management cluster
  start_cluster "${mp_k8s_provider}" "${mp_cluster_name}" "${mp_k8s_version}" "${mp_cluster_name}" "" "${install_repo_url}" ;
  wait_cluster_ready "${mp_k8s_provider}" "${mp_cluster_name}" ;

  # Add nodes labels for locality based routing (region and zone)
  for node_name in $(kubectl --context ${mp_cluster_name} get nodes -o custom-columns=":metadata.name" --no-headers=true); do
    if ! kubectl --context ${mp_cluster_name} get node ${node_name} --show-labels | grep "topology.kubernetes.io/region=${mp_cluster_region}" &>/dev/null ; then
      kubectl --context ${mp_cluster_name} label node ${node_name} topology.kubernetes.io/region=${mp_cluster_region} --overwrite=true ;
    fi
    if ! kubectl --context ${mp_cluster_name} get node ${node_name} --show-labels | grep "topology.kubernetes.io/zone=${mp_cluster_zone}" &>/dev/null ; then
      kubectl --context ${mp_cluster_name} label node ${node_name} topology.kubernetes.io/zone=${mp_cluster_zone} --overwrite=true ;
    fi
  done

  # Spin up vms that belong to the management cluster
  if [[ ${mp_vm_count} -eq 0 ]] ; then
    echo "Skipping vm start-up: no vms attached to management cluster ${mp_cluster_name}" ;
  else
    local mp_vm_index=0 ;
    while [[ ${mp_vm_index} -lt ${mp_vm_count} ]]; do
      vm_image=$(get_mp_vm_image_by_index ${mp_vm_index}) ;
      vm_name=$(get_mp_vm_name_by_index ${mp_vm_index}) ;
      if docker ps --filter "status=running" | grep ${vm_name} &>/dev/null ; then
        echo "Do nothing, vm ${vm_name} for management cluster ${mp_cluster_name} is already running" ;
      elif docker ps --filter "status=exited" | grep ${vm_name} &>/dev/null ; then
        print_info "Going to start vm ${vm_name} for management cluster ${mp_cluster_name} again" ;
        docker start ${vm_name} ;
      else
        print_info "Going to start vm ${vm_name} for management cluster ${mp_cluster_name} for the first time" ;
        docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${mp_cluster_name} --hostname ${vm_name} --name ${vm_name} ${vm_image} ;
      fi
      mp_vm_index=$((mp_vm_index+1)) ;
    done
  fi

  # Disable iptables docker isolation for cluster to private repo communication
  # https://serverfault.com/questions/1102209/how-to-disable-docker-network-isolation
  # https://serverfault.com/questions/830135/routing-among-different-docker-networks-on-the-same-host-machine 
  echo "Flushing docker isolation iptable rules to allow ${mp_cluster_name} cluster to docker repo communication" ;
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;

  ######################## cp clusters ########################
  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    local cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    local cp_cluster_region=$(get_cp_region_by_index ${cp_index}) ;
    local cp_cluster_zone=$(get_cp_zone_by_index ${cp_index}) ;
    local cp_k8s_provider=$(get_cp_k8s_provider_by_index ${cp_index}) ;
    local cp_k8s_version=$(get_cp_k8s_version_by_index ${cp_index}) ;
    local cp_vm_count=$(get_cp_vm_count_by_index ${cp_index}) ;

    # Start kubernetes application cluster
    start_cluster "${cp_k8s_version}" "${cp_cluster_name}" "${cp_k8s_version}" "${cp_cluster_name}" "" "${install_repo_url}" ;
    wait_cluster_ready "${cp_k8s_version}" "${cp_cluster_name}" ;

    # Add nodes labels for locality based routing (region and zone)
    for node_name in $(kubectl --context ${cp_cluster_name} get nodes -o custom-columns=":metadata.name" --no-headers=true); do
      if ! kubectl --context ${cp_cluster_name} get node ${node_name} --show-labels | grep "topology.kubernetes.io/region=${cp_cluster_region}" &>/dev/null ; then
        kubectl --context ${cp_cluster_name} label node ${node_name} topology.kubernetes.io/region=${cp_cluster_region} --overwrite=true ;
      fi
      if ! kubectl --context ${cp_cluster_name} get node ${node_name} --show-labels | grep "topology.kubernetes.io/zone=${cp_cluster_zone}" &>/dev/null ; then
        kubectl --context ${cp_cluster_name} label node ${node_name} topology.kubernetes.io/zone=${cp_cluster_zone} --overwrite=true ;
      fi
    done

    # Spin up vms that belong to this application cluster
    if [[ ${cp_vm_count} -eq 0 ]] ; then
      echo "Skipping vm start-up: no vms attached to application cluster ${cp_cluster_name}" ;
    else
      local cp_vm_index=0 ;
      while [[ ${cp_vm_index} -lt ${cp_vm_count} ]]; do
        local vm_image=$(get_cp_vm_image_by_index ${cp_index} ${cp_vm_index}) ;
        local vm_name=$(get_cp_vm_name_by_index ${cp_index} ${cp_vm_index}) ;
        if docker ps --filter "status=running" | grep ${vm_name} &>/dev/null ; then
          echo "Do nothing, vm ${vm_name} for application cluster ${cp_cluster_name} is already running" ;
        elif docker ps --filter "status=exited" | grep ${vm_name} &>/dev/null ; then
          print_info "Going to start vm ${vm_name} for application cluster ${cp_cluster_name} again" ;
          docker start ${vm_name} ;
        else
          print_info "Going to start vm ${vm_name} for application cluster ${cp_cluster_name} for the first time" ;
          docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${cp_cluster_name} --hostname ${vm_name} --name ${vm_name} ${vm_image} ;
        fi
        cp_vm_index=$((cp_vm_index+1)) ;
      done
    fi
    cp_index=$((cp_index+1)) ;
  done

  # Disable iptables docker isolation for cross cluster and cluster to private repo communication
  if [[ ${cp_count} -gt 0 ]]; then
    # https://serverfault.com/questions/1102209/how-to-disable-docker-network-isolation
    # https://serverfault.com/questions/830135/routing-among-different-docker-networks-on-the-same-host-machine 
    echo "Flushing docker isolation iptable rules to allow cross cluster and ${cp_cluster_name} cluster to private docker repo communication" ;
    sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 ;
  fi

  print_info "All kubernetes clusters and vms started" ;
}

# This function brings down the local instrastructure.
#
function down() {

  # Stop kubernetes clusters
  local mp_cluster_name=$(get_mp_name) ;
  local mp_k8s_provider=$(get_mp_k8s_provider) ;
  print_info "Going to stop management cluster '${mp_cluster_name}'" ;
  stop_cluster "${mp_k8s_provider}" "${mp_cluster_name}" ;

  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_k8s_provider=$(get_cp_k8s_provider_by_index ${cp_index}) ;
    print_info "Going to stop application cluster '${cp_cluster_name}'" ;
    stop_cluster "${cp_k8s_provider}" "${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done

  # Management plane VMs
  local mp_vm_count=$(get_mp_vm_count) ;
  if ! [[ ${mp_vm_count} -eq 0 ]] ; then
    mp_cluster_name=$(get_mp_name) ;
    mp_vm_index=0 ;
    while [[ ${mp_vm_index} -lt ${mp_vm_count} ]]; do
      vm_name=$(get_mp_vm_name_by_index ${mp_vm_index}) ;
      print_info "Going to stop vm ${vm_name} attached to management cluster ${mp_cluster_name}" ;
      docker stop ${vm_name} ;
      mp_vm_index=$((mp_vm_index+1)) ;
    done
  fi

  # Control plane VMs
  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_vm_count=$(get_cp_vm_count_by_index ${cp_index}) ;
    if ! [[ ${cp_vm_count} -eq 0 ]] ; then
      cp_vm_index=0 ;
      while [[ ${cp_vm_index} -lt ${cp_vm_count} ]]; do
        vm_name=$(get_cp_vm_name_by_index ${cp_index} ${cp_vm_index}) ;
        print_info "Going to stop vm ${vm_name} attached to application cluster ${cp_cluster_name}" ;
        docker stop ${vm_name} ;
        cp_vm_index=$((cp_vm_index+1)) ;
      done
    fi
    cp_index=$((cp_index+1)) ;
  done

  print_info "All kubernetes clusters and vms stopped" ;
}

# This function prints info about the local instrastructure.
#
function info() {

  local mp_cluster_name=$(get_mp_name) ;
  if ! kubectl config get-contexts ${mp_cluster_name} &>/dev/null ; then
    kubectl config get-contexts ;
    docker ps ;
    print_error "No kubernetes context \"${mp_cluster_name}\" found... topology in configured env.json is not running." ;
    exit 0 ;
  fi  

  local tsb_api_endpoint=$(kubectl --context ${mp_cluster_name} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  print_info "Running docker containers:" ;
  docker ps ;
  echo "" ;

  print_info "Management plane cluster ${mp_cluster_name}:" ;
  echo "TSB GUI: https://${tsb_api_endpoint}:8443 (admin/admin)" ;
  echo "TSB GUI (port-fowarded): https://$(curl -s ifconfig.me):8443 (admin/admin)" ;
  print_command "kubectl --context ${mp_cluster_name} get pods -A" ;

  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    echo "" ;
    print_info "Control plane cluster ${cp_cluster_name}:" ;
    print_command "kubectl --context ${cp_cluster_name} get pods -A" ;
    cp_index=$((cp_index+1)) ;
  done

  # Management plane VMs
  local mp_vm_count=$(get_mp_vm_count) ;
  if ! [[ ${mp_vm_count} -eq 0 ]] ; then
    mp_cluster_name=$(get_mp_name) ;
    echo "" ;
    print_info "VMs attached to management cluster ${mp_cluster_name}:" ;
    mp_vm_index=0 ;
    while [[ ${mp_vm_index} -lt ${mp_vm_count} ]]; do
      vm_name=$(get_mp_vm_name_by_index ${mp_vm_index}) ;
      vm_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${vm_name}) ;
      echo "${vm_name} has ip address ${vm_ip}" ;
      print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip}" ;
      mp_vm_index=$((mp_vm_index+1)) ;
    done
  fi

  # Control plane VMs
  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_vm_count=$(get_cp_vm_count_by_index ${cp_index}) ;
    if ! [[ ${cp_vm_count} -eq 0 ]] ; then
      echo "" ;
      print_info "VMs attached to application cluster ${cp_cluster_name}:" ;
      cp_vm_index=0 ;
      while [[ ${cp_vm_index} -lt ${cp_vm_count} ]]; do
        vm_name=$(get_cp_vm_name_by_index ${cp_index} ${cp_vm_index}) ;
        vm_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${vm_name}) ;
        echo "${vm_name} has ip address ${vm_ip}" ;
        print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip}" ;
        cp_vm_index=$((cp_vm_index+1)) ;
      done
    fi
    cp_index=$((cp_index+1)) ;
  done
}

# This function removes the local instrastructure.
#
function clean() {

  # Management plane VMs
  local mp_vm_count=$(get_mp_vm_count) ;
  if ! [[ ${mp_vm_count} -eq 0 ]] ; then
    mp_cluster_name=$(get_mp_name) ;
    mp_vm_index=0 ;
    while [[ ${mp_vm_index} -lt ${mp_vm_count} ]]; do
      vm_name=$(get_mp_vm_name_by_index ${mp_vm_index}) ;
      print_info "Going to delete vm ${vm_name} attached to management cluster ${mp_cluster_name}" ;
      docker stop ${vm_name} ;
      docker rm ${vm_name} ;
      mp_vm_index=$((mp_vm_index+1)) ;
    done
  fi

  # Control plane VMs
  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_vm_count=$(get_cp_vm_count_by_index ${cp_index}) ;
    if ! [[ ${cp_vm_count} -eq 0 ]] ; then
      cp_vm_index=0 ;
      while [[ ${cp_vm_index} -lt ${cp_vm_count} ]]; do
        vm_name=$(get_cp_vm_name_by_index ${cp_index} ${cp_vm_index}) ;
        print_info "Going to delete vm ${vm_name} attached to application cluster ${cp_cluster_name}" ;
        docker stop ${vm_name} ;
        docker rm ${vm_name} ;
        cp_vm_index=$((cp_vm_index+1)) ;
      done
    fi
    cp_index=$((cp_index+1)) ;
  done

  # Delete kubernetes cluster
  local mp_cluster_name=$(get_mp_name) ;
  local mp_k8s_provider=$(get_mp_k8s_provider) ;
  print_info "Going to delete management cluster '${mp_cluster_name}'" ;
  remove_cluster "${mp_k8s_provider}" "${mp_cluster_name}" "${mp_cluster_name}" ;

  local cp_count=$(get_cp_count) ;
  local cp_index=0 ;
  while [[ ${cp_index} -lt ${cp_count} ]]; do
    cp_cluster_name=$(get_cp_name_by_index ${cp_index}) ;
    cp_k8s_provider=$(get_cp_k8s_provider_by_index ${cp_index}) ;
    print_info "Going to delete application cluster '${cp_cluster_name}'" ;
    remove_cluster "${cp_k8s_provider}" "${cp_cluster_name}" "${cp_cluster_name}" ;
    cp_index=$((cp_index+1)) ;
  done

  print_info "All kubernetes clusters and vms deleted" ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --up)
    print_stage "Going to bring up the local instrastructure" ;
    up ;
    ;;
  --down)
    print_stage "Going to bring down the local instrastructure" ;
    down ;
    ;;
  --info)
    print_stage "Going to print info about the local instrastructure" ;
    info ;
    ;;
  --clean)
    print_stage "Going to remove the local instrastructure" ;
    clean ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac