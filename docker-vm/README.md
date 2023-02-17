# init.d docker container

## Introduction

This containers provides the tools that would be available on a VM as well.
  - systemd is installed (init process PID=0)
  - ssh systemd service is enabled
  - root/root and ubuntu/ubuntu credentials to get ssh access
  - obs-tester-server in /usr/local/bin (part of $PATH)
  - installed apt packages: curl git iproute2 iputils-ping net-tools openssh-server sudo

## Run container

To run this container locally after building.

```console
$ make run
```

To run straight from dockerhub

```console
$ docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -it --name=tsb-ubuntu-vm boeboe/tsb-ubuntu-vm
```

## Build container

In order to build this container, you need ssh gitrepo access to https://github.com/tetrateio. Add your `id_rsa` private key in this folder to build `obs-tester-server`. Do not commit this key (part of `.gitignore`).

To build this container.

```console
$ make build
```

In order to release and push the containers, modify the Makefile to match your needs (docker user, release version, etc).

```console
$ make release
```
