# Tetrate Service Bridge on Local Kubernetes (K3s/Kind/Minikube) within a Single VM

## Introduction

The purpose of this repo is to provide an isolated environment that allows to showcase TSB value add, without any external dependencies towards cloud provider services. 

The target audience for this repo includes:
 - Prospects that want to quickly dive into TSB, without too much internal administrative overhead (tooling, cloud access rights, etc)
 - Tecnhical pre/post sales to quickly have a scenario up and running for demo and or testing purposes
 - Developers to quickly reproduce scenarios that go beyond just one cluster
 - Trainers and trainees, to have an isolated and easy to manage/clean-up environment.

The environment is based on locally hosted kubernetes clusters, with docker as the underlying virtualization. Currently, only a Linux x86 based systems are supported, as TSB images are not multi-arch yet (no support for MacOS on an M1 for example). The following local kubernetes providers are supported:
 - [k3s](https://k3s.io) managed through [k3d](https://k3d.io)
 - [kind](https://kind.sigs.k8s.io/docs/user/quick-start)
 - [minikube](https://minikube.sigs.k8s.io/docs/start) using the [docker driver](https://minikube.sigs.k8s.io/docs/drivers/docker)

The repo provides support to spin up any arbitrary number of local kubernetes clusters and VM's. VM's are implemented as docker containers with systemd support, so that VM onboarding with our onboarding agent and JWK based attestation can be demo'ed. TSB is automatically installed on those local kubernetes clusters, as per declarative configuration (more on that later).

To reduce traffic from cloudsmith, a local docker repository is implemented, which decreases traffic costs and speeds up TSB deployments.

In order to provide an abstraction and maximum flexibility, a distinction is made between a `topology` and a `scenario`. Anyone is encouraged to add extra topologies and scenarios as he/she sees fit. A scenario is depending on a topology, so keep that in mind once you start changing topologies already used by certain scenarios.

In terms of memory constraints of the VM: a 64GB Ubuntu machine can support up to 5 TSB clusters to showcase a transit zone scenario. It takes around 15 minutes to spin those 5 TSB clusters up completely from scratch (infra / tsb config / application deployment). Spinning down is just a destroy/stopping of the VM or a `make clean`, which takes 30 seconds.

## Configuration

In order to spin-up an environment, leveraging a certain topology and scenario, a top level JSON file `env.json` needs to be configured. An example (without actual TSB repo password) is provided [here](./env-template.json).

The JSON file contains configuration data on the topology and scenario to be used. The topology and scenario names match exactly the name of the folders structure under **topologies/<topolgy-name>/scenarios/<scenario-name>**.


```console
# tree -d -L 3 topologies/
topologies
├── active-standby
│   ├── scenarios
│   │   └── abc-failover
│   └── templates
│       ├── active
│       ├── mgmt
│       └── standby
├── demo-profile
│   ├── scenarios
│   │   ├── gitops-argocd
│   │   └── gitops-fluxcd
│   └── templates
│       └── demo
├── hub-spoke
│   ├── scenarios
│   │   └── abc-def-ghi
│   └── templates
│       ├── cluster1
│       ├── cluster2
│       ├── cluster3
│       └── mgmt
├── transit-zones
│   ├── scenarios
│   │   └── abcd-efgh
│   └── templates
│       ├── app1
│       ├── app2
│       ├── mgmt
│       ├── transit1
│       └── transit2
├── tsb-training
│   ├── scenarios
│   │   └── main
│   └── templates
│       ├── c1
│       ├── c2
│       └── t1
├── vm-expansion
│   ├── scenarios
│   │   └── abc-hybrid
│   └── templates
│       └── mgmt
└── vm-only
    ├── scenarios
    │   └── abc-vm
    └── templates
        └── mgmt
```

A short enumeration of the paramaters to be configured:

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

Note that you have the option to choose what docker repository you want to leverage:
1. use the cloudsmith repo directly within k8s to pull images from (to be avoid to save costs)
2. use your own private repository (u/p or insecure)
3. use a locally-hosted docker repo (default: 192.168.48.2:5000)

For use cases (2) and (3) above, you can use a helper script to speed up the process of deploying a local docker repo and/or syncing official TSB docker images to those repos.

```console
# ./repo.sh 
Please specify correct action:
  - info : get local docker repo url (default: 192.168.48.2:5000)
  - start : start local docker repo
  - stop : stop local docker repo
  - remove : remove local docker repo
  - sync <target-repo> : sync tsb images from official repo to provided target repo (default: 192.168.48.2:5000)
```

### Networking and local kubernetes details

Every cluster (managementplane or controlplane) is deployed in a separate [docker network](https://docs.docker.com/engine/reference/commandline/network) with a separate subnet. VMs that are configured at the managementplane or controlplane are docker containers that run within that same network. The name of the docker network, matches the name of the cluster, which matches the name of the kubectl context.

In order to provide cross docker network connectivity, docker iptables rules are flushed (docker networks are isolated with iptables by design, and we do not want that here).

The reason to use separate docker networks, is mere convenience in terms of metallb dhcp pools and ip address assignment and traceability in general.

### Local docker repository details

The local docker registry mirror, if you choose to use that, is also deployed in a separate docker network, named `registry`.

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
- the names of your clusters (mapping to kubectl contexts and docker networks)
- how many kubernetes clusters you want
- how many tsb managementplane and controlplane clusters you want
- the networking aspects of those clusters (in terms of region/zone)
- the number of VMs you want, and where they are deployed

Currently a handful of useful topologies are available:

```console
# ls topologies -1

active-standby
demo-profile
hub-spoke
mp-only
transit-zones
tsb-training
vm-expansion
vm-only
infra-template.json
```

Take a look at the example template provided [here](./topologies/infra-template.json) to see how this works.

A short enumeration of the parameters to be configured:

|parameter|type|description|
|---------|----|-----------|
|cp_clusters|list|a list TSB controlplane clusters|
|cp_clusters.[].name|string|the name of this controlplane cluster (used as local kubectl context, docker network name and TSB cluster name)|
|cp_clusters.[].region|string|the region to configure for this controlplane cluster|
|cp_clusters.[].trust_domain|string|the trust domain to configure for this controlplane cluster|
|cp_clusters.[].zone|string|the zone to configure for this controlplane cluster|
|cp_clusters.[].vms|list|a list of VMs to spin-up in the same network as this controlplane cluster|
|cp_clusters.[].vms.[].image|string|the base image to use as VM|
|cp_clusters.[].vms.[].name|string|the name of this VM (used as hostname, docker container name and VM name)|
|k8s_provider|string|provider to be used by local kubernetes (`k3s`, `kind` or `minikube`)|
|k8s_version|string|version of kubernetes to be used by local kubernetes|
|mp_cluster|object|tsb managementplane cluster configuration|
|mp_cluster.name|string|the name of this managementplane cluster (used as local kubectl context, docker network name and TSB cluster name)|
|mp_cluster.region|string|the region to configure for the managementplane cluster|
|mp_cluster.trust_domain|string|the trust domain to configure for the managementplane cluster|
|mp_cluster.zone|string|the zone to configure for the managementplane cluster|
|mp_cluster.vms|list||a list of VMs to spin-up in the same network as the managementplane cluster|
|mp_cluster.vms.[].image|string|the base image to use as VM|
|mp_cluster.vms.[].name|string|the name of this VM (used as hostname, docker container name and VM name)|


## Scenarios

Scenarios are leveraging one available scenario. They will deploy TSB configuration (dependent on the topology!), kubernetes configuration, VM configuration/onboarding and anything else you might need or want.

The "interface" to the rest of the system is a `run.sh` file which is invoked by the top-level `makefile` system. It should contain a running hook (shell parameter) for `deploy` (deployment of your scenario), `undeploy` (clean-up scenario, bringing the system back to topology only) and `info` (information about the scenario in terms of ip address and useful commands to execute).

Current scenarios implemented on the available topologies all leverage our built-in `obs-tester-server`. One can implement any application as one sees fit or useful.

Scenarios should not limit themselves to demo applications. One can also implement a scenario to demonstrate gitops, ci/cd, telemetry, rbac or other integrations. As long as the components are docker/k8s friendly and there is no hard-coded external dependency, anything is possible.

Scenario documentation and screenshots are to be provided in the corresponding scenario subfolders within a topology (TODO).

| topology | scenario | description |
|----------|----------|-------------|
| [active-standby](./topologies/active-standby) | [abc-failover](./topologies/active-standby/scenarios/abc-failover) | mgmt cluster as T1, active cluster with a-b-c, standby cluster as failover |
| [hub-spoke](./topologies/hub-spoke) | [abc-def-ghi](./topologies/hub-spoke/scenarios/abc-def-ghi) | mgmt cluster as multi-tenant T1, a-b-c d-e-f and g-h-i as separate tenants |
| [transit-zones](./topologies/transit-zones) | [abcd-efgh](./topologies/transit-zones/scenarios/abcd-efgh) | mgmt cluster and 2 app clusters and 2 transit cluster, ab-cd and ef-gh bidirectional cross transit |
| [tsb-training](./topologies/tsb-training) | [main](./topologies/tsb-training/scenarios/main) | tsb training (cfr https://tsb-labs.netlify.app) |
| [vm-expansion](./topologies/vm-expansion) | [abc-hybrid](./topologies/vm-expansion/scenarios/abc-hybrid) | mgmt cluster as T1, a-b-c with a k8s only, b hybrid and c vm only |
| [vm-only](./topologies/vm-only) | [abc-vm](./topologies/vm-only/scenarios/abc-vm) | mgmt cluster as T1, a-b-c as VM only |


## Usage

After you have configured the necessary details in `env.json` as described above in [configuration](#configuration), you can spin-up the desired environment using `make`, which is self-documented.

```console
# make

help                           This help
up                             Bring up full demo scenario
down                           Bring down full demo scenario
info                           Get information about infra environment and scenario
prereq-check                   Check if prerequisites are installed
prereq-install                 Install prerequisites
infra-up                       Bring up and configure local kubernetes clusters and vms
infra-down                     Bring down local kubernetes clusters and vms
infra-info                     Get infra environment info
tsb-mp-install                 Install TSB management cluster
tsb-mp-uninstall               Uninstall TSB management cluster
tsb-cp-install                 Install TSB control/data plane(s)
tsb-cp-uninstall               Install TSB control/data plane(s)
scenario-deploy                Deploy this scenario
scenario-undeploy              Undeploy this scenario
scenario-info                  Info about this scenario
clean                          Clean up all resources
```

All temporary files (configuration, certificates, etc) are stored in [output](./output) folder, which is cleaned up with a `make clean` command as well.

The `info` and `scenario-info` target give more information about the topology and scenarios being used (ip addresses, ssh commands, kubectl commands, useful curl commands, etc).

> **Note:** all `makefile` targets are implemented to be idempotent, which means that you can run them once, or more, but the result should always be working. This means there is quite some code in the shell scripts that verifies if certain one-off actions are already done, and skips them if needed. Please take this into consideration when you add new scenarios.

## Repo structure and files

This section is a brief description of the repo structure itself. What folder and files are used, and what are they doing.

| file/folder | description |
|-------------|-------------|
|addons/|useful addons (wip). Eg: kibana for elastic index display, openldap-ui for ldap configuration, pgadmin for postgres exploration, etc|
|docker-vm/|the dockerfile for the VM, which is basically a docker image with systemd and some more|
|output/|structured output with temporary files like certificates, configuration, jwk's, etc|
|topologies/|the topologies available|
|topologies/<topology-name>/scenarios/<senario-name>/|a scenario available for a certain topology|
|certs.sh|script with functions to generate certificates with openssl (root, istio, server or client)|
|cp.sh|script to install tsb controlplane, based on the topology configured|
|env-template.json|env.json template to be copied and adjusted to your needs (never commit this one!)|
|helpers.sh|helper functions to add color in a madness of shell output|
|infra.sh|script to install the desired topology, using local kubernetes and docker|
|Makefile|the top level makefile and main entrypoint to be used by end-users|
|mp.sh|script to install tsb management plane, based on the topology configured|
|README.md|this file for documentation|
|prereq.sh|script to check some necessary prerequisites and avoid pain later down|
|repo.sh|helper scripts for local repo spinup and/or local/private repo syncing from TSB cloudsmith repo|
|scenario.sh|script responsible for interacting with the `run.sh` file of your scenario|

## Troubleshooting

### Known issues

In case one of the clusters fails to bootstrap all pods correctly with the error "too many open files", modify the following settings (on Ubuntu) in the file `/etc/sysctl.conf` and add these lines:

```
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

> **Reference:**  https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files


## TODOs

A non-exhaustive list of to be implemented items include:
 - add topology/scenario documentation and screenshots
 - none-demo TSB MP installation (ldap and oidc)
 - rpm based vm onboarding support
 - add support for helm/tf/pulumi to do the initial TSB mp/cp installation (currently `tctl` only)
    - in a scenario you are already free to use whatever you want
 - tsb training labs (https://github.com/tetrateio/tsb-labs) as a set of scenarios on a dedicated training topology
 - porting eshop-demo repo (https://github.com/tetrateio/eshop-demo/tree/main/docs) to here as well
 - more scenarios with real applications
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

