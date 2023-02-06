#!/usr/bin/env bash

ACTION=${1}
CLUSTER=${2}
K8S_VERSION=${3}

VBOX_BRIDGE_NETWORK=HostInterfaceNetworking-vboxnet0

# Minikube always re-configures virtualbox DHCP pool of the bridged network to x.x.x.100-x.x.x.254
# So we are left with the rest of the subnet space to avoid conflict between metallb and vbox dhcp
# https://github.com/kubernetes/minikube/issues/4210

MGMT_CLUSTER_PROFILE=mgmt-cluster
MGMT_CLUSTER_METALLB_STARTIP=40
MGMT_CLUSTER_METALLB_ENDIP=59

ACTIVE_CLUSTER_PROFILE=active-cluster
ACTIVE_CLUSTER_METALLB_STARTIP=60
ACTIVE_CLUSTER_METALLB_ENDIP=79

STANDBY_CLUSTER_PROFILE=standby-cluster
STANDBY_CLUSTER_METALLB_STARTIP=80
STANDBY_CLUSTER_METALLB_ENDIP=99

VM_NAME=ubuntu-vm
VM_CONFDIR=./config/04-ubuntu-vm

# Configure virtualbox IP subnet 
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
  echo "${TSB_DOCKER_PASSWORD}" | docker login containers.dl.tetrate.io --username ${TSB_DOCKER_USERNAME} --password-stdin

  # Sync all tsb images locally (if not yet available)
  echo "Going to pull tsb container images"
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    if ! docker image inspect ${image} &>/dev/null ; then
      echo -n "."
      docker pull ${image} ;
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

# Download VM if not available
#   args:
#     (1) ova download url
#     (2) target file
function download_vm {
  if [[ -f "${2}" ]]; then
    echo "${2} exists, skipping download"
    return
  fi
  curl ${1} --output ${2}
}

# Wait for vm bridge ip address to become available
#   args:
#     (1) vm name
function wait_vm_bridge_ip {
  echo "Waiting for vm ${1} to get bridge ip address"
  while vboxmanage guestproperty get ${1} "/VirtualBox/GuestInfo/Net/0/V4/IP" | grep -q 'No value set!' &>/dev/null; do
    echo -n .
    sleep 5
  done
  echo "DONE"
}

# Get vm bridge ip address
#   args:
#     (1) vm name
function get_vm_bridge_ip {
  echo $(vboxmanage guestproperty get ${1} "/VirtualBox/GuestInfo/Net/0/V4/IP" | cut -d " " -f2)
}

######################## START OF ACTIONS ########################

if [[ ${ACTION} = "cluster-up" ]]; then

  if [[ ${CLUSTER} = "mgmt-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver virtualbox --cpus=6 --memory=12g"
    CLUSTER_PROFILE=${MGMT_CLUSTER_PROFILE}
    CLUSTER_METALLB_STARTIP=${MGMT_CLUSTER_METALLB_STARTIP}
    CLUSTER_METALLB_ENDIP=${MGMT_CLUSTER_METALLB_ENDIP}
    CLUSTER_REGION=region1
    CLUSTER_ZONE=zone1a
  elif [[ ${CLUSTER} = "active-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver virtualbox --cpus=6 --memory=9g"
    CLUSTER_PROFILE=${ACTIVE_CLUSTER_PROFILE}
    CLUSTER_METALLB_STARTIP=${ACTIVE_CLUSTER_METALLB_STARTIP}
    CLUSTER_METALLB_ENDIP=${ACTIVE_CLUSTER_METALLB_ENDIP}
    CLUSTER_REGION=region1
    CLUSTER_ZONE=zone1b
  elif [[ ${CLUSTER} = "standby-cluster" ]]; then
    MINIKUBE_CLUSTER_OPTS="--driver virtualbox --cpus=6 --memory=9g"
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

  # Extract the virtualbox network subnet (default 192.168.59.0/24)
  VBOX_NETWORK_SUBNET=$(get_vbox_subnet ${VBOX_BRIDGE_NETWORK})

  # Start minikube profiles for the mgmt and active clusters
  if minikube profile list | grep ${CLUSTER_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube cluster profile ${CLUSTER_PROFILE} already running"
  else
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${CLUSTER_PROFILE} ${MINIKUBE_CLUSTER_OPTS} ;
  fi

  # Configure and enable metallb in the mgmt and active clusters
  if minikube --profile ${CLUSTER_PROFILE} addons list | grep "metallb" | grep "enabled" &>/dev/null ; then
    echo "Minikube cluster profile ${CLUSTER_PROFILE} metallb addon already enabled"
  else
    configure_metallb ${CLUSTER_PROFILE} ${VBOX_NETWORK_SUBNET}${CLUSTER_METALLB_STARTIP} ${VBOX_NETWORK_SUBNET}${CLUSTER_METALLB_ENDIP} ;
    minikube --profile ${CLUSTER_PROFILE} addons enable metallb ;
  fi  

  # Pull images locally and sync them to minikube profiles of the mgmt and active clusters
  sync_images ;
  load_images ${CLUSTER_PROFILE} ;

  # Add nodes labels for locality based routing (region and zone)
  kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/region=${CLUSTER_REGION} --overwrite=true ;
  kubectl --context ${CLUSTER_PROFILE} label node ${CLUSTER_PROFILE} topology.kubernetes.io/zone=${CLUSTER_ZONE} --overwrite=true ;

  exit 0
fi

if [[ ${ACTION} = "vm-up" ]]; then
  OVA_URL=https://cloud-images.ubuntu.com/jammy/20230110/jammy-server-cloudimg-amd64.ova
  OVA_VM_NAME=ubuntu-jammy-22.04-cloudimg-20230110

  VM_FILE=${VM_CONFDIR}/${VM_NAME}.ova
  VM_CLOUD_INIT_ISO=${VM_CONFDIR}/${VM_NAME}-cloud-init.iso
  CLOUD_INIT_USER_DATA=${VM_CONFDIR}/cloud-init/user-data
  CLOUD_INIT_META_DATA=${VM_CONFDIR}/cloud-init/meta-data

  if vboxmanage list vms | grep ubuntu-vm &>/dev/null ; then
    echo "VM ${VM_NAME} already available"
  else
    # Download VM ova file if not present
    download_vm ${OVA_URL} ${VM_FILE} ;

    # Import and rename ova file into virtualbox
    vboxmanage import ${VM_FILE} ;
    vboxmanage modifyvm ${OVA_VM_NAME} --name ${VM_NAME} ;

    # Generate cloud-init iso image
    rm -f ${VM_CLOUD_INIT} ;
    genisoimage -output ${VM_CLOUD_INIT_ISO} -volid cidata -joliet -rock ${CLOUD_INIT_USER_DATA} ${CLOUD_INIT_META_DATA} ;

    # Add second adapter to bridge to the minikube clusters
    vboxmanage modifyvm ${VM_NAME} --nic2 hostonly --hostonlyadapter2 vboxnet0 --nictype2 virtio ;
    
    # Add cloud-init iso image
    vboxmanage storageattach ${VM_NAME} --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium ${VM_CLOUD_INIT_ISO} ;
  fi

  if vboxmanage list runningvms | grep ubuntu-vm &>/dev/null ; then
    echo "VM ${VM_NAME} already running"
  else
    # Start up the VM
    vboxmanage startvm ${VM_NAME} --type headless ;
  fi 

  # Get the bridge ip from the vm
  wait_vm_bridge_ip ${VM_NAME} ;
  VM_IP=$(get_vm_bridge_ip ${VM_NAME}) ;
  echo "VM is available through ssh (tsbadmin/tsbadmin)" ;
  echo "ssh -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_IP}" ;

  exit 0
fi

if [[ ${ACTION} = "mgmt-active-down" ]]; then

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

if [[ ${ACTION} = "vm-down" ]]; then

  # Power off the VM
  vboxmanage controlvm ${VM_NAME} poweroff ;

  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  echo "kubectl --profile ${MGMT_CLUSTER_PROFILE} get pods -A"
  echo "kubectl --profile ${ACTIVE_CLUSTER_PROFILE} get pods -A"
  echo "kubectl --profile ${STANDBY_CLUSTER_PROFILE} get pods -A"
  VM_IP=$(get_vm_bridge_ip ${VM_NAME}) ;
  echo "ssh -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_IP}" ;

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Delete minikube profiles
  minikube delete --profile ${MGMT_CLUSTER_PROFILE} 2>/dev/null ;
  minikube delete --profile ${ACTIVE_CLUSTER_PROFILE} 2>/dev/null ;
  minikube delete --profile ${STANDBY_CLUSTER_PROFILE} 2>/dev/null ;

  # Remove the VM
  vboxmanage controlvm ${VM_NAME} poweroff 2>/dev/null ;
  vboxmanage unregistervm ${VM_NAME} --delete 2>/dev/null ;

  exit 0
fi

echo "Please specify one of the following action:"
echo "  - cluster-up"
echo "  - vm-up"

echo "  - cluster-down"
echo "  - vm-down"

echo "  - info"
echo "  - clean"
exit 1