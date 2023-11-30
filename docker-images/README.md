# Docker images used by the repo

Next to the official TSB container images, we also use a bunch of images for demo purposes.
This readme file explains how to build and push them to the docker registry included in
this github project (ghcr.io/tetratecx/tsb-single-vm).

## Prerequisites

Make sure you have access to https://github.com/tetratecx/tsb-single-vm and have a proper
github token with the right permissions. You should be able to use a classic token with
`read:packages`, `delete:packages` and `write:packages` permissions.

```bash
docker login ghcr.io -u $GITHUB_USER -p $GITHUB_TOKEN
```

## Build and publsh obs-tester-server image

Go to tetrate's monorepo (`test/services/obs-tester`) and build/push the container.

```bash
docker buildx build --builder tetrate-builder --push \
--platform linux/amd64,linux/arm64 \
--build-arg OCI_SOURCE=tetrateio/tetrate \
--build-arg OCI_REVISION=$(git rev-parse HEAD | cut -c 1-10) \
--file Dockerfile.obs-tester-server \
--build-arg "TAG=1.0" \
--build-arg "PACKAGE_VENDOR=Tetrate.io Inc" \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server:1.0 \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server:latest .
```


## Pull, tag and publish netshoot container

Docker pull, tag and publish the latest netshoot container.

```bash
docker pull nicolaka/netshoot:v0.11
docker tag nicolaka/netshoot:v0.11 ghcr.io/tetratecx/tsb-single-vm/netshoot:v0.11
docker push ghcr.io/tetratecx/tsb-single-vm/netshoot:v0.11

docker pull nicolaka/netshoot:latest
docker tag nicolaka/netshoot:latest ghcr.io/tetratecx/tsb-single-vm/netshoot:latest
docker push ghcr.io/tetratecx/tsb-single-vm/netshoot:latest
```