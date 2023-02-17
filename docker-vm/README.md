# init.d docker container

## Introduction

This containers provides the tools that would be available on a VM as well.
  - systemd is installed (init process PID=0)
  - ssh systemd service is enabled
  - root/root and ubuntu/ubuntu credentials get access
  - obs-tester-server in /usr/local/bin (part of $PATH)
  - installed apt packages: curl git iproute2 iputils-ping net-tools openssh-server sudo

## Run

To run this container.

```console
$ make run
```

## Build

In order to build this container, you need ssh gitrepo access to https://github.com/tetrateio. Add your `id_rsa` private key in this folder to build `obs-tester-server`. Do not commit this key (part of `.gitignore`).

To build this container.

```console
$ make build
```

In order to release and push the containers, modify the Makefile to match your needs (docker user, release version, etc).

```console
$ make release
```
