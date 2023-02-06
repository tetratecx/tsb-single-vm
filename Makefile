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

# APP_ABC_MODE := active
# APP_ABC_MODE := active-standby
APP_ABC_MODE := active-vm
# APP_ABC_MODE := active-standby-vm


check-credentials:
ifeq ($(TSB_DOCKER_USERNAME),)
	$(error environment variable TSB_DOCKER_USERNAME is undefined)
endif
ifeq ($(TSB_DOCKER_PASSWORD),)
	$(error environment variable TSB_DOCKER_PASSWORD is undefined)
endif

prereqs: ## Make sure prerequisites are satisfied
	@/bin/sh -c './init.sh ${TSB_VERSION}'

###########################
infra-mgmt-up: check-credentials ## Bring up and configure mgmt minikube cluster
	@/bin/sh -c './infra.sh cluster-up mgmt-cluster ${K8S_VERSION}'

infra-active-up: check-credentials ## Bring up and configure active minikube cluster
	@/bin/sh -c './infra.sh cluster-up active-cluster ${K8S_VERSION}'

infra-standby-up: check-credentials ## Bring up and configure standby cluster
	@/bin/sh -c './infra.sh cluster-up standby-cluster ${K8S_VERSION}'

infra-vm-up: check-credentials ## Bring up and configure vm
	@/bin/sh -c './infra.sh vm-up'

###########################
infra-mgmt-down: check-credentials ## Bring down and delete mgmt clusters
	@/bin/sh -c './infra.sh cluster-down mgmt-cluster'

infra-active-down: check-credentials ## Bring down and delete active minikube cluster
	@/bin/sh -c './infra.sh cluster-down active-cluster'

infra-standby-down: check-credentials ## Bring down and delete standby cluster
	@/bin/sh -c './infra.sh cluster-down standby-cluster'

infra-vm-down: check-credentials ## Bring down and delete vm
	@/bin/sh -c './infra.sh vm-down'


###########################
tsb-mgmt-install: ## Install TSB management, control and data plane in mgmt cluster (demo profile)
	@/bin/sh -c './tsb.sh mgmt-cluster-install'

tsb-active-install: ## Install TSB control and data plane in active cluster
	@/bin/sh -c './tsb.sh app-cluster-install active-cluster'

tsb-standby-install: ## Install TSB control and data plane in stanby cluster
	@/bin/sh -c './tsb.sh app-cluster-install standby-cluster'



config-tsb: ## Configure TSB
	@/bin/sh -c './tsb.sh config-tsb'

reset-tsb: ## Reset all TSB configuration
	@/bin/sh -c './tsb.sh reset-tsb'

deploy-app-abc: check-credentials ## Deploy abc application
	@/bin/sh -c './apps.sh deploy-app-abc ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

undeploy-app-abc: ## Undeploy abc application
	@/bin/sh -c './apps.sh undeploy-app-abc ${TIER1_MODE} ${TIER2_MODE} ${APP_ABC_MODE}'

test-app-abc: ## Generate curl commands to test ABC traffic
	@/bin/sh -c './apps.sh traffic-cmd-abc'



info: ## Get infra environment info
	@/bin/sh -c './infra.sh info'

clean: ## Clean up all resources
	@/bin/sh -c './infra.sh clean'
	@/bin/sh -c 'rm -f \
		./config/01-mgmt-cluster/clusteroperators.yaml \
		./config/01-mgmt-cluster/*.pem \
		./config/02-active-cluster/cluster-service-account.jwk \
		./config/02-active-cluster/controlplane-secrets.yaml \
		./config/02-active-cluster/controlplane.yaml \
		./config/03-standby-cluster/cluster-service-account.jwk \
		./config/03-standby-cluster/controlplane-secrets.yaml \
		./config/03-standby-cluster/controlplane.yaml \
	'
