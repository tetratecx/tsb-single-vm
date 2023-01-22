#!/usr/bin/env bash

if [[ $1 = "root-ca" ]]; then
  make -f Makefile.selfsigned.mk root-ca 
  exit 0
fi

if [[ $1 = "mgmt-cluster" ]]; then
  make -f Makefile.selfsigned.mk mgmt-cluster-cacerts
  exit 0
fi

if [[ $1 = "active-cluster" ]]; then
  make -f Makefile.selfsigned.mk active-cluster-cacerts
  exit 0
fi

if [[ $1 = "standby-cluster" ]]; then
  make -f Makefile.selfsigned.mk standby-cluster-cacerts
  exit 0
fi

if [[ $1 = "print-root-ca" ]]; then
  openssl x509 -in ./root-cert.pem -text
  exit 0
fi

if [[ $1 = "print-mgmt-cluster" ]]; then
  openssl x509 -in ./mgmt-cluster/ca-cert.pem -text
  exit 0
fi

if [[ $1 = "print-active-cluster" ]]; then
  openssl x509 -in ./active-cluster/ca-cert.pem -text
  exit 0
fi

if [[ $1 = "print-standby-cluster" ]]; then
  openssl x509 -in ./standby-cluster/ca-cert.pem -text
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - root-ca"
echo "  - mgmt-cluster"
echo "  - active-cluster"
echo "  - standby-cluster"
echo "  - print-root-ca"
echo "  - print-mgmt-cluster"
echo "  - print-active-cluster"
echo "  - print-standby-cluster"
exit 1