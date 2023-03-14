#!/usr/bin/env bash
#
# Helper script for vm onboarding and application bootstrapping
#
trap "" INT QUIT TSTP EXIT SIGHUP SIGKILL SIGTERM SIGINT

# Configure application
sudo tee /usr/lib/systemd/system/obstester.service <<EOF
[Unit]
Description=ObsTester App-B Service

[Service]
Environment=SVCNAME=app-b
ExecStart=/usr/local/bin/obs-tester-server \
    --log-output-level=all:debug \
    --http-listen-address=127.0.0.1:8000 \
    --tcp-listen-address=127.0.0.1:8888 \
    --health-address=127.0.0.1:7777 \
    --ep-duration=0 \
    --ep-errors=0 \
    --ep-headers=0 \
    --zipkin-reporter-endpoint=http://zipkin.istio-system:9411/api/v2/spans \
    --zipkin-sample-rate=1.0 \
    --zipkin-singlehost-spans
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 664 /usr/lib/systemd/system/obstester.service ;

# Update hosts file for dns resolving of istio enabled services
if ! cat /etc/hosts | grep "The following lines are insterted for istio" &>/dev/null ; then
sudo tee -a /etc/hosts << EOF

# The following lines are insterted for istio
127.0.0.2 zipkin.istio-system.svc.cluster.local
127.0.0.2 app-c.ns-c.svc.cluster.local
127.0.0.2 zipkin.istio-system
127.0.0.2 app-c.ns-c
EOF
fi

# Install onboarding agent, istio sidecar and sample jwt credentials plugin
# DOC: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm
# SRC: https://github.com/tetrateio/onboarding-agent-sample-jwt-credential-plugin
curl -k -fL -o /tmp/onboarding-agent.deb "https://vm-onboarding.demo.tetrate.io/install/deb/amd64/onboarding-agent.deb" --resolve "vm-onboarding.demo.tetrate.io:443:${TSB_VM_ONBOARDING_ENDPOINT}"
curl -k -fL -o /tmp/istio-sidecar.deb "https://vm-onboarding.demo.tetrate.io/install/deb/amd64/istio-sidecar.deb" --resolve "vm-onboarding.demo.tetrate.io:443:${TSB_VM_ONBOARDING_ENDPOINT}"
sudo apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/onboarding-agent.deb ;
sudo apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/istio-sidecar.deb ;
rm /tmp/onboarding-agent.deb ;
rm /tmp/istio-sidecar.deb ;
sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/envoy ;
curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
 | tar --directory /tmp -xz onboarding-agent-sample-jwt-credential-plugin ;
sudo mv /tmp/onboarding-agent-sample-jwt-credential-plugin /usr/local/bin/ ;
sudo chmod +x /usr/local/bin/onboarding-agent-sample-jwt-credential-plugin ;

# Add json web key
sudo mkdir -p /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin ;
sudo tee /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk << EOF
${JWK_VM1}
EOF
sudo chmod 400 /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk ;
sudo chown onboarding-agent: -R /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/ ;

# Add onboarding agent configuration
sudo mkdir -p /etc/onboarding-agent ;
sudo tee /etc/onboarding-agent/agent.config.yaml << EOF
---
apiVersion: config.agent.onboarding.tetrate.io/v1alpha1
kind: AgentConfiguration
host:
  custom:
    credential:
    - plugin:
        name: sample-jwt-credential
        path: /usr/local/bin/onboarding-agent-sample-jwt-credential-plugin
        env:
        - name: SAMPLE_JWT_ISSUER
          value: "https://issuer-vm1.demo.tetrate.io"
        - name: SAMPLE_JWT_ISSUER_KEY
          value: "/var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk"
        - name: SAMPLE_JWT_SUBJECT
          value: "vm1.demo.tetrate.io"
        - name: SAMPLE_JWT_ATTRIBUTES_FIELD
          value: "custom_attributes"
        - name: SAMPLE_JWT_ATTRIBUTES
          value: "instance_name=vm1,instance_role=app-b,region=region1"

EOF
sudo tee /etc/onboarding-agent/onboarding.config.yaml << EOF
---
apiVersion: config.agent.onboarding.tetrate.io/v1alpha1
kind: OnboardingConfiguration
onboardingEndpoint:
  host: ${TSB_VM_ONBOARDING_ENDPOINT}
  transportSecurity:
    tls:
      insecureSkipVerify: true
      sni: vm-onboarding.demo.tetrate.io
workloadGroup:
  namespace: ns-b
  name: app-b
workload:
  labels:
    app: app-b
    version: v1

EOF

# Start demo application and onboarding agent
sudo systemctl enable obstester ;
sudo systemctl start obstester ;

if sudo systemctl is-active onboarding-agent &>/dev/null ; then
  sudo systemctl restart onboarding-agent ;
else
  sudo systemctl enable onboarding-agent ;
  sudo systemctl start onboarding-agent ;
fi

echo "Onboarding finished"
