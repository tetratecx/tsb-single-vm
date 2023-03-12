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

infra-up: prereq-check ## Bring up and configure minikube clusters and vms
	@/bin/bash -c './infra.sh up'

infra-down: ## Bring down minikube clusters and vms
	@/bin/bash -c './infra.sh down'

tsb-mp-install: ## Install TSB management cluster
	@/bin/bash -c './mp.sh install'

tsb-mp-uninstall: ## Uninstall TSB management cluster
	@/bin/bash -c './mp.sh uninstall'

tsb-cp-install: ## Install TSB control/data plane(s)
	@/bin/bash -c './cp.sh install'

tsb-cp-uninstall: ## Install TSB control/data plane(s)
	@/bin/bash -c './cp.sh uninstall'

info: ## Get infra environment info
	@/bin/bash -c './infra.sh info'

scenario-deploy: ## Deploy this scenario
	@/bin/bash -c './scenario.sh deploy'

scenario-undeploy: ## Undeploy this scenario
	@/bin/bash -c './scenario.sh undeploy'

scenario-info: ## Info about this scenario
	@/bin/bash -c './scenario.sh info'

clean: ## Clean up all resources
	@/bin/bash -c './infra.sh clean'
	@/bin/bash -c 'rm -f ./output/*'
