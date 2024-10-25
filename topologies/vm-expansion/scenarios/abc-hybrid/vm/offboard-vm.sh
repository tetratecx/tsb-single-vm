#!/usr/bin/env bash
#
# Helper script for vm onboarding and application bootstrapping
#
trap "" INT QUIT TSTP EXIT SIGHUP SIGTERM SIGINT

# Stop and remove systemd services
sudo systemctl stop onboarding-agent
sudo systemctl disable onboarding-agent
sudo systemctl stop obstester
sudo systemctl disable obstester
sudo rm /usr/lib/systemd/system/onboarding-agent.service
sudo rm /usr/lib/systemd/system/obstester.service
sudo systemctl daemon-reload
sudo systemctl reset-failed

# Remove hosts file entries for istio enabled services
sudo tee /etc/hosts > /dev/null << EOF
$(grep -v '# The following lines are insterted for istio\|127.0.0.2\|^$' /etc/hosts)
EOF

# Remove onboarding agent, istio sidecar and sample jwt credentials plugin
sudo rm -rf /usr/local/bin/onboarding-agent-sample-jwt-credential-plugin
sudo rm -rf /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin
sudo rm -rf /etc/onboarding-agent
sudo dpkg --force-all --purge istio-sidecar
sudo dpkg --force-all --purge onboarding-agent
sudo rm -rf /var/lib/istio

echo "Offboarding finished"
