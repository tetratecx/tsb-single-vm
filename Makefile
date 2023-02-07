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
# K8S_VERSION := 1.23.15

TIER1_MODE := http
# TIER1_MODE := https
# TIER1_MODE := mtls

TIER2_MODE := http
# TIER2_MODE := https

APP_ABC_MODE := active
# APP_ABC_MODE := active-standby

VM_APP_A := enabled
VM_APP_B := enabled
VM_APP_C := enabled


check-credentials:
ifeq ($(TSB_DOCKER_USERNAME),)
	$(error environment variable TSB_DOCKER_USERNAME is undefined)
endif
ifeq ($(TSB_DOCKER_PASSWORD),)
	$(error environment variable TSB_DOCKER_PASSWORD is undefined)
endif

prereqs: ## Make sure prerequisites are satisfied
	@/bin/bash -c './init.sh ${TSB_VERSION}'

###########################
infra-mgmt-up: check-credentials ## Bring up and configure mgmt minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-up mgmt-cluster ${K8S_VERSION}'

infra-active-up: check-credentials ## Bring up and configure active minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-up active-cluster ${K8S_VERSION}'

infra-standby-up: check-credentials ## Bring up and configure standby cluster
	@/bin/bash -c './infra-k8s.sh cluster-up standby-cluster ${K8S_VERSION}'

infra-vm-up: check-credentials ## Bring up and configure vm
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./infra-vm.sh vm-up ubuntu-vm-c ; fi'

###########################
infra-mgmt-down: check-credentials ## Bring down and delete mgmt clusters
	@/bin/bash -c './infra-k8s.sh cluster-down mgmt-cluster'

infra-active-down: check-credentials ## Bring down and delete active minikube cluster
	@/bin/bash -c './infra-k8s.sh cluster-down active-cluster'

infra-standby-down: check-credentials ## Bring down and delete standby cluster
	@/bin/bash -c './infra-k8s.sh cluster-down standby-cluster'

infra-vm-down: check-credentials ## Bring down and delete vm
	@/bin/bash -c './infra-vm.sh vm-down'


###########################
tsb-mgmt-install: ## Install TSB management, control and data plane in mgmt cluster (demo profile)
	@/bin/bash -c './tsb.sh mgmt-cluster-install'

tsb-active-install: ## Install TSB control and data plane in active cluster
	@/bin/bash -c './tsb.sh app-cluster-install active-cluster'

tsb-standby-install: ## Install TSB control and data plane in stanby cluster
	@/bin/bash -c './tsb.sh app-cluster-install standby-cluster'



config-tsb: ## Configure TSB
	@/bin/bash -c './tsb.sh config-tsb'

reset-tsb: ## Reset all TSB configuration
	@/bin/bash -c './tsb.sh reset-tsb'

deploy-app-abc-k8s: check-credentials ## Deploy abc application
	@/bin/bash -c './apps-k8s.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

deploy-app-abc-vm: check-credentials ## Deploy abc application
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./apps-vm.sh deploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-c ; fi'

undeploy-app-abc-k8s: ## Undeploy abc application as pod
	@/bin/bash -c './apps-k8s.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

undeploy-app-abc-vm: ## Undeploy abc application as vm
	@/bin/bash -c 'if [[ ${VM_APP_A} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-a ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_B} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-b ; fi'
	@/bin/bash -c 'if [[ ${VM_APP_C} = "enabled" ]] ; then ./apps-vm.sh undeploy-app ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE} ubuntu-vm-c ; fi'

test-app-abc: ## Generate curl commands to test ABC traffic
	@/bin/bash -c './apps.sh traffic-cmd-abc'



info: ## Get infra environment info
	@/bin/bash -c './infra-k8s.sh info'
	@/bin/bash -c './infra-vm.sh info'

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
