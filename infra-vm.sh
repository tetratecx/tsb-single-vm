#!/usr/bin/env bash

ACTION=${1}
VM_NAME=${2}

VBOX_BRIDGE_NETWORK=HostInterfaceNetworking-vboxnet0

CONF_DIR=./config
VM_APP_A_CONFDIR=${CONF_DIR}/04-ubuntu-vm-a
VM_APP_B_CONFDIR=${CONF_DIR}/05-ubuntu-vm-b
VM_APP_C_CONFDIR=${CONF_DIR}/06-ubuntu-vm-c

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

if [[ ${ACTION} = "vm-up" ]]; then

  if [[ ${VM_NAME} = "ubuntu-vm-a" ]]; then
    VM_CONFDIR=${VM_APP_A_CONFDIR}
  elif [[ ${VM_NAME} = "ubuntu-vm-b" ]]; then
    VM_CONFDIR=${VM_APP_B_CONFDIR}
  elif [[ ${VM_NAME} = "ubuntu-vm-c" ]]; then
    VM_CONFDIR=${VM_APP_C_CONFDIR}
  else
    echo "Please specify one of the following vms:"
    echo "  - ubuntu-vm-a"
    echo "  - ubuntu-vm-b"
    echo "  - ubuntu-vm-c"
    exit 1
  fi

  OVA_URL=https://cloud-images.ubuntu.com/jammy/20230110/jammy-server-cloudimg-amd64.ova
  OVA_VM_NAME=ubuntu-jammy-22.04-cloudimg-20230110

  VM_FILE=${CONF_DIR}/ubuntu-vm.ova
  VM_CLOUD_INIT_ISO=${VM_CONFDIR}/${VM_NAME}-cloud-init.iso
  CLOUD_INIT_USER_DATA=${VM_CONFDIR}/cloud-init/user-data
  CLOUD_INIT_META_DATA=${VM_CONFDIR}/cloud-init/meta-data

  if vboxmanage list vms | grep ${VM_NAME} &>/dev/null ; then
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

  if vboxmanage list runningvms | grep ${VM_NAME} &>/dev/null ; then
    echo "VM ${VM_NAME} already running"
  else
    # Start up the VM
    vboxmanage startvm ${VM_NAME} --type headless ;
  fi 

  # Get the bridge ip from the vm
  wait_vm_bridge_ip ${VM_NAME} ;
  VM_IP=$(get_vm_bridge_ip ${VM_NAME}) ;
  echo "VM ${VM_NAME} is available through ssh (tsbadmin/tsbadmin)" ;
  echo "ssh -i ${VM_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_IP}" ;

  exit 0
fi

if [[ ${ACTION} = "vm-down" ]]; then

  # Power off the VM
  vboxmanage controlvm ubuntu-vm-a poweroff 2>/dev/null ;
  vboxmanage controlvm ubuntu-vm-b poweroff 2>/dev/null ;
  vboxmanage controlvm ubuntu-vm-c poweroff 2>/dev/null ;

  exit 0
fi

if [[ ${ACTION} = "info" ]]; then

  if VM_A_IP=$(get_vm_bridge_ip ubuntu-vm-a 2>/dev/null) ; then
    echo "ssh -i ${VM_APP_A_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_A_IP} -- docker logs app-a -f" ;
  fi
  if VM_B_IP=$(get_vm_bridge_ip ubuntu-vm-b 2>/dev/null) ; then
    echo "ssh -i ${VM_APP_B_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_B_IP} -- docker logs app-b -f" ;
  fi
  if VM_C_IP=$(get_vm_bridge_ip ubuntu-vm-c 2>/dev/null) ; then
    echo "ssh -i ${VM_APP_C_CONFDIR}/tsbadmin -o StrictHostKeyChecking=no tsbadmin@${VM_C_IP} -- docker logs app-c -f" ;
  fi

  exit 0
fi

if [[ ${ACTION} = "clean" ]]; then

  # Remove the VM
  vboxmanage controlvm ubuntu-vm-a poweroff 2>/dev/null ;
  vboxmanage unregistervm ubuntu-vm-a --delete 2>/dev/null ;
  vboxmanage controlvm ubuntu-vm-b poweroff 2>/dev/null ;
  vboxmanage unregistervm ubuntu-vm-b --delete 2>/dev/null ;
  vboxmanage controlvm ubuntu-vm-c poweroff 2>/dev/null ;
  vboxmanage unregistervm ubuntu-vm-c --delete 2>/dev/null ;

  exit 0
fi

echo "Please specify one of the following action:"
echo "  - vm-up"
echo "  - vm-down"
echo "  - info"
echo "  - clean"
exit 1