#!/usr/bin/env bash
#
# Helper functions for certificate generation.
#
ROOT_DIR=${1}
CERT_OUTPUT_DIR=${1}/output/certs

source ${ROOT_DIR}/helpers.sh

function get_certs_base_dir {
  echo ${CERT_OUTPUT_DIR}
}

# Generate a self signed root certificate
function generate_root_cert {
  mkdir -p ${CERT_OUTPUT_DIR} ;
  if [[ -f "${CERT_OUTPUT_DIR}/root-cert.pem" ]]; then
    echo "File ${CERT_OUTPUT_DIR}/root-cert.pem already exists... skipping root certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERT_OUTPUT_DIR}/root-key.pem \
    -subj "/CN=Root CA/O=Istio" \
    -out ${CERT_OUTPUT_DIR}/root-cert.csr ;
  openssl x509 -req -sha512 -days 3650 \
    -signkey ${CERT_OUTPUT_DIR}/root-key.pem \
    -in ${CERT_OUTPUT_DIR}/root-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign") \
    -out ${CERT_OUTPUT_DIR}/root-cert.pem ;
  print_info "New root certificate generated at ${CERT_OUTPUT_DIR}/root-cert.pem"
}

# Generate an intermediate istio certificate signed by the self signed root certificate
#   args:
#     (1) cluster name
function generate_istio_cert {
  if [[ ! -f "${CERT_OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ; fi
  if [[ -f "${CERT_OUTPUT_DIR}/${1}/ca-cert.pem" ]]; then echo "File ${CERT_OUTPUT_DIR}/${1}/ca-cert.pem already exists... skipping istio certificate generation" ; return ; fi

  mkdir -p ${CERT_OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERT_OUTPUT_DIR}/${1}/ca-key.pem \
    -subj "/CN=Intermediate CA/O=Istio/L=${1}" \
    -out ${CERT_OUTPUT_DIR}/${1}/ca-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${CERT_OUTPUT_DIR}/root-cert.pem \
    -CAkey ${CERT_OUTPUT_DIR}/root-key.pem \
    -in ${CERT_OUTPUT_DIR}/${1}/ca-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign\nsubjectAltName=DNS.1:istiod.istio-system.svc") \
    -out ${CERT_OUTPUT_DIR}/${1}/ca-cert.pem ;
  cat ${CERT_OUTPUT_DIR}/${1}/ca-cert.pem ${CERT_OUTPUT_DIR}/root-cert.pem >> ${CERT_OUTPUT_DIR}/${1}/cert-chain.pem ;
  cp ${CERT_OUTPUT_DIR}/root-cert.pem ${CERT_OUTPUT_DIR}/${1}/root-cert.pem ;
  print_info "New intermediate istio certificate generated at ${CERT_OUTPUT_DIR}/${1}/ca-cert.pem"
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) client workload name
#     (2) domain name
function generate_client_cert {
  if [[ ! -f "${CERT_OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ${CERT_OUTPUT_DIR}; fi
  if [[ -f "${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem" ]]; then echo "File ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem already exists... skipping client certificate generation" ; return ; fi

  mkdir -p ${CERT_OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-key.pem \
    -subj "/CN=${1}.${2}/O=Customer/C=US/ST=CA" \
    -out ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 1 \
    -CA ${CERT_OUTPUT_DIR}/root-cert.pem \
    -CAkey ${CERT_OUTPUT_DIR}/root-key.pem \
    -in ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.csr \
    -out ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem ;
  cat ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem ${CERT_OUTPUT_DIR}/root-cert.pem >> ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert-chain.pem ;
  cp ${CERT_OUTPUT_DIR}/root-cert.pem ${CERT_OUTPUT_DIR}/${1}/root-cert.pem ;
  print_info "New client certificate generated at ${CERT_OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem"
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) server workload name
#     (2) domain name
function generate_server_cert {
  if [[ ! -f "${CERT_OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ${CERT_OUTPUT_DIR}; fi
  if [[ -f "${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem" ]]; then echo "File ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem already exists... skipping server certificate generation" ; return ; fi

  mkdir -p ${CERT_OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-key.pem \
    -subj "/CN=${1}.${2}/O=Tetrate/C=US/ST=CA" \
    -out ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 0 \
    -CA ${CERT_OUTPUT_DIR}/root-cert.pem \
    -CAkey ${CERT_OUTPUT_DIR}/root-key.pem \
    -in ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.csr \
    -extfile <(printf "subjectAltName=DNS:${1}.${2},DNS:${2},DNS:*.${2},DNS:localhost") \
    -out ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem ;
  cat ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem ${CERT_OUTPUT_DIR}/root-cert.pem >> ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert-chain.pem ;
  cp ${CERT_OUTPUT_DIR}/root-cert.pem ${CERT_OUTPUT_DIR}/${1}/root-cert.pem ;
  print_info "New server certificate generated at ${CERT_OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem"
}

### Cert Generation Tests

# generate_root_cert ;
# generate_istio_cert mgmt ;
# generate_istio_cert active-cluster ;
# generate_istio_cert standby-cluster ;
# generate_client_cert vm-onboarding tetrate.prod ;
# generate_server_cert vm-onboarding tetrate.prod ;
