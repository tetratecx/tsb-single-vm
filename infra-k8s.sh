#!/usr/bin/env bash

ACTION=${1}
CLUSTER=${2}
K8S_VERSION=${3}

DOCKER_NET=tsb-demo

MGMT_CLUSTER_PROFILE=mgmt-cluster
MGMT_CLUSTER_METALLB_STARTIP=100
MGMT_CLUSTER_METALLB_ENDIP=119

ACTIVE_CLUSTER_PROFILE=active-cluster
ACTIVE_CLUSTER_METALLB_STARTIP=120
ACTIVE_CLUSTER_METALLB_ENDIP=139

STANDBY_CLUSTER_PROFILE=standby-cluster
STANDBY_CLUSTER_METALLB_STARTIP=140
STANDBY_CLUSTER_METALLB_ENDIP=159

# Get virtualbox IP subnet 
#   args:
#     (1) virtualbox bridge network name
function get_vbox_subnet {
  if vboxmanage list dhcpservers | grep "NetworkName:" | grep "${1}" &>/dev/null ; then
    echo $(vboxmanage list dhcpservers | grep "Dhcpd IP:" | awk '{ print $NF }' | awk -F '.' '{ print $1"."$2"."$3".";}')
  else
    echo "Cannot find a virtualbox network named ${1}. Quitting!"
    exit 1
  fi
}

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

# Pull tsb docker images 
function sync_images {
  # Sync all tsb images locally (if not yet available)
  echo "Going to pull tsb container images"
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    if ! docker image inspect ${image} &>/dev/null ; then
      docker pull ${image} ;
      echo -n "."
    fi
  done

  # Sync image for application deployment
  if ! docker image inspect containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
    echo -n "."
  fi

  # Sync image for debugging
  if ! docker image inspect containers.dl.tetrate.io/netshoot &>/dev/null ; then
    docker pull containers.dl.tetrate.io/netshoot ;
    echo -n "."
  fi

  echo "DONE"
}

# Load docker images into minikube profile 
#   args:
#     (1) minikube profile name
function load_images {

  # Load images for tsb
  echo "Going to load tsb container images into minikube profile ${1}"
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    if ! minikube --profile ${1} image ls | grep ${image} &>/dev/null ; then
      # echo "Syncing image ${image} to minikube profile ${1}" ;
      echo -n "."
      minikube --profile ${1} image load ${image} ;
    fi
  done

  # Load image for application deployment
  if ! minikube --profile ${1} image ls | grep containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    # echo "Syncing image containers.dl.tetrate.io/obs-tester-server:1.0 to minikube profile ${1}" ;
    echo -n "."
    minikube --profile ${1} image load containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi

  # Load image for debugging
  if ! minikube --profile ${1} image ls | grep containers.dl.tetrate.io/netshoot &>/dev/null ; then
    # echo "Syncing image containers.dl.tetrate.io/netshoot to minikube profile ${1}" ;
    echo -n "."
    minikube --profile ${1} image load containers.dl.tetrate.io/netshoot ;
  fi

  echo "DONE"
}

######################## START OF ACTIONS ########################

if [[ ${ACTION} = "cluster-up" ]]; then

  if [[ ${CLUSTER} = "mgmt-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver docker --network=${DOCKER_NET} --cpus=6"
    CLUSTER_PROFILE=${MGMT_CLUSTER_PROFILE}
    CLUSTER_METALLB_STARTIP=${MGMT_CLUSTER_METALLB_STARTIP}
    CLUSTER_METALLB_ENDIP=${MGMT_CLUSTER_METALLB_ENDIP}
    CLUSTER_REGION=region1
    CLUSTER_ZONE=zone1a
  elif [[ ${CLUSTER} = "active-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver docker --network=${DOCKER_NET} --cpus=6"
    CLUSTER_PROFILE=${ACTIVE_CLUSTER_PROFILE}
    CLUSTER_METALLB_STARTIP=${ACTIVE_CLUSTER_METALLB_STARTIP}
    CLUSTER_METALLB_ENDIP=${ACTIVE_CLUSTER_METALLB_ENDIP}
    CLUSTER_REGION=region1
    CLUSTER_ZONE=zone1b
  elif [[ ${CLUSTER} = "standby-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver docker --network=${DOCKER_NET} --cpus=6"
    CLUSTER_PROFILE=${STANDBY_CLUSTER_PROFILE}
    CLUSTER_METALLB_STARTIP=${STANDBY_CLUSTER_METALLB_STARTIP}
    CLUSTER_METALLB_ENDIP=${STANDBY_CLUSTER_METALLB_ENDIP}
    CLUSTER_REGION=region2
    CLUSTER_ZONE=zone2a
  else
    echo "Please specify one of the following cluster:"
    echo "  - mgmt-cluster"
    echo "  - active-cluster"
    echo "  - standby-cluster"
    exit 1
  fi

  # Start minikube profiles for the mgmt and active clusters
  if minikube profile list 2>/dev/null | grep ${CLUSTER_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube cluster profile ${CLUSTER_PROFILE} already running"
  else
    echo "Starting minikube cluster profile ${CLUSTER_PROFILE}"
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CLUSTER_PROFILE} ${MINIKUBE_CLUSTER_OPTS} ;
  fi

  # Extract the docker network subnet (default 192.168.49.0/24)
  DOCKER_NET_SUBNET=$(docker network inspect ${DOCKER_NET} --format '{{(index .IPAM.Config 0).Subnet}}' | awk -F '.' '{ print $1"."$2"."$3;}')

  # Configure and enable metallb in the mgmt and active clusters
  if minikube --profile ${CLUSTER_PROFILE} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
    echo "Minikube cluster profile ${CLUSTER_PROFILE} metallb addon already enabled"
  else
    configure_metallb ${CLUSTER_PROFILE} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_STARTIP} ${DOCKER_NET_SUBNET}.${CLUSTER_METALLB_ENDIP} ;
    minikube --profile ${CLUSTER_PROFILE} addons enable metallb ;
  fi  

  # Pull images locally and sync them to minikube profiles of the mgmt and active clusters
  # sync_images ;
  # load_images ${CLUSTER_PROFILE} ;
  # Make sure minikube has access to tsb private repo
  minikube --profile ${CLUSTER_PROFILE} ssh docker login containers.dl.tetrate.io --username ${TSB_DOCKER_USERNAME} --password ${TSB_DOCKER_PASSWORD} ;

  # Add nodes labels for locality based routing (region and zone)
  kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/region=${CLUSTER_REGION} --overwrite=true ;
  kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/zone=${CLUSTER_ZONE} --overwrite=true ;

  exit 0
fi

if [[ ${ACTION} = "cluster-down" ]]; then

  if [[ ${CLUSTER} = "mgmt-cluster" ]]; then
    CLUSTER_PROFILE=${MGMT_CLUSTER_PROFILE}
  elif [[ ${CLUSTER} = "active-cluster" ]]; then
    CLUSTER_PROFILE=${ACTIVE_CLUSTER_PROFILE}
  elif [[ ${CLUSTER} = "standby-cluster" ]]; then
    CLUSTER_PROFILE=${STANDBY_CLUSTER_PROFILE}
  else
    echo "Please specify one of the following cluster:"
    echo "  - mgmt-cluster"
    echo "  - active-cluster"
    echo "  - standby-cluster"
    exit 1
  fi

  # Stop minikube profiles
  minikube stop --profile ${CLUSTER_PROFILE} ;

  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  echo "kubectl --profile ${MGMT_CLUSTER_PROFILE} get pods -A"
  echo "kubectl --profile ${ACTIVE_CLUSTER_PROFILE} get pods -A"
  echo "kubectl --profile ${STANDBY_CLUSTER_PROFILE} get pods -A"

  TSB_API_ENDPOINT=$(kubectl --context ${MGMT_CLUSTER_PROFILE} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;
  echo "TSB GUI: https://${TSB_API_ENDPOINT}:8443 (admin/admin)"

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Delete minikube profiles
  minikube delete --profile ${MGMT_CLUSTER_PROFILE} 2>/dev/null ;
  minikube delete --profile ${ACTIVE_CLUSTER_PROFILE} 2>/dev/null ;
  minikube delete --profile ${STANDBY_CLUSTER_PROFILE} 2>/dev/null ;

  exit 0
fi

echo "Please specify one of the following action:"
echo "  - cluster-up"
echo "  - cluster-down"
echo "  - info"
echo "  - clean"
exit 1