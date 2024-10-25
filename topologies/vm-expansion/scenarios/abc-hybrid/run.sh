#!/usr/bin/env bash
SCENARIO_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;

if [[ -z "${BASE_DIR}" ]]; then
    echo "BASE_DIR environment variable is not set or is empty" ;
    exit 1 ;
fi

# shellcheck source=/dev/null
source "${BASE_DIR}/env.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/certs.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/print.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/registry.sh" ;
# shellcheck source=/dev/null
source "${BASE_DIR}/helpers/tsb.sh" ;

ACTION=${1} ;

# This function provides help information for the script.
#
function help() {
  echo "Usage: $0 <command> [options]" ;
  echo "Commands:" ;
  echo "  --deploy: delpoy the scenario" ;
  echo "  --undeploy: undeploy the scenario" ;
  echo "  --info: print info about the scenario" ;
}

# Onboard vm by uploading onboarding script and running it
#   args:
#     (1) vm name
#     (2) onboarding script path
function onboard_vm {
  local vm_ip; vm_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${1}")

  # scp onboarding script
  expect <<DONE
  spawn scp -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ${2} ubuntu@${vm_ip}:/home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE

  # ssh bootstrap onboarding script
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip} -- chmod +x /home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip} -- /home/ubuntu/onboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect "Onboarding finished"
DONE
}

# Offboard vm by uploading offboarding script and running it
#   args:
#     (1) vm name
#     (2) offboarding script path
function offboard_vm {
  local vm_ip; vm_ip=$(docker container inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${1}")

  # scp offboarding script
  expect <<DONE
  spawn scp -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ${2} ubuntu@${vm_ip}:/home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE

  # ssh bootstrap offboarding script
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip} -- chmod +x /home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect eof
DONE
  expect <<DONE
  spawn ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" ubuntu@${vm_ip} -- /home/ubuntu/offboard-vm.sh
  expect "password:" { send "ubuntu\\r" }
  expect "Offboarding finished"
DONE
}

# Generate vm jwt tokens
# In case you want to change some attributes of the JWT token, please check the docs and adjust the proper files accordingly
#   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding#allow-workloads-to-authenticate-themselves-by-means-of-a-jwt-token
#   REF: https://github.com/tet./onboarding-agent-sample-jwt-credential-plugin --docsrateio/onboarding-agent-sample-jwt-credential-plugin
function generate_vm_jwt_tokens {
  local mp_output_dir; mp_output_dir=$(get_mp_output_dir) ;

  if ! [[ -f "${ONBOARDING_AGENT_JWT_PLUGIN}" ]]; then
    curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
      | tar --directory "${BASE_DIR}/output" -xz onboarding-agent-sample-jwt-credential-plugin ;
    chmod +x "${BASE_DIR}/output/onboarding-agent-sample-jwt-credential-plugin" ;
  fi

  if ! [[ -f "${mp_output_dir}/vm1/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm1.demo.tetrate.io" ;
    export SAMPLE_JWT_SUBJECT="vm1.demo.tetrate.io" ;
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes" ;
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm1,instance_role=app-b,region=region1" ;
    export SAMPLE_JWT_EXPIRATION="87600h" ;
    "${BASE_DIR}/output/onboarding-agent-sample-jwt-credential-plugin" generate key -o "${mp_output_dir}/vm1/sample-jwt-issuer" ;
  fi

  if ! [[ -f "${mp_output_dir}/vm2/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm2.demo.tetrate.io" ;
    export SAMPLE_JWT_SUBJECT="vm2.demo.tetrate.io" ;
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes" ;
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm2,instance_role=app-b,region=region1" ;
    export SAMPLE_JWT_EXPIRATION="87600h" ;
    "${BASE_DIR}/output/onboarding-agent-sample-jwt-credential-plugin" generate key -o "${mp_output_dir}/vm2/sample-jwt-issuer" ;
  fi

  if ! [[ -f "${mp_output_dir}/vm3/sample-jwt-issuer.jwks" ]]; then
    export SAMPLE_JWT_ISSUER="https://issuer-vm3.demo.tetrate.io" ;
    export SAMPLE_JWT_SUBJECT="vm3.demo.tetrate.io" ;
    export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes" ;
    export SAMPLE_JWT_ATTRIBUTES="instance_name=vm3,instance_role=app-c,region=region1" ;
    export SAMPLE_JWT_EXPIRATION="87600h" ;
    "${BASE_DIR}/output/onboarding-agent-sample-jwt-credential-plugin" generate key -o "${mp_output_dir}/vm3/sample-jwt-issuer" ;
  fi
}


# This function deploys the scenario.
#
function deploy() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local install_repo_url; install_repo_url="$(get_local_registry_endpoint)" ;
  local mp_output_dir; mp_output_dir="$(get_mp_output_dir)" ;
  
  # Set TSB_INSTALL_REPO_URL for envsubst of image repo

  mkdir -p "${mp_output_dir}/vm1" ;
  mkdir -p "${mp_output_dir}/vm2" ;
  mkdir -p "${mp_output_dir}/vm3" ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Generate vm gateway and application ingress certificate
  CERTS_BASE_DIR="${BASE_DIR}/output/certs" ;
  generate_server_cert "${CERTS_BASE_DIR}" "vm-onboarding" "demo.tetrate.io" ;
  generate_server_cert "${CERTS_BASE_DIR}" "abc" "demo.tetrate.io" ;

  # Deploy tsb cluster and tenant objects
  tctl apply -f "${SCENARIO_DIR}/tsb/01-cluster.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/02-tenant.yaml" ;

  # Generate jwt tokens for vms and patch control plane of mgmt cluster with jwks configurations
  generate_vm_jwt_tokens ;
  # shellcheck disable=SC2002
  JWKS_VM1=$(cat "${mp_output_dir}/vm1/sample-jwt-issuer.jwks" | tr '\n' ' ' | tr -d ' ') ; export JWKS_VM1 ;
  # shellcheck disable=SC2002
  JWKS_VM2=$(cat "${mp_output_dir}/vm2/sample-jwt-issuer.jwks" | tr '\n' ' ' | tr -d ' ') ; export JWKS_VM2 ;
  # shellcheck disable=SC2002
  JWKS_VM3=$(cat "${mp_output_dir}/vm3/sample-jwt-issuer.jwks" | tr '\n' ' ' | tr -d ' ') ; export JWKS_VM3 ;

  export TSB_INSTALL_REPO_URL=${install_repo_url} ;
  envsubst < "${SCENARIO_DIR}/patch/onboarding-vm-patch-template.yaml" > "${mp_output_dir}/onboarding-vm-patch.yaml" ;

  kubectl --context mgmt -n istio-system patch controlplanes controlplane --patch-file "${mp_output_dir}/onboarding-vm-patch.yaml" --type merge ;

  # Deploy kubernetes objects in mgmt cluster
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" ;
  if ! kubectl --context mgmt get secret app-abc-cert -n gateway-abc &>/dev/null ; then
    kubectl --context mgmt create secret tls app-abc-cert -n gateway-abc \
      --key "${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-key.pem" \
      --cert "${CERTS_BASE_DIR}/abc/server.abc.demo.tetrate.io-cert.pem" ;
  fi
  if ! kubectl --context mgmt get secret vm-onboarding -n istio-system &>/dev/null ; then
    kubectl --context mgmt create secret tls vm-onboarding -n istio-system \
      --key "${CERTS_BASE_DIR}/vm-onboarding/server.vm-onboarding.demo.tetrate.io-key.pem" \
      --cert "${CERTS_BASE_DIR}/vm-onboarding/server.vm-onboarding.demo.tetrate.io-cert.pem" ;
  fi
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/02-serviceaccount.yaml" ;
  mkdir -p "${BASE_DIR}/output/mgmt/k8s" ;
  envsubst < "${SCENARIO_DIR}/k8s/mgmt/03-deployment.yaml" > "${BASE_DIR}/output/mgmt/k8s/03-deployment.yaml" ;
  kubectl --context mgmt apply -f "${BASE_DIR}/output/mgmt/k8s/03-deployment.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/04-workload-group.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/05-service.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/06-onboarding-policy.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/07-sidecar.yaml" ;
  kubectl --context mgmt apply -f "${SCENARIO_DIR}/k8s/mgmt/08-ingress-gateway.yaml" ;

  # Get vm gateway external load balancer ip address
  echo "Getting vm gateway exernal load balancer ip address" ;
  local vm_gw_ip ;
  while ! vm_gw_ip=$(kubectl --context mgmt get svc -n istio-system vmgateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    echo -n "." ;
  done
  echo "DONE" ;

  # Wait for onboarding-plane and onboarding-repository to be ready
  kubectl --context mgmt wait deployment -n istio-system onboarding-plane --for condition=Available=True --timeout=600s ;
  kubectl --context mgmt wait deployment -n istio-system onboarding-repository --for condition=Available=True --timeout=600s ;

  # Onboard vms
  export TSB_VM_ONBOARDING_ENDPOINT=${vm_gw_ip} ;
  # shellcheck disable=SC2002
  JWK_VM1=$(cat "${mp_output_dir}/vm1/sample-jwt-issuer.jwk" | tr '\n' ' ' | tr -d ' ') ; export JWK_VM1 ;
  # shellcheck disable=SC2002
  JWK_VM2=$(cat "${mp_output_dir}/vm2/sample-jwt-issuer.jwk" | tr '\n' ' ' | tr -d ' ') ; export JWK_VM2 ;
  # shellcheck disable=SC2002
  JWK_VM3=$(cat "${mp_output_dir}/vm3/sample-jwt-issuer.jwk" | tr '\n' ' ' | tr -d ' ') ; export JWK_VM3 ;
  envsubst < "${SCENARIO_DIR}/vm/vm1/onboard-vm-template.sh" > "${mp_output_dir}/vm1/onboard-vm.sh" ;
  onboard_vm "vm1" "${mp_output_dir}/vm1/onboard-vm.sh" ;
  envsubst < "${SCENARIO_DIR}/vm/vm2/onboard-vm-template.sh" > "${mp_output_dir}/vm2/onboard-vm.sh" ;
  onboard_vm "vm2" "${mp_output_dir}/vm2/onboard-vm.sh" ;
  envsubst < "${SCENARIO_DIR}/vm/vm3/onboard-vm-template.sh" > "${mp_output_dir}/vm3/onboard-vm.sh" ;
  onboard_vm "vm3" "${mp_output_dir}/vm3/onboard-vm.sh" ;

  # Deploy tsb objects
  tctl apply -f "${SCENARIO_DIR}/tsb/03-workspace.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/04-workspace-setting.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/05-group.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/06-ingress-gateway.yaml" ;
  tctl apply -f "${SCENARIO_DIR}/tsb/07-security-setting.yaml" ;
}


# This function undeploys the scenario.
#
function undeploy() {

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" "admin" "admin" ;

  # Delete tsb configuration
  for tsb_yaml_files in $(find "${SCENARIO_DIR}/tsb" -name '*.yaml' ! -name '01-cluster.yaml' | sort -r) ; do
    echo "Going to delete ${tsb_yaml_files}" ;
    tctl delete -f "${tsb_yaml_files}" 2>/dev/null ;
    sleep 1 ;
  done

  echo "Sleep 30 seconds to allow TSB to delete all the objects" ;
  sleep 30 ;

  # Delete kubernetes configuration in mgmt cluster
  kubectl --context mgmt delete -f "${SCENARIO_DIR}/k8s/mgmt/01-namespace.yaml" --wait=true 2>/dev/null ;

  offboard_vm "vm1" "${SCENARIO_DIR}/vm/offboard-vm.sh" ;
  offboard_vm "vm2" "${SCENARIO_DIR}/vm/offboard-vm.sh" ;
  offboard_vm "vm3" "${SCENARIO_DIR}/vm/offboard-vm.sh" ;
}


# This function prints info about the scenario.
#
function info() {

  local certs_base_dir; certs_base_dir="$(get_certs_output_dir)" ;
  local ingress_mgmt_gw_ip ;

  while ! ingress_mgmt_gw_ip=$(kubectl --context mgmt get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    sleep 1 ;
  done

  echo "*************************************" ;
  echo "*** VM-EXPANSION Traffic Commands ***" ;
  echo "*************************************" ;
  echo ;
  echo "Traffic through Management Ingress Gateway" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ingress_mgmt_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "In a loop" ;
  print_command "while true ; do
  curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:443:${ingress_mgmt_gw_ip}\" --cacert ${certs_base_dir}/root-cert.pem \"https://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\" ;
  sleep 1 ;
done"
  echo ;
}


# Main execution
#
case "${ACTION}" in
  --help)
    help ;
    ;;
  --deploy)
    deploy ;
    ;;
  --undeploy)
    undeploy ;
    ;;
  --info)
    info ;
    ;;
  *)
    print_error "Invalid option. Use 'help' to see available commands." ;
    help ;
    ;;
esac