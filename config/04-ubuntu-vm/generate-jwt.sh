#!/usr/bin/env bash

# In case you want to change some attributes of the JWT token, please check the docs and adjust the proper files accordingly
#   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding#allow-workloads-to-authenticate-themselves-by-means-of-a-jwt-token
#   REF: https://github.com/tetrateio/onboarding-agent-sample-jwt-credential-plugin

if ! [[ -f "onboarding-agent-sample-jwt-credential-plugin" ]]; then
  curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
    | tar -xz onboarding-agent-sample-jwt-credential-plugin
fi

export SAMPLE_JWT_ISSUER="https://sample-jwt-issuer.example"
export SAMPLE_JWT_SUBJECT="ubuntu-vm.tetrate.prod"
export SAMPLE_JWT_ATTRIBUTES_FIELD="custom_attributes"
export SAMPLE_JWT_ATTRIBUTES="instance_name=ubuntu-vm,instance_role=app-b,region=region1"
export SAMPLE_JWT_EXPIRATION="87600h"

./onboarding-agent-sample-jwt-credential-plugin generate key -o ./sample-jwt-issuer
