
FROM ubuntu:jammy AS builder
WORKDIR /tmp
COPY /id_rsa /
RUN apt-get update -y && apt-get install -y git make golang docker.io curl jq && chmod 400 /id_rsa
RUN mkdir -p /root/.docker/cli-plugins && \
    curl https://github.com/docker/buildx/releases/download/v0.10.3/buildx-v0.10.3.linux-amd64 -o /root/.docker/cli-plugins/docker-buildx && \
    chmod +x /root/.docker/cli-plugins/docker-buildx && ls /root/.docker/cli-plugins/docker-buildx
RUN git clone -c "core.sshCommand=ssh -i /id_rsa -o StrictHostKeyChecking=no -F /dev/null" git@github.com:tetrateio/tetrate.git && \
    cd /tmp/tetrate/test/services/obs-tester && \
    make && cp /tmp/tetrate/test/services/obs-tester/build/bin/linux/*/obs-tester-server /obs-tester-server

FROM ubuntu:jammy
LABEL org.opencontainers.image.authors="bart@tetrate.io"
ENV TZ=Europe/Brussels
ENV LC_ALL C
ENV DEBIAN_FRONTEND noninteractive
COPY --from=builder /obs-tester-server /usr/local/bin/obs-tester-server
RUN apt-get update -y && apt-get install --no-install-recommends -y \
    apt-transport-https \
    ca-certificates \
    curl \
    git \
    gnupg2 \
    iproute2 \
    iputils-ping \
    net-tools \
    sudo \
    systemd \
    systemd-sysv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    /lib/systemd/system/systemd-update-utmp*
VOLUME [ "/sys/fs/cgroup" ]
WORKDIR /
ADD /entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# ENTRYPOINT ["/sbin/init"]
ENTRYPOINT ["/bin/sh", "-c", "/usr/local/bin/entrypoint.sh"]
