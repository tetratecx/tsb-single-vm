# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
.PHONY: init plan deploy destroy clean reset validate update

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

deploy: ## Deploy this scenario
	@/bin/bash -c './make.sh deploy'

undeploy: ## Undeploy this scenario
	@/bin/bash -c './make.sh undeploy'

info: ## Info about this scenario
	@/bin/bash -c './make.sh info'
