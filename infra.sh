#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}

# MINIKUBE_OPTS="--driver docker --cpus=6"
MINIKUBE_OPTS="--driver docker --insecure-registry \"192.168.48.0/24\""
CLUSTER_METALLB_STARTIP=100
CLUSTER_METALLB_ENDIP=199

K8S_VERSION=$(get_k8s_version) ;
TSB_REPO_PW=$(get_tsb_repo_password) ;
TSB_REPO_URL=$(get_tsb_repo_url) ;
TSB_REPO_USER=$(get_tsb_repo_user) ;


# Configure metallb start and end IP
#   args:
#     (1) minikube profile name
#     (2) start ip
#     (3) end ip
function configure_metallb {
  expect <<DONE
  spawn minikube --profile ${1} addons configure metallb
  expect "Enter Load Balancer Start IP:" { send "${2}\\r" }
  expect "Enter Load Balancer End IP:" { send "${3}\\r" }
  expect eof
DONE
}

# Patch for minikube metallb addon dependencies to docker.io
#   args:
#     (1) minikube profile name
function patch_metallb_pull_repo {
  CONTROLLER_PATCH='{"spec":{"template":{"spec":{"containers":[{"name":"controller","image":"quay.io/metallb/controller:v0.9.6"}]}}}}'
  SPEAKER_PATCH='{"spec":{"template":{"spec":{"containers":[{"name":"speaker","image":"quay.io/metallb/speaker:v0.9.6"}]}}}}'

  while ! kubectl --context ${1} -n metallb-system get deployment controller ; do sleep 1 ; done
  kubectl --context ${1} -n metallb-system patch deployment controller --patch ${CONTROLLER_PATCH} ;
  while ! kubectl --context ${1} -n metallb-system get daemonset speaker ; do sleep 1 ; done
  kubectl --context ${1} -n metallb-system patch daemonset speaker --patch ${SPEAKER_PATCH} ;
}

# Configure minikube clusters to have access to docker repo containing tsb images
#   args:
#     (1) minikube profile name
function configure_docker_access {
  minikube --profile ${1} ssh -- docker login ${TSB_REPO_URL} --username ${TSB_REPO_USER} --password ${TSB_REPO_PW} &>/dev/null ;
  minikube --profile ${1} ssh -- sudo cp /home/docker/.docker/config.json /var/lib/kubelet ;
  minikube --profile ${1} ssh -- sudo systemctl restart kubelet ;
}


######################## START OF ACTIONS ########################

if [[ ${ACTION} = "up" ]]; then

  ######################## mp cluster ########################
  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  DOCKER_NET=$(get_mp_name) ; 
  CLUSTER_REGION=$(get_mp_region) ;
  CLUSTER_ZONE=$(get_mp_zone) ;
  VM_COUNT=$(get_mp_vm_count) ;

  # Start minikube profile for the management cluster
  if minikube profile list 2>/dev/null | grep ${CLUSTER_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube management cluster profile ${CLUSTER_PROFILE} already running"
  else
    print_info "Starting minikube management cluster profile ${CLUSTER_PROFILE}"
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CLUSTER_PROFILE} --network ${DOCKER_NET} ${MINIKUBE_OPTS} ;
  fi

  # Extract the docker network subnet (default 192.168.49.0/24) for the management cluster
  DOCKER_NET_SUBNET=$(docker network inspect ${DOCKER_NET} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

  # Configure and enable metallb in the management cluster
  if minikube --profile ${CLUSTER_PROFILE} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
    echo "Minikube management cluster profile ${CLUSTER_PROFILE} metallb addon already enabled"
  else
    configure_metallb ${CLUSTER_PROFILE} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_STARTIP} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
    minikube --profile ${CLUSTER_PROFILE} addons enable metallb ;
    patch_metallb_pull_repo ${CLUSTER_PROFILE} ;
  fi  

  # Make sure minikube has access to docker repo containing tsb images
  configure_docker_access ${CLUSTER_PROFILE} ;

  # Add nodes labels for locality based routing (region and zone)
  if ! kubectl --context ${CLUSTER_PROFILE} get nodes ${CLUSTER_PROFILE} --show-labels | grep "topology.kubernetes.io/region=${CLUSTER_REGION}" &>/dev/null ; then
    kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/region=${CLUSTER_REGION} --overwrite=true ;
  fi
  if ! kubectl --context ${CLUSTER_PROFILE} get nodes ${CLUSTER_PROFILE} --show-labels | grep "topology.kubernetes.io/zone=${CLUSTER_ZONE}" &>/dev/null ; then
    kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/zone=${CLUSTER_ZONE} --overwrite=true ;
  fi

  # Spin up vms that belong to the management cluster
  if [[ ${VM_COUNT} -eq 0 ]] ; then
    echo "Skipping vm start-up: no vms attached to management cluster ${CLUSTER_PROFILE}"
  else
    VM_INDEX=0
    while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
      VM_IMAGE=$(get_mp_vm_image_by_index ${VM_INDEX}) ;
      VM_NAME=$(get_mp_vm_name_by_index ${VM_INDEX}) ;
      if docker ps --filter "status=running" | grep ${VM_NAME} &>/dev/null ; then
        echo "Do nothing, vm ${VM_NAME} for management cluster ${CLUSTER_PROFILE} is already running"
      elif docker ps --filter "status=exited" | grep ${VM_NAME} &>/dev/null ; then
        print_info "Going to start vm ${VM_NAME} for management cluster ${CLUSTER_PROFILE} again"
        docker start ${VM_NAME} ;
      else
        print_info "Going to start vm ${VM_NAME} for management cluster ${CLUSTER_PROFILE} for the first time"
        docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${DOCKER_NET} --hostname ${VM_NAME} --name ${VM_NAME} ${VM_IMAGE} ;
      fi
      VM_INDEX=$((VM_INDEX+1))
    done
  fi

  ######################## cp clusters ########################
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    DOCKER_NET=$(get_cp_name_by_index ${CP_INDEX}) ;
    CLUSTER_REGION=$(get_cp_region_by_index ${CP_INDEX}) ;
    CLUSTER_ZONE=$(get_cp_zone_by_index ${CP_INDEX}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
  
    # Start minikube profile for this application cluster
    if minikube profile list 2>/dev/null | grep ${CLUSTER_PROFILE} | grep "Running" &>/dev/null ; then
      echo "Minikube application cluster profile ${CLUSTER_PROFILE} already running"
    else
      print_info "Starting minikube application cluster profile ${CLUSTER_PROFILE}"
      minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CLUSTER_PROFILE} --network ${DOCKER_NET} ${MINIKUBE_OPTS};
    fi

    # Extract the docker network subnet (default 192.168.49.0/24) for this application cluster
    DOCKER_NET_SUBNET=$(docker network inspect ${DOCKER_NET} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

    # Configure and enable metallb in this application cluster
    if minikube --profile ${CLUSTER_PROFILE} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
      echo "Minikube application cluster profile ${CLUSTER_PROFILE} metallb addon already enabled"
    else
      configure_metallb ${CLUSTER_PROFILE} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_STARTIP} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
      minikube --profile ${CLUSTER_PROFILE} addons enable metallb ;
      patch_metallb_pull_repo ${CLUSTER_PROFILE} ;
    fi  

    # Make sure minikube has access to docker repo containing tsb images
    configure_docker_access ${CLUSTER_PROFILE} ;

    # Add nodes labels for locality based routing (region and zone)
    if ! kubectl --context ${CLUSTER_PROFILE} get nodes ${CLUSTER_PROFILE} --show-labels | grep "topology.kubernetes.io/region=${CLUSTER_REGION}" &>/dev/null ; then
      kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/region=${CLUSTER_REGION} --overwrite=true ;
    fi
    if ! kubectl --context ${CLUSTER_PROFILE} get nodes ${CLUSTER_PROFILE} --show-labels | grep "topology.kubernetes.io/zone=${CLUSTER_ZONE}" &>/dev/null ; then
      kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/zone=${CLUSTER_ZONE} --overwrite=true ;
    fi

    # Spin up vms that belong to this application cluster
    if [[ ${VM_COUNT} -eq 0 ]] ; then
      echo "Skipping vm start-up: no vms attached to application cluster ${CLUSTER_PROFILE}"
    else
      VM_INDEX=0
      while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
        VM_IMAGE=$(get_cp_vm_image_by_index ${CP_INDEX} ${VM_INDEX}) ;
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${VM_INDEX}) ;
        if docker ps --filter "status=running" | grep ${VM_NAME} &>/dev/null ; then
          echo "Do nothing, vm ${VM_NAME} for application cluster ${CLUSTER_PROFILE} is already running"
        elif docker ps --filter "status=exited" | grep ${VM_NAME} &>/dev/null ; then
          print_info "Going to start vm ${VM_NAME} for application cluster ${CLUSTER_PROFILE} again"
          docker start ${VM_NAME} ;
        else
          print_info "Going to start vm ${VM_NAME} for application cluster ${CLUSTER_PROFILE} for the first time"
          docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${DOCKER_NET} --hostname ${VM_NAME} --name ${VM_NAME} ${VM_IMAGE} ;
        fi
        VM_INDEX=$((VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  # When multiple docker networks are used (cp installs), we need to disable docker isolation for cross cluster connectivity
  if [[ ${CP_COUNT} -gt 0 ]]; then
    # https://serverfault.com/questions/1102209/how-to-disable-docker-network-isolation
    # https://serverfault.com/questions/830135/routing-among-different-docker-networks-on-the-same-host-machine 
    echo "Flushing docker isolation iptable rules to allow cross network communication"
    sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2
  fi

  print_info "All minikube cluster profiles and vms started"
  exit 0
fi

if [[ ${ACTION} = "down" ]]; then

  # Stop minikube profiles
  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  print_info "Going to stop minikube management cluster profile ${CLUSTER_PROFILE}"
  minikube stop --profile ${CLUSTER_PROFILE} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    print_info "Going to stop minikube application cluster profile ${CLUSTER_PROFILE}"
    minikube stop --profile ${CLUSTER_PROFILE} 2>/dev/null ;
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${VM_COUNT} -eq 0 ]] ; then
    CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
    VM_INDEX=0
    while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
      DOCKER_NET=$(get_mp_name) ;
      VM_NAME=$(get_mp_vm_name_by_index ${VM_INDEX}) ;
      print_info "Going to stop vm ${VM_NAME} attached to management cluster ${CLUSTER_PROFILE}"
      docker stop ${VM_NAME} ;
      VM_INDEX=$((VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    DOCKER_NET=$(get_cp_name_by_index ${CP_INDEX}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${VM_COUNT} -eq 0 ]] ; then
      VM_INDEX=0
      while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${VM_INDEX}) ;
        print_info "Going to stop vm ${VM_NAME} attached to application cluster ${CLUSTER_PROFILE}"
        docker stop ${VM_NAME} ;
        VM_INDEX=$((VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  print_info "All minikube cluster profiles and vms stopped"
  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  CLUSTER_NAME=$(get_mp_name) ;
  TSB_API_ENDPOINT=$(kubectl --context ${CLUSTER_PROFILE} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  print_info "Minikube profiles:"
  minikube profile list ;
  echo ""

  print_info "Management plane cluster ${CLUSTER_NAME}:"
  echo "TSB GUI: https://${TSB_API_ENDPOINT}:8443 (admin/admin)"
  echo "TSB GUI (port-fowarded): https://$(curl -s ifconfig.me):8443 (admin/admin)"
  print_command "kubectl --context ${CLUSTER_PROFILE} get pods -A"

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    echo ""
    print_info "Control plane cluster ${CLUSTER_NAME}:"
    print_command "kubectl --context ${CLUSTER_PROFILE} get pods -A"
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${VM_COUNT} -eq 0 ]] ; then
    CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
    CLUSTER_NAME=$(get_mp_name) ;
    echo ""
    print_info "VMs attached to management cluster ${CLUSTER_NAME}:"
    VM_INDEX=0
    while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
      DOCKER_NET=$(get_mp_name) ;
      VM_NAME=$(get_mp_vm_name_by_index ${VM_INDEX}) ;
      VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VM_NAME}) ;
      echo "${VM_NAME} has ip address ${VM_IP}"
      print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP}"
    VM_INDEX=$((VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    DOCKER_NET=$(get_cp_name_by_index ${CP_INDEX}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${VM_COUNT} -eq 0 ]] ; then
      echo ""
      print_info "VMs attached to application cluster ${CLUSTER_NAME}:"
      VM_INDEX=0
      while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${VM_INDEX}) ;
        VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VM_NAME}) ;
        echo "${VM_NAME} has ip address ${VM_IP}"
        print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP}"
        VM_INDEX=$((VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Delete minikube profiles
  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  print_info "Going to delete minikube management cluster profile ${CLUSTER_PROFILE}"
  minikube delete --profile ${CLUSTER_PROFILE} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    print_info "Going to delete minikube application cluster profile ${CLUSTER_PROFILE}"
    minikube delete --profile ${CLUSTER_PROFILE} 2>/dev/null ;
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${VM_COUNT} -eq 0 ]] ; then
    CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
    VM_INDEX=0
    while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
      VM_NAME=$(get_mp_vm_name_by_index ${VM_INDEX}) ;
      print_info "Going to delete vm ${VM_NAME} attached to management cluster ${CLUSTER_PROFILE}"
      docker stop ${VM_NAME} ;
      docker rm ${VM_NAME} ;
      VM_INDEX=$((VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${CP_INDEX}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${VM_COUNT} -eq 0 ]] ; then
      VM_INDEX=0
      while [[ ${VM_INDEX} -lt ${VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${VM_INDEX}) ;
        print_info "Going to delete vm ${VM_NAME} attached to application cluster ${CLUSTER_PROFILE}"
        docker stop ${VM_NAME} ;
        docker rm ${VM_NAME} ;
        VM_INDEX=$((VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  # Docker networks
  MP_DOCKER_NET=$(get_mp_name) ;
  docker network rm ${MP_DOCKER_NET} 2>/dev/null ;
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_DOCKER_NET=$(get_cp_name_by_index ${CP_INDEX}) ;
    docker network rm ${CP_DOCKER_NET} 2>/dev/null ;
    CP_INDEX=$((CP_INDEX+1))
  done
  echo "All docker networks deleted"

  print_info "All minikube cluster profiles and vms deleted"
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - up"
echo "  - down"
echo "  - info"
echo "  - clean"
exit 1