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


check-credentials:
ifeq ($(TSB_DOCKER_USERNAME),)
	$(error environment variable TSB_DOCKER_USERNAME is undefined)
endif
ifeq ($(TSB_DOCKER_PASSWORD),)
	$(error environment variable TSB_DOCKER_PASSWORD is undefined)
endif

prereqs: ## Make sure prerequisites are satisfied
	@/bin/sh -c './init.sh ${TSB_VERSION}'

minikube-up: check-credentials ## Bring up and configure minikube clusters
	@/bin/sh -c './minikube.sh up ${K8S_VERSION}'

minikube-down: ## Bring down and delete minikube clusters
	@/bin/sh -c './minikube.sh down'

install-mgmt-plane: ## Install TSB management plane
	@/bin/sh -c './tsb.sh install-mgmt-plane'

onboard-app-clusters: ## Onboard application clusters
	@/bin/sh -c './tsb.sh onboard-app-clusters'

config-tsb: ## Configure TSB
	@/bin/sh -c './tsb.sh config-tsb'

deploy-app-abc: ## Deploy abc application
	@/bin/sh -c './apps.sh deploy-app-abc'

deploy-app-def: ## Deploy def application
	@/bin/sh -c './apps.sh deploy-app-def'

test-app-abc: ## Generate curl commands to test ABC traffic
	@/bin/sh -c './apps.sh traffic-cmd-abc'

test-app-def: ## Generate curl commands to test DEF traffic
	@/bin/sh -c './apps.sh traffic-cmd-def'


clean: ## Clean resources
	@/bin/sh -c 'rm -f \
		./config/mgmt-cluster/clusteroperators.yaml \
		./config/mgmt-cluster/*.pem \
		./config/active-cluster/cluster-service-account.jwk \
		./config/active-cluster/controlplane-secrets.yaml \
		./config/active-cluster/controlplane.yaml \
		./config/standby-cluster/cluster-service-account.jwk \
		./config/standby-cluster/controlplane-secrets.yaml \
		./config/standby-cluster/controlplane.yaml \
	'
