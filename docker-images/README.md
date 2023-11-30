# Docker images used by the repo

Next to the official TSB container images, we also use a bunch of images for demo purposes.
This readme file explains how to build and push them to the docker registry included in
this github project (`ghcr.io/tetratecx/tsb-single-vm`).

## Prerequisites

Make sure you have access to https://github.com/tetratecx/tsb-single-vm and have a proper
github token with the right permissions. You should be able to use a classic token with
`read:packages`, `delete:packages` and `write:packages` permissions.

```bash
docker login ghcr.io -u $GITHUB_USER -p $GITHUB_TOKEN
```

## Build and publish obs-tester-server image

Go to tetrateio's monorepo (`test/services/obs-tester`) and build/push the container.

```bash
docker buildx build --builder tetrate-builder --push \
--platform linux/amd64,linux/arm64 \
--build-arg OCI_SOURCE=tetrateio/tetrate \
--build-arg OCI_REVISION=$(git rev-parse HEAD | cut -c 1-10) \
--file Dockerfile.obs-tester-server \
--build-arg "TAG=1.0" \
--build-arg "PACKAGE_VENDOR=Tetrate.io Inc" \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server:1.0 \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server:latest . ;
```


## Pull, tag and publish netshoot container

Docker pull, tag and publish the latest netshoot container.

```bash
docker pull nicolaka/netshoot:v0.11 ;
docker tag nicolaka/netshoot:v0.11 ghcr.io/tetratecx/tsb-single-vm/netshoot:v0.11 ;
docker push ghcr.io/tetratecx/tsb-single-vm/netshoot:v0.11 ;

docker pull nicolaka/netshoot:latest ;
docker tag nicolaka/netshoot:latest ghcr.io/tetratecx/tsb-single-vm/netshoot:latest ;
docker push ghcr.io/tetratecx/tsb-single-vm/netshoot:latest ;
```

## Build and publish obs-tester-java image

Go to tetratecx's obs-tester-java repo and build/push the container.

```bash
docker buildx build --builder tetrate-builder --push \
--platform linux/amd64,linux/arm64 \
--build-arg OCI_SOURCE=tetratecx/obs-tester-java \
--build-arg OCI_REVISION=$(git rev-parse HEAD | cut -c 1-10) \
--file Dockerfile \
--build-arg "TAG=1.0" \
--build-arg "PACKAGE_VENDOR=Tetrate.io Inc" \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-java:1.0 \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-java:latest . ;
```

## Build and publish obs-tester-server-ubuntu-vm image

This containers provides the tools that would be available on a VM as well.
  - systemd is installed (init process PID=0)
  - ssh systemd service is enabled
  - root/root and ubuntu/ubuntu credentials to get ssh access
  - obs-tester-server in /usr/local/bin (part of $PATH)
  - pre-installed apt packages (apt-transport-https ca-certificates curl file git gnupg2 iproute2 iptables iputils-ping net-tools netcat nmap openssh-server sudo systemd systemd-sysv tree vim)

Go to tetrateio's monorepo (`test/services/obs-tester`) and build/push the container using the following [Dockerfile.obs-tester-server.ubuntu-vm](Dockerfile.obs-tester-server.ubuntu-vm) dockerfile.

```bash
export PLATFORMS=linux/amd64,linux/arm64 make release ;
docker buildx build --builder tetrate-builder --push \
--platform linux/amd64,linux/arm64 \
--build-arg OCI_SOURCE=tetrateio/tetrate \
--build-arg OCI_REVISION=$(git rev-parse HEAD | cut -c 1-10) \
--file Dockerfile.obs-tester-server.ubuntu-vm \
--build-arg "TAG=1.0" \
--build-arg "PACKAGE_VENDOR=Tetrate.io Inc" \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server-ubuntu-vm:1.0 \
-t ghcr.io/tetratecx/tsb-single-vm/obs-tester-server-ubuntu-vm:latest . ;
```

To run this vm simulating docker container.

```bash
docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -it --name=obs-tester-server-ubuntu-vm ghcr.io/tetratecx/tsb-single-vm/obs-tester-server-ubuntu-vm:latest ;
docker exec -it obs-tester-server-ubuntu-vm bash ;
```
