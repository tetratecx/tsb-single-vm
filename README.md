# Tetrate Service Bridge on Minikube

## Introduction

The purpose of this repo is to provide an isolated environmnent that allows to showcase TSB value add, without any external dependencies towards cloud provider services.

The target audience for this repo includes:
 - Prospects that want to quickly dive into TSB, without too much internal administrative overhead (tooling, cloud access rights, etc)
 - Tecnhical pre/post sales to quickly have a scenario up and running for demo and or testing purposes
 - Developers to quickly reproduce scenario's that go beyond just one cluster
 - Trainers and trainees, to have an isolated and easy to manage/clean-up environment.

The environment is based on [minikube](https://minikube.sigs.k8s.io/docs/start), with docker as the underlying virtualization [driver](https://minikube.sigs.k8s.io/docs/drivers/docker). Currently, only a Linux based system is supported, as TSB images are not multi-arch yet.

The repo provides support to spin up any arbitrary number of minikube based kubernetes clusters and VM's. VM's are implemented as docker containers with systemd support, so that VM onboarding with our onboarding agent and JWK based attestation can be demo'ed. TBS is automatically installed on those minikube clusters, as per declarative configuration (more on that later).

To redruce traffic from cloudsmith, a local docker repository is implemented, which decreases traffic costs and speeds up TSB deployments.

In order to provide an abstraction and maximum flexibility, a distintion is made between a `topology` and a `scenario`. Anyone is encouraged to add extra topologies and scenario's as he/she sees fit. A scenario is depending on a topology, so keep that in mind once you start changing topologies already used by certain scenario's.

## Configuration

In order to spin-up an environment, leveraging a certain topology and scenario, a top level JSON file `env.json` needs to be configured. An example (without actual TSB repo password) is provided [here](./env-template.json).

The JSON files contains configuration data on the topology and scenario to be used. The topology and scenario names match exactly the name of the folders within the [scenario](./scenario) and [topology](./topology) folders.


```console
# tree topologies/ -L 1
topologies
├── active-standby
├── demo-profile
├── hub-spoke
├── transit-zones
├── vm-expansion
└── vm-only

$ tree scenarios/ -L 2
scenarios
├── active-standby
│   └── abc-failover
├── hub-spoke
│   └── abc-def-ghi
├── transit-zones
│   └── abcd-efgh
├── vm-expansion
│   └── abc-hybrid
└── vm-only
    └── abc-vm
```

This a a short enumeration of the paramaters to be configured.

|parameter|type|description|
|---------|----|-----------|
|scenario|string|name of the scenario you want to use|
|topology|string|name of the topology you want to use|
|tsb|object|tsb configuration data|
|tsb.install_repo|object|configuration of the tsb repository to use (pulling images into k8s)|
|tsb.install_repo.insecure_registry|bool|insecure registry, or not (no user/password needed)|
|tsb.install_repo.password|string|password of the docker registry|
|tsb.install_repo.url|string|url of the docker registry (ip or dns based, with optional port)|
|tsb.install_repo.user|string|username of the docker registry|
|tsb.istio_version|string|version of istioctl to install on the host (make this TSB version compatible)|
|tsb.tetrate_repo|object|configuration of the tsb cloudsmith repository (to sync images in a local or private repo)|
|tsb.tetrate_repo.password|string|your tsb cloudsmith password|
|tsb.tetrate_repo.url|string|the tsb cloudsmith url|
|tsb.tetrate_repo.user|string|your tsb cloudsmith username|
|tsb.version|string|tsb version to install|

> **Alert:** Never commit your TSB cloudsmith credentials to github!

Note that you have the options to chose what docker repository you want to leverage:
1. use the cloudsmith repo directly within k8s to pull images from (to be avoid to save costs)
2. use your own private repository (u/p or insecure)
3. use a locally hosted docker repo (default: 192.168.48.2:5000)

For use cases (2) and (3) above, you can use a helper script to speed up the process of deploying a local docker repo and/or syncing official TSB docker images to those repos.

```console
# ./repo.sh 
Please specify correct action:
  - local-info : get local docker repo url (default: 192.168.48.2:5000)
  - local-remove : remove local docker repo
  - local-start : start local docker repo
  - local-stop : stop local docker repo
  - sync <repo-url> : sync tsb images from official repo to provided target repo
```

### Networking and minikube details

Every cluster (managementplane or controlplane) is deployed in a seperate [minikube profile](https://minikube.sigs.k8s.io/docs/commands/profile), which is hosted in a dedicated [docker network](https://docs.docker.com/engine/reference/commandline/network) with a seperate subnet. VMs that are configured at the managementplane or controlplane are docker containers run within that same network. The name of the docker network, matches the name of the cluster.

In order to provide cross docker network connectivity, docker iptables rules are flushed (docker networks are isolated with iptables by design, and we do not want that here).

The reason to use seperate minikube profiles and docker networks, is mere convenience in terms of metallb dhcp pools and ip address assigment and traceability in general.

### Local docker repository details

The local docker registry mirror, if you chose to use that, is also deployed in a seperate docker network, named `registry`.

```console
# docker network ls
NETWORK ID     NAME              DRIVER    SCOPE
72ccb42b9499   registry          bridge    local

# docker ps
CONTAINER ID   IMAGE        COMMAND                  CREATED      STATUS       PORTS                                       NAMES
177f8ae75e11   registry:2   "/entrypoint.sh /etc…"   7 days ago   Up 7 hours   0.0.0.0:5000->5000/tcp, :::5000->5000/tcp   registry
```

## Topologies

Topologies are the infra-structure part of the repo, and are expressed in JSON files. 

Topologies determine:
- the names of your clusters (mapping to minikube profiles, k8s cluster contexts and docker networks)
- how many kubernetes clusters you want
- how many tsb managementplane and controlplane clusters you want
- the networking aspects of those clusters (in terms of region/zone)
- the number of VMs you want, and where they are deployed

Currently a handfull of useful scenario's are available:

```console
# ls topologies -1

active-standby/
demo-profile/
hub-spoke/
transit-zones/
vm-expansion/
vm-only/
infra-template.json
```

Take a look at the example template provided [here](./scenarios/infra-template.json) to see how this works.

|parameter|type|description|
|---------|----|-----------|
|cp_clusters|list|a list TSB controlplane clusters|
|cp_clusters.[].name|string|the name of this controlplane cluster (used in minikube/k8s profile and TSB cluster name)|
|cp_clusters.[].region|string|the region to configure for this controlplane cluster|
|cp_clusters.[].zone|string|the zone to configure for this controlplane cluster|
|cp_clusters.[].vms|list|a list of VMs to spin-up in the same network as this controlplane cluster|
|cp_clusters.[].vms.[].image|string|the base image to use as VM|
|cp_clusters.[].vms.[].name|string|the name of this VM (used as hostname, docker container name and VM name)|
|k8s_version|string|version of kubernetes to be used by minikube|
|mp_cluster|object|tsb managementplane cluster configuration|
|mp_cluster.demo_profile|bool|use TSB demo installation profile (with cert-manager, postgres, elastic, redis and ldap)|
|mp_cluster.name|string|the name of this managementplane cluster (used in minikube/k8s profile and TSB cluster name)|
|mp_cluster.region|string|the region to configure for the managementplane cluster|
|mp_cluster.zone|string|the zone to configure for the managementplane cluster|
|mp_cluster.vms|list||a list of VMs to spin-up in the same network as the managementplane cluster|
|mp_cluster.vms.[].image|string|the base image to use as VM|
|mp_cluster.vms.[].name|string|the name of this VM (used as hostname, docker container name and VM name)|


## Scenario's

Scenario's are leveraging one available scenario. They will deploy TSB configuration (dependent on the topology!), kubernetes configuration, VM configuration/onboarding and anything else you might need or want.

The "interface" to the rest of the system is a `run.sh` file which is invoked by the toplevel `makefile` system. It should contain a running hook (shell parameter) for `deploy` (deploymeny of your scenario), `undeploy` (clean-up scenario, bringing the system back to topology only) and `info` (information about the scenario in terms of ip address and useful commands to execute).

Current scenario's implemented on the avaible topologies all leverage our built-in `obs-tester-server`. One can implement any application as one see fits useful.

Scenario's should not limit themselves to demo applications only. One can also implement a scenario to demonstrate gitops, cicd, telemetry, rbac or other integrations. As long as the components are docker/k8s friendly and there is no hard-coded external dependency, anything is possible.

## Usage

After you have configured the necessary details in `env.json` as described above in [configuration](#configuration), you can spin-up the desired environment using `make`, which is self-documented.

```console
make
help                           This help
up                             Bring up full demo scenario
prereq-check                   Check if prerequisites are installed
prereq-install                 Install prerequisites
infra-up                       Bring up and configure minikube clusters and vms
infra-down                     Bring down minikube clusters and vms
tsb-mp-install                 Install TSB management cluster
tsb-mp-uninstall               Uninstall TSB management cluster
tsb-cp-install                 Install TSB control/data plane(s)
tsb-cp-uninstall               Install TSB control/data plane(s)
info                           Get infra environment info
scenario-deploy                Deploy this scenario
scenario-undeploy              Undeploy this scenario
scenario-info                  Info about this scenario
clean                          Clean up all resources
```

All temporary files (configuration, certificates, etc) are stored in [output](./output) folder, which is cleaned up with a `make clean` command as well.

The `info` and `scenario-info` target give more information about the topology and scenario's being used (ip addresses, ssh commands, kubectl commands, useful curl commands, etc).

> **Note:** all `makefile` targets are implemented to be idempotent, which means that you can run them once, or more, but the result should always be working. This means there is quite some code in the shell scripts that verifies if certain one-off actions are already done, and skips them if needed. Please take this into consideration when you add new scenario's.

## Repo structure and files

This section is a brief description of the repo structure itself. What folder and files are used, and what are they doing.

| file/folder | description |
|-------------|-------------|
|addons/|useful addons (wip). Eg: kibana for elastic index display, openldap-ui for ldap configuration, pgadmin for postgres exploration, etc|
|docker-vm/|the dockerfile for the VM, which is basically a docker image with systemd and some more|
|output/|structured output with temporary files like certificates, configuration, jwk's, etc|
|scenarios/|the scenario's available, sorted per topology|
|topologies/|the topologies available|
|certs.sh|script with functions to generate certificates with openssl (root, istio, server or client)|
|cp.sh|script to install tsb controlplane, based on the topology configured|
|env-template.json|env.json template to be copied and adjusted to your needs (never commit this one!)|
|helpers.sh|helper functions to add color in a madness of shell output|
|infra.sh|script to install the desired topology, using minikube and docker|
|Makefile|the top level makefile and main entrypoint to be used by end-users|
|mp.sh|script to install tsb management plane, based on the topology configured|
|README.md|this file for documentation|
|prereq.sh|script to check some necessary prerequisites and avoid pain later down|
|repo.sh|helper scripts for local repo spinup and/or local/private repo syncing from TSB cloudsmith repo|
|scenario.sh|script responsible for interacting with the `run.sh` file of your scenario|


## TODOs

A non-exhaustive list of to be implemented items include:
 - none-demo TSB MP installation (ldap and oidc)
 - rpm based vm onboarding support
 - tsb training labs (https://github.com/tetrateio/tsb-labs) as a set of scenario's on a dedicated training topology
 - porting eshop-demo repo (https://github.com/tetrateio/eshop-demo/tree/main/docs) to here as well
 - more scenario's with real applications
 - potentially add LXD support next to minikube/docker support
 - add TF and/or cloudshell (glcoud/aws-cli/az-cli) to quickly bootstrap a fully prepped and ready VM on AWS/GCP/Azure
 - add support for local MacOS (intel and arm chipset)
 - integrations, integrations, integrations:
    - gitops: fluxcd and argocd
    - cicd: jenkins
    - authn/z: keycloack, ory
    - telemetry: prometheus, etc
    - ... 

## Disclaimer

This repo is purely used for demo/training/local usage purposes and not meant for production environments at all.

