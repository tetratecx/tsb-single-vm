#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

ACTION=${1}

CLUSTER_METALLB_STARTIP=100
CLUSTER_METALLB_ENDIP=199

K8S_PROVIDER=$(get_k8s_provider) ;
K8S_VERSION=$(get_k8s_version) ;
INSTALL_REPO_PW=$(get_install_repo_password) ;
INSTALL_REPO_URL=$(get_install_repo_url) ;
INSTALL_REPO_USER=$(get_install_repo_user) ;

INSTALL_REPO_INSECURE_REGISTRY=$(is_install_repo_insecure_registry) ;
MINIKUBE_OPTS="--driver docker --insecure-registry 192.168.48.0/24"
# MINIKUBE_OPTS="--driver docker --cpus=6"

# Configure metallb start and end IP
#   args:
#     (1) cluster name
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

# Configure minikube clusters to have access to docker repo containing tsb images
#   args:
#     (1) cluster name
function configure_docker_access {
  if ! [[ ${INSTALL_REPO_INSECURE_REGISTRY} == "true" ]]; then
    minikube --profile ${1} ssh -- docker login ${INSTALL_REPO_URL} --username ${INSTALL_REPO_USER} --password ${INSTALL_REPO_PW} &>/dev/null ;
    minikube --profile ${1} ssh -- sudo cp /home/docker/.docker/config.json /var/lib/kubelet ;
    minikube --profile ${1} ssh -- sudo systemctl restart kubelet ;
    print_info "Logged-in into docker repo ${INSTALL_REPO_URL} inside minikube profile ${1} cluster"
  else
    print_info "Insecure docker registry configured, skipping docker login"
  fi
}


######################## START OF ACTIONS ########################

if [[ ${ACTION} = "up" ]]; then

  ######################## mp cluster ########################
  MP_CLUSTER_NAME=$(get_mp_name) ;
  MP_CLUSTER_REGION=$(get_mp_region) ;
  MP_CLUSTER_ZONE=$(get_mp_zone) ;
  MP_VM_COUNT=$(get_mp_vm_count) ;

  # Start minikube profile for the management cluster
  if minikube profile list 2>/dev/null | grep ${MP_CLUSTER_NAME} | grep "Running" &>/dev/null ; then
    echo "Minikube management cluster profile ${MP_CLUSTER_NAME} already running"
  else
    print_info "Starting minikube management cluster profile ${MP_CLUSTER_NAME}"
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${MP_CLUSTER_NAME} --network ${MP_CLUSTER_NAME} ${MINIKUBE_OPTS} ;
  fi

  # Extract the docker network subnet (default 192.168.49.0/24) for the management cluster
  MP_DOCKER_SUBNET=$(docker network inspect ${MP_CLUSTER_NAME} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

  # Configure and enable metallb in the management cluster
  if minikube --profile ${MP_CLUSTER_NAME} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
    echo "Minikube management cluster profile ${MP_CLUSTER_NAME} metallb addon already enabled"
  else
    configure_metallb ${MP_CLUSTER_NAME} ${MP_DOCKER_SUBNET}.${CLUSTER_METALLB_STARTIP} ${MP_DOCKER_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
    minikube --profile ${MP_CLUSTER_NAME} addons enable metallb ;
  fi  

  # Make sure minikube has access to docker repo containing tsb images
  configure_docker_access ${MP_CLUSTER_NAME} ;

  # Add nodes labels for locality based routing (region and zone)
  if ! kubectl --context ${MP_CLUSTER_NAME} get nodes ${MP_CLUSTER_NAME} --show-labels | grep "topology.kubernetes.io/region=${MP_CLUSTER_REGION}" &>/dev/null ; then
    kubectl --context ${MP_CLUSTER_NAME} label node ${MP_CLUSTER_NAME} topology.kubernetes.io/region=${MP_CLUSTER_REGION} --overwrite=true ;
  fi
  if ! kubectl --context ${MP_CLUSTER_NAME} get nodes ${MP_CLUSTER_NAME} --show-labels | grep "topology.kubernetes.io/zone=${MP_CLUSTER_ZONE}" &>/dev/null ; then
    kubectl --context ${MP_CLUSTER_NAME} label node ${MP_CLUSTER_NAME} topology.kubernetes.io/zone=${MP_CLUSTER_ZONE} --overwrite=true ;
  fi

  # Spin up vms that belong to the management cluster
  if [[ ${MP_VM_COUNT} -eq 0 ]] ; then
    echo "Skipping vm start-up: no vms attached to management cluster ${MP_CLUSTER_NAME}"
  else
    MP_VM_INDEX=0
    while [[ ${MP_VM_INDEX} -lt ${MP_VM_COUNT} ]]; do
      VM_IMAGE=$(get_mp_vm_image_by_index ${MP_VM_INDEX}) ;
      VM_NAME=$(get_mp_vm_name_by_index ${MP_VM_INDEX}) ;
      if docker ps --filter "status=running" | grep ${VM_NAME} &>/dev/null ; then
        echo "Do nothing, vm ${VM_NAME} for management cluster ${MP_CLUSTER_NAME} is already running"
      elif docker ps --filter "status=exited" | grep ${VM_NAME} &>/dev/null ; then
        print_info "Going to start vm ${VM_NAME} for management cluster ${MP_CLUSTER_NAME} again"
        docker start ${VM_NAME} ;
      else
        print_info "Going to start vm ${VM_NAME} for management cluster ${MP_CLUSTER_NAME} for the first time"
        docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${MP_CLUSTER_NAME} --hostname ${VM_NAME} --name ${VM_NAME} ${VM_IMAGE} ;
      fi
      MP_VM_INDEX=$((MP_VM_INDEX+1))
    done
  fi

  # Disable iptables docker isolation for cluster to private repo communication
  # https://serverfault.com/questions/1102209/how-to-disable-docker-network-isolation
  # https://serverfault.com/questions/830135/routing-among-different-docker-networks-on-the-same-host-machine 
  echo "Flushing docker isolation iptable rules to allow ${MP_CLUSTER_NAME} cluster to docker repo communication"
  sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2

  ######################## cp clusters ########################
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    CP_CLUSTER_REGION=$(get_cp_region_by_index ${CP_INDEX}) ;
    CP_CLUSTER_ZONE=$(get_cp_zone_by_index ${CP_INDEX}) ;
    CP_VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
  
    # Start minikube profile for this application cluster
    if minikube profile list 2>/dev/null | grep ${CP_CLUSTER_NAME} | grep "Running" &>/dev/null ; then
      echo "Minikube application cluster profile ${CP_CLUSTER_NAME} already running"
    else
      print_info "Starting minikube application cluster profile ${CP_CLUSTER_NAME}"
      minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CP_CLUSTER_NAME} --network ${CP_CLUSTER_NAME} ${MINIKUBE_OPTS};
    fi

    # Extract the docker network subnet (default 192.168.49.0/24) for this application cluster
    CP_DOCKER_SUBNET=$(docker network inspect ${CP_CLUSTER_NAME} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

    # Configure and enable metallb in this application cluster
    if minikube --profile ${CP_CLUSTER_NAME} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
      echo "Minikube application cluster profile ${CP_CLUSTER_NAME} metallb addon already enabled"
    else
      configure_metallb ${CP_CLUSTER_NAME} ${CP_DOCKER_SUBNET}.${CLUSTER_METALLB_STARTIP} ${CP_DOCKER_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
      minikube --profile ${CP_CLUSTER_NAME} addons enable metallb ;
    fi  

    # Make sure minikube has access to docker repo containing tsb images
    configure_docker_access ${CP_CLUSTER_NAME} ;

    # Add nodes labels for locality based routing (region and zone)
    if ! kubectl --context ${CP_CLUSTER_NAME} get nodes ${CP_CLUSTER_NAME} --show-labels | grep "topology.kubernetes.io/region=${CP_CLUSTER_REGION}" &>/dev/null ; then
      kubectl --context ${CP_CLUSTER_NAME} label node ${CP_CLUSTER_NAME} topology.kubernetes.io/region=${CP_CLUSTER_REGION} --overwrite=true ;
    fi
    if ! kubectl --context ${CP_CLUSTER_NAME} get nodes ${CP_CLUSTER_NAME} --show-labels | grep "topology.kubernetes.io/zone=${CP_CLUSTER_ZONE}" &>/dev/null ; then
      kubectl --context ${CP_CLUSTER_NAME} label node ${CP_CLUSTER_NAME} topology.kubernetes.io/zone=${CP_CLUSTER_ZONE} --overwrite=true ;
    fi

    # Spin up vms that belong to this application cluster
    if [[ ${CP_VM_COUNT} -eq 0 ]] ; then
      echo "Skipping vm start-up: no vms attached to application cluster ${CP_CLUSTER_NAME}"
    else
      CP_VM_INDEX=0
      while [[ ${CP_VM_INDEX} -lt ${CP_VM_COUNT} ]]; do
        VM_IMAGE=$(get_cp_vm_image_by_index ${CP_INDEX} ${CP_VM_INDEX}) ;
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${CP_VM_INDEX}) ;
        if docker ps --filter "status=running" | grep ${VM_NAME} &>/dev/null ; then
          echo "Do nothing, vm ${VM_NAME} for application cluster ${CP_CLUSTER_NAME} is already running"
        elif docker ps --filter "status=exited" | grep ${VM_NAME} &>/dev/null ; then
          print_info "Going to start vm ${VM_NAME} for application cluster ${CP_CLUSTER_NAME} again"
          docker start ${VM_NAME} ;
        else
          print_info "Going to start vm ${VM_NAME} for application cluster ${CP_CLUSTER_NAME} for the first time"
          docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${CP_CLUSTER_NAME} --hostname ${VM_NAME} --name ${VM_NAME} ${VM_IMAGE} ;
        fi
        CP_VM_INDEX=$((CP_VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  # Disable iptables docker isolation for cross cluster and cluster to private repo communication
  if [[ ${CP_COUNT} -gt 0 ]]; then
    # https://serverfault.com/questions/1102209/how-to-disable-docker-network-isolation
    # https://serverfault.com/questions/830135/routing-among-different-docker-networks-on-the-same-host-machine 
    echo "Flushing docker isolation iptable rules to allow cross cluster and ${CP_CLUSTER_NAME} cluster to private docker repo communication"
    sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2
  fi

  print_info "All minikube cluster profiles and vms started"
  exit 0
fi

if [[ ${ACTION} = "down" ]]; then

  # Stop minikube profiles
  MP_CLUSTER_NAME=$(get_mp_name) ;
  print_info "Going to stop minikube management cluster profile ${MP_CLUSTER_NAME}"
  minikube stop --profile ${MP_CLUSTER_NAME} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    print_info "Going to stop minikube application cluster profile ${CP_CLUSTER_NAME}"
    minikube stop --profile ${CP_CLUSTER_NAME} 2>/dev/null ;
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  MP_VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${MP_VM_COUNT} -eq 0 ]] ; then
    MP_CLUSTER_NAME=$(get_mp_name) ;
    MP_VM_INDEX=0
    while [[ ${MP_VM_INDEX} -lt ${MP_VM_COUNT} ]]; do
      VM_NAME=$(get_mp_vm_name_by_index ${MP_VM_INDEX}) ;
      print_info "Going to stop vm ${VM_NAME} attached to management cluster ${MP_CLUSTER_NAME}"
      docker stop ${VM_NAME} ;
      MP_VM_INDEX=$((MP_VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    CP_VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${CP_VM_COUNT} -eq 0 ]] ; then
      CP_VM_INDEX=0
      while [[ ${CP_VM_INDEX} -lt ${CP_VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${CP_VM_INDEX}) ;
        print_info "Going to stop vm ${VM_NAME} attached to application cluster ${CP_CLUSTER_NAME}"
        docker stop ${VM_NAME} ;
        CP_VM_INDEX=$((CP_VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  print_info "All minikube cluster profiles and vms stopped"
  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  MP_CLUSTER_NAME=$(get_mp_name) ;
  if ! kubectl config get-contexts ${MP_CLUSTER_NAME} &>/dev/null ; then
    kubectl config get-contexts ;
    minikube profile list ;
    docker ps ;
    print_error "No kubernetes context \"${MP_CLUSTER_NAME}\" found... topology in configured env.json is not running." ;
    exit 0
  fi  

  TSB_API_ENDPOINT=$(kubectl --context ${MP_CLUSTER_NAME} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  print_info "Minikube profiles:"
  minikube profile list ;
  echo ""

  print_info "Management plane cluster ${MP_CLUSTER_NAME}:"
  echo "TSB GUI: https://${TSB_API_ENDPOINT}:8443 (admin/admin)"
  echo "TSB GUI (port-fowarded): https://$(curl -s ifconfig.me):8443 (admin/admin)"
  print_command "kubectl --context ${MP_CLUSTER_NAME} get pods -A"

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    echo ""
    print_info "Control plane cluster ${CP_CLUSTER_NAME}:"
    print_command "kubectl --context ${CP_CLUSTER_NAME} get pods -A"
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  MP_VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${MP_VM_COUNT} -eq 0 ]] ; then
    MP_CLUSTER_NAME=$(get_mp_name) ;
    echo ""
    print_info "VMs attached to management cluster ${MP_CLUSTER_NAME}:"
    MP_VM_INDEX=0
    while [[ ${MP_VM_INDEX} -lt ${MP_VM_COUNT} ]]; do
      VM_NAME=$(get_mp_vm_name_by_index ${MP_VM_INDEX}) ;
      VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VM_NAME}) ;
      echo "${VM_NAME} has ip address ${VM_IP}"
      print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP}"
    MP_VM_INDEX=$((MP_VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    CP_VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${CP_VM_COUNT} -eq 0 ]] ; then
      echo ""
      print_info "VMs attached to application cluster ${CP_CLUSTER_NAME}:"
      CP_VM_INDEX=0
      while [[ ${CP_VM_INDEX} -lt ${CP_VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${CP_VM_INDEX}) ;
        VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VM_NAME}) ;
        echo "${VM_NAME} has ip address ${VM_IP}"
        print_command "ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP}"
        CP_VM_INDEX=$((CP_VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Delete minikube profiles
  MP_CLUSTER_NAME=$(get_mp_name) ;
  print_info "Going to delete minikube management cluster profile ${MP_CLUSTER_NAME}"
  minikube delete --profile ${MP_CLUSTER_NAME} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    print_info "Going to delete minikube application cluster profile ${CP_CLUSTER_NAME}"
    minikube delete --profile ${CP_CLUSTER_NAME} 2>/dev/null ;
    CP_INDEX=$((CP_INDEX+1))
  done

  # Management plane VMs
  MP_VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${MP_VM_COUNT} -eq 0 ]] ; then
    MP_CLUSTER_NAME=$(get_mp_name) ;
    MP_VM_INDEX=0
    while [[ ${MP_VM_INDEX} -lt ${MP_VM_COUNT} ]]; do
      VM_NAME=$(get_mp_vm_name_by_index ${MP_VM_INDEX}) ;
      print_info "Going to delete vm ${VM_NAME} attached to management cluster ${MP_CLUSTER_NAME}"
      docker stop ${VM_NAME} ;
      docker rm ${VM_NAME} ;
      MP_VM_INDEX=$((MP_VM_INDEX+1))
    done
  fi

  # Control plane VMs
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    CP_VM_COUNT=$(get_cp_vm_count_by_index ${CP_INDEX}) ;
    if ! [[ ${CP_VM_COUNT} -eq 0 ]] ; then
      CP_VM_INDEX=0
      while [[ ${CP_VM_INDEX} -lt ${CP_VM_COUNT} ]]; do
        VM_NAME=$(get_cp_vm_name_by_index ${CP_INDEX} ${CP_VM_INDEX}) ;
        print_info "Going to delete vm ${VM_NAME} attached to application cluster ${CP_CLUSTER_NAME}"
        docker stop ${VM_NAME} ;
        docker rm ${VM_NAME} ;
        CP_VM_INDEX=$((CP_VM_INDEX+1))
      done
    fi
    CP_INDEX=$((CP_INDEX+1))
  done

  # Docker networks
  MP_CLUSTER_NAME=$(get_mp_name) ;
  docker network rm ${MP_CLUSTER_NAME} 2>/dev/null ;
  CP_COUNT=$(get_cp_count)
  CP_INDEX=0
  while [[ ${CP_INDEX} -lt ${CP_COUNT} ]]; do
    CP_CLUSTER_NAME=$(get_cp_name_by_index ${CP_INDEX}) ;
    docker network rm ${CP_CLUSTER_NAME} 2>/dev/null ;
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