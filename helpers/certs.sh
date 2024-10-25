#!/usr/bin/env bash
#
# Helper functions for certificate generation.
#
HELPERS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") ;
# shellcheck source=/dev/null
source "${HELPERS_DIR}/print.sh" ;

# Install a root certificate
#   args:
#     (1) root certificate source file
#     (2) root certificate destination file (optional, default 'tsb-single-vm-ca.pem')
function install_root_cert {
  [[ -z "${1}" ]] && print_error "Please provide root certificate source file as 1st argument" && return 2 || local cert_source_file="${1}" ;
  [[ -z "${2}" ]] && local cert_destination_file="tsb-single-vm-ca.crt" || local cert_destination_file="${2}" ;

  if [[ "${cert_destination_file}" != *.crt ]]; then
      print_warning "Warning: cert_destination_file does not end with .crt" ;
      print_error "Certificates must have a .crt extension in order to be included by update-ca-certificates" ;
      return 1 ;
  fi
  if [[ ! -f "${cert_source_file}" ]]; then
    print_error "File ${cert_source_file} does not exist" ;
    return ;
  fi
  sudo cp "${cert_source_file}" "/usr/local/share/ca-certificates/${cert_destination_file}" ;
  sudo update-ca-certificates ;
}

# Generate a self signed root certificate
#   args:
#     (1) output directory
function generate_root_cert {
  [[ -z "${1}" ]] && print_error "Please provide output directory as 1st argument" && return 2 || local output_dir="${1}" ;

  mkdir -p "${output_dir}" ;
  if [[ -f "${output_dir}/root-cert.pem" ]]; then
    echo "File ${output_dir}/root-cert.pem already exists... skipping root certificate generation" ;
    return ;
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout "${output_dir}/root-key.pem" \
    -subj "/CN=Root CA/O=Istio" \
    -out "${output_dir}/root-cert.csr" ;
  openssl x509 -req -sha512 -days 3650 \
    -signkey "${output_dir}/root-key.pem" \
    -in "${output_dir}/root-cert.csr" \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign") \
    -out "${output_dir}/root-cert.pem" ;
  print_info "New root certificate generated at ${output_dir}/root-cert.pem" ;
}

# Generate an intermediate istio certificate signed by the self signed root certificate
#   args:
#     (1) output directory
#     (2) cluster name
function generate_istio_cert {
  [[ -z "${1}" ]] && print_error "Please provide output directory as 1st argument" && return 2 || local output_dir="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;

  if [[ ! -f "${output_dir}/root-cert.pem" ]]; then generate_root_cert "${output_dir}" ; fi
  if [[ -f "${output_dir}/${cluster_name}/ca-cert.pem" ]]; then 
    echo "File ${output_dir}/${cluster_name}/ca-cert.pem already exists... skipping istio certificate generation" ;
    return ;
  fi

  mkdir -p "${output_dir}/${cluster_name}" ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout "${output_dir}/${cluster_name}/ca-key.pem" \
    -subj "/CN=Intermediate CA/O=Istio/L=${cluster_name}" \
    -out "${output_dir}/${cluster_name}/ca-cert.csr" ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA "${output_dir}/root-cert.pem" \
    -CAkey "${output_dir}/root-key.pem" \
    -in "${output_dir}/${cluster_name}/ca-cert.csr" \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign\nsubjectAltName=DNS.1:istiod.istio-system.svc") \
    -out "${output_dir}/${cluster_name}/ca-cert.pem" ;
  cat "${output_dir}/${cluster_name}/ca-cert.pem" "${output_dir}/root-cert.pem" >> "${output_dir}/${cluster_name}/cert-chain.pem" ;
  cp "${output_dir}/root-cert.pem" "${output_dir}/${cluster_name}/root-cert.pem" ;
  print_info "New intermediate istio certificate generated at ${output_dir}/${cluster_name}/ca-cert.pem" ;
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) output directory
#     (2) client workload name
#     (3) domain name
function generate_client_cert {
  [[ -z "${1}" ]] && print_error "Please provide output directory as 1st argument" && return 2 || local output_dir="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide client workload name as 2nd argument" && return 2 || local workload_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide domain name as 3rd argument" && return 2 || local domain_name="${3}" ;

  if [[ ! -f "${output_dir}/root-cert.pem" ]]; then generate_root_cert "${output_dir}" ; fi
  if [[ -f "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.pem" ]]; then
    echo "File ${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.pem already exists... skipping client certificate generation" ;
    return ;
  fi

  mkdir -p "${output_dir}/${workload_name}" ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-key.pem" \
    -subj "/CN=${workload_name}.${domain_name}/O=Customer/C=US/ST=CA" \
    -out "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.csr" ;
  openssl x509 -req -sha512 -days 3650 -set_serial 1 \
    -CA "${output_dir}/root-cert.pem" \
    -CAkey "${output_dir}/root-key.pem" \
    -in "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.csr" \
    -out "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.pem" ;
  cat "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.pem" "${output_dir}/root-cert.pem" >> "${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert-chain.pem" ;
  cp "${output_dir}/root-cert.pem" "${output_dir}/${workload_name}/root-cert.pem" ;
  print_info "New client certificate generated at ${output_dir}/${workload_name}/client.${workload_name}.${domain_name}-cert.pem" ;
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) output directory
#     (2) server workload name
#     (3) domain name
function generate_server_cert {
  [[ -z "${1}" ]] && print_error "Please provide output directory as 1st argument" && return 2 || local output_dir="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide server workload name as 2nd argument" && return 2 || local workload_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide domain name as 3rd argument" && return 2 || local domain_name="${3}" ;

  if [[ ! -f "${output_dir}/root-cert.pem" ]]; then generate_root_cert "${output_dir}" ; fi
  if [[ -f "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.pem" ]]; then
    echo "File ${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.pem already exists... skipping server certificate generation" ;
    return ;
  fi

  mkdir -p "${output_dir}/${workload_name}" ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-key.pem" \
    -subj "/CN=${workload_name}.${domain_name}/O=Tetrate/C=US/ST=CA" \
    -out "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.csr" ;
  openssl x509 -req -sha512 -days 3650 -set_serial 0 \
    -CA "${output_dir}/root-cert.pem" \
    -CAkey "${output_dir}/root-key.pem" \
    -in "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.csr" \
    -extfile <(printf "subjectAltName=DNS:%s,DNS:%s.%s,DNS:*.%s,DNS:localhost" "${workload_name}" "${workload_name}" "${domain_name}" "${domain_name}") \
    -out "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.pem" ;
  cat "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.pem" "${output_dir}/root-cert.pem" >> "${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert-chain.pem" ;
  cp "${output_dir}/root-cert.pem" "${output_dir}/${workload_name}/root-cert.pem" ;
  print_info "New server certificate generated at ${output_dir}/${workload_name}/server.${workload_name}.${domain_name}-cert.pem" ;
}

### Cert Generation Tests

# generate_root_cert "/tmp/certs" ;
# generate_istio_cert "/tmp/certs" "mgmt" ;
# generate_istio_cert "/tmp/certs" "active" ;
# generate_istio_cert "/tmp/certs" "standby" ;
# generate_client_cert "/tmp/certs" "client1" "tetrate.prod" ;
# generate_client_cert "/tmp/certs" "client2" "tetrate.prod" ;
# generate_server_cert "/tmp/certs" "server1" "tetrate.prod" ;
# generate_server_cert "/tmp/certs" "server2" "tetrate.prod" ;
