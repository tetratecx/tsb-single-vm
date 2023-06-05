# General release info
BUILD_DATE        := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
BUILD_VERSION     := 1.0.0
DOCKER_ACCOUNT    := boeboe
CONTAINER_NAME    := tsb-ubuntu-vm
IMAGE_DESCRIPTION := Docker container to mimic an ubuntu virtual machine
IMAGE_NAME        := tsb-ubuntu-vm
APP_VERSION       := 1.0.0
REPO_URL          := https://github.com/boeboe/tetrate-service-bridge-minikube
URL               := https://github.com/boeboe/tetrate-service-bridge-minikube

BUILD_ARGS := --build-arg BUILD_DATE="${BUILD_DATE}" \
							--build-arg BUILD_VERSION="${BUILD_VERSION}" \
							--build-arg DOCKER_ACCOUNT="${DOCKER_ACCOUNT}" \
							--build-arg IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION}" \
							--build-arg IMAGE_NAME="${IMAGE_NAME}" \
							--build-arg REPO_URL="${REPO_URL}" \
							--build-arg URL="${URL}" \
							--platform linux/amd64 

# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

build: ## Build the container
	docker build ${BUILD_ARGS} -t $(DOCKER_ACCOUNT)/${IMAGE_NAME} .

build-nc: ## Build the container without cache
	docker build ${BUILD_ARGS} --no-cache -t $(DOCKER_ACCOUNT)/${IMAGE_NAME} .

run: ## Run container
	docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -it --name=${IMAGE_NAME} $(DOCKER_ACCOUNT)/${IMAGE_NAME}

up: build run ## Build and run container on port configured

stop: ## Stop and remove a running container
	docker stop ${IMAGE_NAME} || true
	docker rm ${IMAGE_NAME} || true

release: build-nc publish ## Make a full release

publish: ## Tag and publish container
	@echo 'create tag $(BUILD_VERSION)'
	docker tag $(DOCKER_ACCOUNT)/$(IMAGE_NAME) $(DOCKER_ACCOUNT)/$(IMAGE_NAME):$(BUILD_VERSION)
	docker tag $(DOCKER_ACCOUNT)/$(IMAGE_NAME) $(DOCKER_ACCOUNT)/$(IMAGE_NAME):latest
	@echo 'publish $(BUILD_VERSION) to $(DOCKER_ACCOUNT)/$(IMAGE_NAME):$(BUILD_VERSION)'
	docker push $(DOCKER_ACCOUNT)/$(IMAGE_NAME):$(BUILD_VERSION)
	docker push $(DOCKER_ACCOUNT)/$(IMAGE_NAME):latest
