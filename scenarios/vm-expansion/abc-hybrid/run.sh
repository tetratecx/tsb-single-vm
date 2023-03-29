#!/usr/bin/env bash
SCENARIO_ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
ROOT_DIR=${1}
ACTION=${2}
source ${ROOT_DIR}/env.sh ${ROOT_DIR}
source ${ROOT_DIR}/certs.sh ${ROOT_DIR}
source ${ROOT_DIR}/helpers.sh

INSTALL_REPO_URL=$(get_install_repo_url) ;

# Login as admin into tsb
#   args:
#     (1) organization
function login_tsb_admin {
  expect <<DONE
  spawn tctl login --username admin --password admin --org ${1}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Onboard vm by uploading onboarding script and running it
#   args:
#     (1) vm name
#     (2) onboarding script path
function onboard_vm {
  VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1})

  # scp onboarding script
  expect <<DONE
  spawn scp -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ${2} ubuntu@${VM_IP}:/home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE

  # ssh bootstrap onboarding script
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP} -- chmod +x /home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP} -- /home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect "Onboarding finished"
DONE
}

# Offboard vm by uploading offboarding script and running it
#   args:
#     (1) vm name
#     (2) offboarding script path
function offboard_vm {
  VM_IP=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1})

  # scp offboarding script
  expect <<DONE
  spawn scp -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ${2} ubuntu@${VM_IP}:/home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE

  # ssh bootstrap offboarding script
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP} -- chmod +x /home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${VM_IP} -- /home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect "Offboarding finished"
DONE
}

# Generate vm jwt tokens
# In case you want to change some attributes of the JWT token, please check the docs and adjust the proper files accordingly
#   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding#allow-workloads-to-authenticate-themselves-by-means-of-a-jwt-token
#   REF: https://github.com/tet./onboarding-agent-sample-jwt-credential-plugin --docsrateio/onboarding-agent-sample-jwt-credential-plugin
function generate_vm_jwt_tokens {
  MP_OUTPUT_DIR=$(get_mp_output_dir)

  if ! [[ -f "${ONBOARDING_AGENT_JWT_PLUGIN}" ]]; then
    curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
      | tar --directory ${ROOT_DIR}/output -xz onboarding-agent-sample-jwt-credential-plugin ;
    chmod +x ${ROOT_DIR}/output/onboarding-agent-sample-jwt-credential-plugin ;
  fi

  if ! [[ -f "${MP_OUTPUT_DIR}/vm1/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm1.demo.tetrate.io"
    export SAMPLE_JWT_SUBJECT="vm1.demo.tetrate.io"
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes"
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm1,instance_role=app-b,region=region1"
    export SAMPLE_JWT_EXPIRATION="87600h"
    ${ROOT_DIR}/output/onboarding-agent-sample-jwt-credential-plugin generate key -o ${MP_OUTPUT_DIR}/vm1/sample-jwt-issuer ;
  fi

  if ! [[ -f "${MP_OUTPUT_DIR}/vm2/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm2.demo.tetrate.io"
    export SAMPLE_JWT_SUBJECT="vm2.demo.tetrate.io"
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes"
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm2,instance_role=app-b,region=region1"
    export SAMPLE_JWT_EXPIRATION="87600h"
    ${ROOT_DIR}/output/onboarding-agent-sample-jwt-credential-plugin generate key -o ${MP_OUTPUT_DIR}/vm2/sample-jwt-issuer ;
  fi

  if ! [[ -f "${MP_OUTPUT_DIR}/vm3/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm3.demo.tetrate.io"
    export SAMPLE_JWT_SUBJECT="vm3.demo.tetrate.io"
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes"
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm3,instance_role=app-c,region=region1"
    export SAMPLE_JWT_EXPIRATION="87600h"
    ${ROOT_DIR}/output/onboarding-agent-sample-jwt-credential-plugin generate key -o ${MP_OUTPUT_DIR}/vm3/sample-jwt-issuer ;
  fi
}


if [[ ${ACTION} = "deploy" ]]; then

  # Set TSB_INSTALL_REPO_URL for envsubst of image repo
  export TSB_INSTALL_REPO_URL=${INSTALL_REPO_URL}

  CERTS_BASE_DIR=$(get_certs_base_dir) ;
  MP_OUTPUT_DIR=$(get_mp_output_dir) ;
  mkdir -p ${MP_OUTPUT_DIR}/vm1 ;
  mkdir -p ${MP_OUTPUT_DIR}/vm2 ;
  mkdir -p ${MP_OUTPUT_DIR}/vm3 ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Generate vm gateway and application ingress certificate
  generate_server_cert vm-onboarding demo.tetrate.io ;
  generate_server_cert abc demo.tetrate.io ;

  # Deploy tsb cluster and tenant objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/01-cluster.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/02-tenant.yaml ;

  # Generate jwt tokens for vms and patch control plane of mgmt cluster with jwks configurations
  generate_vm_jwt_tokens ;
  export JWKS_VM1=$(cat ${MP_OUTPUT_DIR}/vm1/sample-jwt-issuer.jwks | tr '\n' ' ' | tr -d ' ')
  export JWKS_VM2=$(cat ${MP_OUTPUT_DIR}/vm2/sample-jwt-issuer.jwks | tr '\n' ' ' | tr -d ' ')
  export JWKS_VM3=$(cat ${MP_OUTPUT_DIR}/vm3/sample-jwt-issuer.jwks | tr '\n' ' ' | tr -d ' ')
  envsubst < ${SCENARIO_ROOT_DIR}/patch/onboarding-vm-patch-template.yaml > ${MP_OUTPUT_DIR}/onboarding-vm-patch.yaml ;
  kubectl --context mgmt-cluster -n istio-system patch controlplanes controlplane --patch-file ${MP_OUTPUT_DIR}/onboarding-vm-patch.yaml --type merge ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/01-namespace.yaml ;
  if ! kubectl --context mgmt-cluster get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context mgmt-cluster create secret tls app-abc-cert -n gateway-abc \
      --key ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem ;
  fi
  if ! kubectl --context mgmt-cluster get secret vm-onboarding -n istio-system &>/dev/null ; then
    kubectl --context mgmt-cluster create secret tls vm-onboarding -n istio-system \
      --key ${CERTS_BASE_DIR}/vm-onboarding/server.vm-onboarding.demo.tetrate.io-key.pem \
      --cert ${CERTS_BASE_DIR}/vm-onboarding/server.vm-onboarding.demo.tetrate.io-cert.pem ;
  fi
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/01-namespace.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/02-serviceaccount.yaml ;
  mkdir -p ${ROOT_DIR}/output/mgmt-cluster/k8s ;
  envsubst < ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/03-deployment.yaml > ${ROOT_DIR}/output/mgmt-cluster/k8s/03-deployment.yaml ;
  kubectl --context mgmt-cluster apply -f ${ROOT_DIR}/output/mgmt-cluster/k8s/03-deployment.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/04-workload-group.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/05-service.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/06-onboarding-policy.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/07-sidecar.yaml ;
  kubectl --context mgmt-cluster apply -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster/08-ingress-gateway.yaml ;

  # Get vm gateway external load balancer ip address
  echo "Getting vm gateway exernal load balancer ip address"
  while ! VM_GW_IP=$(kubectl --context mgmt-cluster get svc -n istio-system vmgateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    echo -n "."
  done
  echo "DONE"

  # Wait for onboarding-plane and onboarding-repository to be ready
  kubectl --context mgmt-cluster wait deployment -n istio-system onboarding-plane --for condition=Available=True --timeout=600s ;
  kubectl --context mgmt-cluster wait deployment -n istio-system onboarding-repository --for condition=Available=True --timeout=600s ;

  # Onboard vms
  export TSB_VM_ONBOARDING_ENDPOINT=${VM_GW_IP}
  export JWK_VM1=$(cat ${MP_OUTPUT_DIR}/vm1/sample-jwt-issuer.jwk | tr '\n' ' ' | tr -d ' ')
  export JWK_VM2=$(cat ${MP_OUTPUT_DIR}/vm2/sample-jwt-issuer.jwk | tr '\n' ' ' | tr -d ' ')
  export JWK_VM3=$(cat ${MP_OUTPUT_DIR}/vm3/sample-jwt-issuer.jwk | tr '\n' ' ' | tr -d ' ')
  envsubst < ${SCENARIO_ROOT_DIR}/vm/vm1/onboard-vm-template.sh > ${MP_OUTPUT_DIR}/vm1/onboard-vm.sh ;
  onboard_vm "vm1" ${MP_OUTPUT_DIR}/vm1/onboard-vm.sh ;
  envsubst < ${SCENARIO_ROOT_DIR}/vm/vm2/onboard-vm-template.sh > ${MP_OUTPUT_DIR}/vm2/onboard-vm.sh ;
  onboard_vm "vm2" ${MP_OUTPUT_DIR}/vm2/onboard-vm.sh ;
  envsubst < ${SCENARIO_ROOT_DIR}/vm/vm3/onboard-vm-template.sh > ${MP_OUTPUT_DIR}/vm3/onboard-vm.sh ;
  onboard_vm "vm3" ${MP_OUTPUT_DIR}/vm3/onboard-vm.sh ;

  # Deploy tsb objects
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/03-workspace.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/04-workspace-setting.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/05-group.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/06-ingress-gateway.yaml ;
  tctl apply -f ${SCENARIO_ROOT_DIR}/tsb/07-security-setting.yaml ;

  exit 0
fi


if [[ ${ACTION} = "undeploy" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Delete tsb configuration
  for TSB_FILE in $(ls -1 ${SCENARIO_ROOT_DIR}/tsb | sort -r) ; do
    echo "Going to delete tsb/${TSB_FILE}"
    tctl delete -f ${SCENARIO_ROOT_DIR}/tsb/${TSB_FILE} 2>/dev/null ;
  done

  # Delete kubernetes configuration in mgmt cluster
  kubectl --context mgmt-cluster delete -f ${ROOT_DIR}/output/mgmt-cluster/k8s/03-deployment.yaml 2>/dev/null ;
  kubectl --context mgmt-cluster delete -f ${SCENARIO_ROOT_DIR}/k8s/mgmt-cluster 2>/dev/null ;

  offboard_vm "vm1" ${SCENARIO_ROOT_DIR}/vm/offboard-vm.sh ;
  offboard_vm "vm2" ${SCENARIO_ROOT_DIR}/vm/offboard-vm.sh ;
  offboard_vm "vm3" ${SCENARIO_ROOT_DIR}/vm/offboard-vm.sh ;

  exit 0
fi


if [[ ${ACTION} = "info" ]]; then

  INGRESS_MGMT_GW_IP=$(kubectl --context mgmt-cluster get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  echo "****************************"
  echo "*** ABC Traffic Commands ***"
  echo "****************************"
  echo
  echo "Traffic through Management Ingress Gateway"
  print_command "curl -k -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${INGRESS_MGMT_GW_IP}\" --cacert ca.crt=certs/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\""
  echo
  exit 0
fi


echo "Please specify one of the following action:"
echo "  - deploy"
echo "  - undeploy"
echo "  - info"
exit 1
