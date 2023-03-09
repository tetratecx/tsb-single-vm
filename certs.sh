#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"
source ${ROOT_DIR}/env.sh

CERTS_BASE_DIR=$(get_certs_base_dir) ;

# Generate a self signed root certificate
function generate_root_cert {
  mkdir -p ${CERTS_BASE_DIR} ;
  if [[ -f "${CERTS_BASE_DIR}/root-cert.pem" ]]; then 
    echo "File ${CERTS_BASE_DIR}/root-cert.pem already exists... skipping certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERTS_BASE_DIR}/root-key.pem \
    -subj "/CN=Root CA/O=Istio" \
    -out ${CERTS_BASE_DIR}/root-cert.csr ;
  openssl x509 -req -sha512 -days 3650 \
    -signkey ${CERTS_BASE_DIR}/root-key.pem \
    -in ${CERTS_BASE_DIR}/root-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign") \
    -out ${CERTS_BASE_DIR}/root-cert.pem ;
  echo "New root certificate generated at ${CERTS_BASE_DIR}/root-cert.pem"
}

# Generate an intermediate istio certificate signed by the self signed root certificate
#   args:
#     (1) cluster name
function generate_istio_cert {
  CLUSTER_NAME=${1}
  CERT_ISTIO_DIR=${CERTS_BASE_DIR}/${CLUSTER_NAME}
  mkdir -p ${CERT_ISTIO_DIR} ;
  if [[ ! -f "${CERTS_BASE_DIR}/root-cert.pem" ]]; then generate_root_cert ; fi
  if [[ -f "${CERT_ISTIO_DIR}/ca-cert.pem" ]]; then 
    echo "File ${CERT_ISTIO_DIR}/ca-cert.pem already exists... skipping certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${CERT_ISTIO_DIR}/ca-key.pem \
    -subj "/CN=Intermediate CA/O=Istio/L=${CLUSTER_NAME}" \
    -out ${CERT_ISTIO_DIR}/ca-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${CERTS_BASE_DIR}/root-cert.pem \
    -CAkey ${CERTS_BASE_DIR}/root-key.pem \
    -in ${CERT_ISTIO_DIR}/ca-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign\nsubjectAltName=DNS.1:istiod.istio-system.svc") \
    -out ${CERT_ISTIO_DIR}/ca-cert.pem ;
  cat ${CERT_ISTIO_DIR}/ca-cert.pem ${CERTS_BASE_DIR}/root-cert.pem >> ${CERT_ISTIO_DIR}/cert-chain.pem ;
  cp ${CERTS_BASE_DIR}/root-cert.pem ${CERT_ISTIO_DIR}/root-cert.pem ;
  echo "New intermediate istio certificate generated at ${CERT_ISTIO_DIR}/ca-cert.pem"
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) client workload name
#     (2) domain name
function generate_client_cert {
  CLIENT_NAME=${1}
  DOMAIN=${2}
  OUT_DIR=${CERTS_BASE_DIR}/${CLIENT_NAME}
  mkdir -p ${OUT_DIR} ;
  if [[ ! -f "${CERTS_BASE_DIR}/root-cert.pem" ]]; then generate_root_cert ; fi
  if [[ -f "${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.pem" ]]; then 
    echo "File ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.pem already exists... skipping certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-key.pem \
    -subj "/CN=${CLIENT_NAME}.${DOMAIN}/O=Customer/C=US/ST=CA" \
    -out ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 1 \
    -CA ${CERTS_BASE_DIR}/root-cert.pem \
    -CAkey ${CERTS_BASE_DIR}/root-key.pem \
    -in ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.csr \
    -out ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.pem ;
  cat ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert.pem ${CERTS_BASE_DIR}/root-cert.pem >> ${OUT_DIR}/client.${CLIENT_NAME}.${DOMAIN}-cert-chain.pem ;
  cp ${CERTS_BASE_DIR}/root-cert.pem ${OUT_DIR}/root-cert.pem ;
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) server workload name
#     (2) domain name
function generate_server_cert {
  SERVER_NAME=${1}
  DOMAIN=${2}
  OUT_DIR=${CERTS_BASE_DIR}/${SERVER_NAME}
  mkdir -p ${OUT_DIR} ;
  if [[ ! -f "${CERTS_BASE_DIR}/root-cert.pem" ]]; then generate_root_cert ; fi
  if [[ -f "${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.pem" ]]; then 
    echo "File ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.pem already exists... skipping certificate generation"
    return
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-key.pem \
    -subj "/CN=${SERVER_NAME}.${DOMAIN}/O=Tetrate/C=US/ST=CA" \
    -out ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 0 \
    -CA ${CERTS_BASE_DIR}/root-cert.pem \
    -CAkey ${CERTS_BASE_DIR}/root-key.pem \
    -in ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.csr \
    -extfile <(printf "subjectAltName=DNS:${SERVER_NAME}.${DOMAIN},DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost") \
    -out ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.pem ;
  cat ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert.pem ${CERTS_BASE_DIR}/root-cert.pem >> ${OUT_DIR}/server.${SERVER_NAME}.${DOMAIN}-cert-chain.pem ;
  cp ${CERTS_BASE_DIR}/root-cert.pem ${OUT_DIR}/root-cert.pem ;
}

### Cert Generation Tests
# 
# generate_root_cert;
# generate_istio_cert active-cluster ;
# generate_client_cert vm-onboarding tetrate.prod ;
# generate_server_cert vm-onboarding tetrate.prod ;
