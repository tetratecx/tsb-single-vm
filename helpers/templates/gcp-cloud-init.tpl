#cloud-config
hostname: tsb-single-vm

packages:
  - curl
  - docker.io
  - expect
  - git
  - httpie
  - jq
  - net-tools
  - make
  - nmap
  - traceroute
  - tree

runcmd:
  - usermod -aG docker ubuntu
