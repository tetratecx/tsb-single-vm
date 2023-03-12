#!/usr/bin/env bash
#
# Helper functions for certificate generation.
#
ROOT_DIR=${1}
OUTPUT_DIR=${1}/output/certs

function get_certs_base_dir {
  echo ${OUTPUT_DIR}
}

# Generate a self signed root certificate
function generate_root_cert {
  mkdir -p ${OUTPUT_DIR} ;
  if [[ -f "${OUTPUT_DIR}/root-cert.pem" ]]; then 
    echo "File ${OUTPUT_DIR}/root-cert.pem already exists... skipping certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUTPUT_DIR}/root-key.pem \
    -subj "/CN=Root CA/O=Istio" \
    -out ${OUTPUT_DIR}/root-cert.csr ;
  openssl x509 -req -sha512 -days 3650 \
    -signkey ${OUTPUT_DIR}/root-key.pem \
    -in ${OUTPUT_DIR}/root-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign") \
    -out ${OUTPUT_DIR}/root-cert.pem ;
  echo "New root certificate generated at ${OUTPUT_DIR}/root-cert.pem"
}

# Generate an intermediate istio certificate signed by the self signed root certificate
#   args:
#     (1) cluster name
function generate_istio_cert {
  if [[ ! -f "${OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ${OUTPUT_DIR}; fi
  if [[ -f "${OUTPUT_DIR}/ca-cert.pem" ]]; then echo "File ${OUTPUT_DIR}/ca-cert.pem already exists... skipping certificate generation" ; return ; fi

  mkdir -p ${OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUTPUT_DIR}/${1}/ca-key.pem \
    -subj "/CN=Intermediate CA/O=Istio/L=${1}" \
    -out ${OUTPUT_DIR}/${1}/ca-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${OUTPUT_DIR}/root-cert.pem \
    -CAkey ${OUTPUT_DIR}/root-key.pem \
    -in ${OUTPUT_DIR}/${1}/ca-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign\nsubjectAltName=DNS.1:istiod.istio-system.svc") \
    -out ${OUTPUT_DIR}/${1}/ca-cert.pem ;
  cat ${OUTPUT_DIR}/${1}/ca-cert.pem ${OUTPUT_DIR}/root-cert.pem >> ${OUTPUT_DIR}/${1}/cert-chain.pem ;
  cp ${OUTPUT_DIR}/root-cert.pem ${OUTPUT_DIR}/${1}/root-cert.pem ;
  echo "New intermediate istio certificate generated at ${OUTPUT_DIR}/${1}/ca-cert.pem"
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) client workload name
#     (2) domain name
function generate_client_cert {
  if [[ ! -f "${OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ${OUTPUT_DIR}; fi
  if [[ -f "${OUTPUT_DIR}/ca-cert.pem" ]]; then echo "File ${OUTPUT_DIR}/ca-cert.pem already exists... skipping certificate generation" ; return ; fi

  mkdir -p ${OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUTPUT_DIR}/${1}/client.${1}.${2}-key.pem \
    -subj "/CN=${1}.${2}/O=Customer/C=US/ST=CA" \
    -out ${OUTPUT_DIR}/${1}/client.${1}.${2}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 1 \
    -CA ${OUTPUT_DIR}/root-cert.pem \
    -CAkey ${OUTPUT_DIR}/root-key.pem \
    -in ${OUTPUT_DIR}/${1}/client.${1}.${2}-cert.csr \
    -out ${OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem ;
  cat ${OUTPUT_DIR}/${1}/client.${1}.${2}-cert.pem ${OUTPUT_DIR}/root-cert.pem >> ${OUTPUT_DIR}/${1}/client.${1}.${2}-cert-chain.pem ;
  cp ${OUTPUT_DIR}/root-cert.pem ${OUTPUT_DIR}/${1}/root-cert.pem ;
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) server workload name
#     (2) domain name
function generate_server_cert {
  if [[ ! -f "${OUTPUT_DIR}/root-cert.pem" ]]; then generate_root_cert ${OUTPUT_DIR}; fi
  if [[ -f "${OUTPUT_DIR}/ca-cert.pem" ]]; then echo "File ${OUTPUT_DIR}/ca-cert.pem already exists... skipping certificate generation" ; return ; fi

  mkdir -p ${OUTPUT_DIR}/${1} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUTPUT_DIR}/${1}/server.${1}.${2}-key.pem \
    -subj "/CN=${1}.${2}/O=Tetrate/C=US/ST=CA" \
    -out ${OUTPUT_DIR}/${1}/server.${1}.${2}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 0 \
    -CA ${OUTPUT_DIR}/root-cert.pem \
    -CAkey ${OUTPUT_DIR}/root-key.pem \
    -in ${OUTPUT_DIR}/${1}/server.${1}.${2}-cert.csr \
    -extfile <(printf "subjectAltName=DNS:${1}.${2},DNS:${2},DNS:*.${2},DNS:localhost") \
    -out ${OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem ;
  cat ${OUTPUT_DIR}/${1}/server.${1}.${2}-cert.pem ${OUTPUT_DIR}/root-cert.pem >> ${OUTPUT_DIR}/${1}/server.${1}.${2}-cert-chain.pem ;
  cp ${OUTPUT_DIR}/root-cert.pem ${OUTPUT_DIR}/${1}/root-cert.pem ;
}

### Cert Generation Tests

# generate_root_cert ;
# generate_istio_cert mgmt-cluster ;
# generate_istio_cert active-cluster ;
# generate_istio_cert standby-cluster ;
# generate_client_cert vm-onboarding tetrate.prod ;
# generate_server_cert vm-onboarding tetrate.prod ;
