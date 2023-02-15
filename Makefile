# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
.PHONY: init plan deploy destroy clean reset validate update

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help


TSB_VERSION := 1.6.0
K8S_VERSION := 1.24.9
ISTIO_VERSION := 1.15.2

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


check-credentials:
ifeq ($(TSB_DOCKER_USERNAME),)
	$(error environment variable TSB_DOCKER_USERNAME is undefined)
endif
ifeq ($(TSB_DOCKER_PASSWORD),)
	$(error environment variable TSB_DOCKER_PASSWORD is undefined)
endif

prereqs-check: ## Check if prerequisites are installed
	@/bin/sh -c './prereqs.sh check ${K8S_VERSION} ${TSB_VERSION} ${ISTIO_VERSION}'

prereqs-install: ## Install prerequisites
	@/bin/sh -c './prereqs.sh install ${K8S_VERSION} ${TSB_VERSION} ${ISTIO_VERSION}'

###########################
infra-mgmt-up: prereqs-check check-credentials ## Bring up and configure mgmt minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-up mgmt-cluster ${K8S_VERSION}'

infra-active-up: prereqs-check check-credentials ## Bring up and configure active minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-up active-cluster ${K8S_VERSION}'

infra-standby-up: prereqs-check check-credentials ## Bring up and configure standby minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-up standby-cluster ${K8S_VERSION}'

infra-vm-up: prereqs-check check-credentials ## Bring up and configure vms
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-c ; fi'

###########################
infra-mgmt-down: check-credentials ## Bring down and delete mgmt minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-down mgmt-cluster'

infra-active-down: check-credentials ## Bring down and delete active minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-down active-cluster'

infra-standby-down: check-credentials ## Bring down and delete standby minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-down standby-cluster'

infra-vm-down: check-credentials ## Bring down and delete vms
	@/bin/bash -c './infra-vm.sh vm-down'


###########################
tsb-mgmt-install: ## Install TSB management/control/data plane in mgmt cluster (demo profile)
	@/bin/bash -c './tsb.sh mgmt-cluster-install'

tsb-active-install: ## Install TSB control/data plane in active cluster
	@/bin/bash -c './tsb.sh app-cluster-install active-cluster'

tsb-standby-install: ## Install TSB control/data plane in stanby cluster
	@/bin/bash -c './tsb.sh app-cluster-install standby-cluster'

reset-tsb: ## Reset all TSB configuration
	@/bin/bash -c './tsb.sh reset-tsb'

deploy-app-abc-k8s: check-credentials ## Deploy abc application on kubernetes
	@/bin/bash -c './apps-k8s.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

deploy-app-abc-vm: check-credentials ## Deploy abc application on vms
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
	@/bin/bash -c './infra-k8s.sh info'
	@/bin/bash -c './infra-vm.sh info'

clean: ## Clean up all resources
	@/bin/bash -c './infra-k8s.sh clean'
	@/bin/bash -c './infra-vm.sh clean'
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
