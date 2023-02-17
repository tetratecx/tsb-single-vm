#!/usr/bin/env bash
source config.sh

ACTION=${1}

MINIKUBE_OPTS="--driver docker --cpus=6"
CLUSTER_METALLB_STARTIP=100
CLUSTER_METALLB_ENDIP=199

K8S_VERSION=$(get_k8s_version) ;
TSB_DOCKER_REPO=$(get_tsb_image_sync_repo) ;
TSB_DOCKER_USERNAME=$(get_tsb_image_sync_username) ;
TSB_DOCKER_APIKEY=$(get_tsb_image_sync_apikey) ;


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
    echo "Starting minikube management cluster profile ${CLUSTER_PROFILE}"
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
  fi  

  # Make sure minikube has access to tsb private repo
  minikube --profile ${CLUSTER_PROFILE} ssh -- docker login ${TSB_DOCKER_REPO} --username ${TSB_DOCKER_USERNAME} --password ${TSB_DOCKER_APIKEY} &>/dev/null ;
  minikube --profile ${CLUSTER_PROFILE} ssh -- sudo cp /home/docker/.docker/config.json /var/lib/kubelet ;
  minikube --profile ${CLUSTER_PROFILE} ssh -- sudo systemctl restart kubelet ;

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
    for index_vm in $(seq 0 $((${VM_COUNT} - 1))) ; do
      VM_IMAGE=$(get_mp_vm_image_by_index ${index_vm}) ;
      VM_NAME=$(get_mp_vm_name_by_index ${index_vm}) ;
      echo "Going to spin vm ${VM_NAME} for management cluster ${CLUSTER_PROFILE}"
      docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${DOCKER_NET} --name ${VM_NAME} ${VM_IMAGE} ;
    done
  fi

  ######################## cp clusters ########################
  CP_COUNT=$(get_cp_count)
  for index in $(seq 0 $((${CP_COUNT} - 1))) ; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${index}) ;
    DOCKER_NET=$(get_cp_name_by_index ${index}) ;
    CLUSTER_REGION=$(get_cp_region_by_index ${index}) ;
    CLUSTER_ZONE=$(get_cp_zone_by_index ${index}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${index}) ;
  
    # Start minikube profile for this application cluster
    if minikube profile list 2>/dev/null | grep ${CLUSTER_PROFILE} | grep "Running" &>/dev/null ; then
      echo "Minikube application cluster profile ${CLUSTER_PROFILE} already running"
    else
      echo "Starting minikube application cluster profile ${CLUSTER_PROFILE}"
      minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CLUSTER_PROFILE} --network ${DOCKER_NET} ${MINIKUBE_OPTS} ;
    fi

    # Extract the docker network subnet (default 192.168.49.0/24) for this application cluster
    DOCKER_NET_SUBNET=$(docker network inspect ${DOCKER_NET} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

    # Configure and enable metallb in this application cluster
    if minikube --profile ${CLUSTER_PROFILE} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
      echo "Minikube application cluster profile ${CLUSTER_PROFILE} metallb addon already enabled"
    else
      configure_metallb ${CLUSTER_PROFILE} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_STARTIP} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
      minikube --profile ${CLUSTER_PROFILE} addons enable metallb ;
    fi  

    # Make sure minikube has access to tsb private repo
    minikube --profile ${CLUSTER_PROFILE} ssh -- docker login ${TSB_DOCKER_REPO} --username ${TSB_DOCKER_USERNAME} --password ${TSB_DOCKER_APIKEY} &>/dev/null ;
    minikube --profile ${CLUSTER_PROFILE} ssh -- sudo cp /home/docker/.docker/config.json /var/lib/kubelet ;
    minikube --profile ${CLUSTER_PROFILE} ssh -- sudo systemctl restart kubelet ;

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
      for index_vm in $(seq 0 $((${VM_COUNT} - 1))) ; do
        VM_IMAGE=$(get_cp_vm_image_by_index ${index} ${index_vm}) ;
        VM_NAME=$(get_cp_vm_name_by_index ${index} ${index_vm}) ;
        echo "Going to spin vm ${VM_NAME} for application cluster ${CLUSTER_PROFILE}"
        docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -d --net ${DOCKER_NET} --name ${VM_NAME} ${VM_IMAGE} ;
      done
    fi
  done
  
  exit 0
fi

if [[ ${ACTION} = "down" ]]; then

  # Stop minikube profiles
  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  echo "Going to stop minikube management cluster profile ${CLUSTER_PROFILE}"
  minikube stop --profile ${CLUSTER_PROFILE} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  for index in $(seq 0 $((${CP_COUNT} - 1))) ; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${index})
    echo "Going to stop minikube application cluster profile ${CLUSTER_PROFILE}"
    minikube stop --profile ${CLUSTER_PROFILE} 2>/dev/null ;
  done

  echo "All minikube cluster profiles stopped"
  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  TSB_API_ENDPOINT=$(kubectl --context ${CLUSTER_PROFILE} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "Minikube profiles"
  minikube profile list ;

  echo "Management plane cluster:"
  echo "TSB GUI: https://${TSB_API_ENDPOINT}:8443 (admin/admin)"
  echo "kubectl --context ${CLUSTER_PROFILE} get pods -A"
  echo ""

  echo "Control plane cluster:"
  CP_COUNT=$(get_cp_count)
  for index in $(seq 0 $((${CP_COUNT} - 1))) ; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${index})
    echo "kubectl --context ${CLUSTER_PROFILE} get pods -A"
  done

  VM_COUNT=$(get_mp_vm_count) ;
  if ! [[ ${VM_COUNT} -eq 0 ]] ; then
    CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
    echo "\nVMs attached to management cluster ${CLUSTER_PROFILE}:"
    for index_vm in $(seq 0 $((${VM_COUNT} - 1))) ; do
      DOCKER_NET=$(get_mp_name) ;
      VM_NAME=$(get_mp_vm_name_by_index ${index_vm}) ;
      VM_IP=$(docker container inspect ${VM_NAME} --format "{{.NetworkSettings.Networks.${DOCKER_NET}.IPAddress}}")
      echo "${VM_NAME} has ip address ${VM_IP}"
    done
  fi

  CP_COUNT=$(get_cp_count)
  for index in $(seq 0 $((${CP_COUNT} - 1))) ; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${index})
    DOCKER_NET=$(get_cp_name_by_index ${index}) ;
    VM_COUNT=$(get_cp_vm_count_by_index ${index}) ;
    if ! [[ ${VM_COUNT} -eq 0 ]] ; then
      echo "\nVMs attached to application cluster ${CLUSTER_PROFILE}:"
      for index_vm in $(seq 0 $((${VM_COUNT} - 1))) ; do
        VM_NAME=$(get_cp_vm_name_by_index ${index} ${index_vm}) ;
        VM_IP=$(docker container inspect ${VM_NAME} --format "{{.NetworkSettings.Networks.${DOCKER_NET}.IPAddress}}")
        echo "${VM_NAME} has ip address ${VM_IP}"
      done
    fi
  done

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Delete minikube profiles
  CLUSTER_PROFILE=$(get_mp_minikube_profile) ;
  echo "Going to delete minikube management cluster profile ${CLUSTER_PROFILE}"
  minikube delete --profile ${CLUSTER_PROFILE} 2>/dev/null ;

  CP_COUNT=$(get_cp_count)
  for index in $(seq 0 $((${CP_COUNT} - 1))) ; do
    CLUSTER_PROFILE=$(get_cp_minikube_profile_by_index ${index})
    echo "Going to delete minikube application cluster profile ${CLUSTER_PROFILE}"
    minikube delete --profile ${CLUSTER_PROFILE} 2>/dev/null ;
  done

  echo "All minikube cluster profiles deleted"
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - up"
echo "  - down"
echo "  - info"
echo "  - clean"
exit 1