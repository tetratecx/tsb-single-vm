
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
ARG BUILD_DATE
ARG BUILD_VERSION
ARG DOCKER_ACCOUNT
ARG IMAGE_DESCRIPTION
ARG IMAGE_NAME
ARG REPO_URL
ARG URL
LABEL org.opencontainers.image.authors="bart@tetrate.io"
LABEL org.label-schema.build-date=$BUILD_DATE
LABEL org.label-schema.description=$IMAGE_DESCRIPTION
LABEL org.label-schema.name=$DOCKER_ACCOUNT/$IMAGE_NAME
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.url=$URL
LABEL org.label-schema.vcs-url=$REPO_URL
LABEL org.label-schema.vendor="Tetrate"
LABEL org.label-schema.version=$BUILD_VERSION
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
    iptables \
    iputils-ping \
    net-tools \
    openssh-server \
    sudo \
    systemd \
    systemd-sysv \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    /lib/systemd/system/systemd-update-utmp*
RUN systemctl enable ssh 
RUN /bin/bash -c 'echo -e "root\nroot" | passwd root'
RUN /bin/bash -c 'echo -e "\n\nPermitRootLogin yes" | tee -a /etc/ssh/sshd_config'
RUN /bin/bash -c 'useradd --create-home -p $(openssl passwd -1 ubuntu) ubuntu'
RUN /bin/bash -c 'usermod -aG sudo ubuntu'
RUN /bin/bash -c 'echo -e "\n\nubuntu ALL=(ALL:ALL) NOPASSWD:ALL" | tee -a /etc/sudoers'
RUN /bin/bash -c 'usermod --shell /bin/bash root'
RUN /bin/bash -c 'usermod --shell /bin/bash ubuntu'
VOLUME [ "/sys/fs/cgroup" ]
WORKDIR /
ENTRYPOINT ["/sbin/init"]
