# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
.PHONY: init plan deploy destroy clean reset validate update

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

### Scenario configuration ###
TIER1_MODE := http
# TIER1_MODE := https
# TIER1_MODE := mtls
TIER2_MODE := http
# TIER2_MODE := https
APP_ABC_MODE := active
# APP_ABC_MODE := active-standby
# VM_APP_A := enabled
VM_APP_A := disabled
VM_APP_B := enabled
# VM_APP_B := disabled
# VM_APP_C := enabled
VM_APP_C := disabled
### Scenario configuration ###

prereq-check: ## Check if prerequisites are installed
	@/bin/sh -c './prereq.sh check'

prereq-install: ## Install prerequisites
	@/bin/sh -c './prereq.sh install'

###########################
infra-up: prereq-check ## Bring up and configure minikube clusters and vms
	@/bin/bash -c './infra.sh up'

###########################
infra-down: ## Bring down minikube clusters and vms
	@/bin/bash -c './infra.sh down'

###########################
tsb-mp-install: ## Install TSB management/control/data plane
	@/bin/bash -c './mp.sh install'

tsb-cp-install: ## Install TSB control/data plane(s)
	@/bin/bash -c './cp.sh install'

reset-tsb: ## Reset all TSB configuration
	@/bin/bash -c './tsb.sh reset-tsb'

deploy-app-abc-k8s: ## Deploy abc application on kubernetes
	@/bin/bash -c './apps-k8s.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

deploy-app-abc-vm: ## Deploy abc application on vms
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-c ; fi'

undeploy-app-abc-k8s: ## Undeploy abc application from kubernetes
	@/bin/bash -c './apps-k8s.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

undeploy-app-abc-vm: ## Undeploy abc application from vms
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-c ; fi'

test-app-abc: ## Generate curl commands to test ABC traffic
	@/bin/bash -c './apps-k8s.sh traffic-cmd-abc'



info: ## Get infra environment info
	@/bin/bash -c './infra.sh info'

clean: ## Clean up all resources
	@/bin/bash -c './infra.sh clean'
	@/bin/bash -c 'rm -f \
		./config/01-mgmt-cluster/clusteroperators.yaml \
		./config/01-mgmt-cluster/*.pem \
		./config/02-active-cluster/cluster-service-account.jwk \
		./config/02-active-cluster/controlplane-secrets.yaml \
		./config/02-active-cluster/controlplane.yaml \
		./config/03-standby-cluster/cluster-service-account.jwk \
		./config/03-standby-cluster/controlplane-secrets.yaml \
		./config/03-standby-cluster/controlplane.yaml \
	'
