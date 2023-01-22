#!/usr/bin/env bash

TSB_VERSION=${1}
DEPENDENCIES=( tctl minikube expect docker kubectl )

# check necessary dependencies are installed
for dep in "${DEPENDENCIES[@]}"
do
  if ! command -v ${dep} &> /dev/null
  then
    echo "${dep} could not be found, please install this on your local system first" ;
    exit 1
  fi
done

# check if the expected tctl version is installed
if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]]
then
  echo "wrong version of tctl, please install version ${TSB_VERSION} first" ;
  exit 2
fi
