# init.d docker container

## Introduction

This containers provides the tools that would be available on a VM as well.
  - systemd is installed (init process PID=0)
  - ssh systemd service is enabled
  - root/root and ubuntu/ubuntu credentials get access
  - obs-tester-server in /usr/local/bin (part of $PATH)

## Run

To run this container.

```console
docker run --privileged --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup --cgroupns=host -it <image-name:image-tag>
```
