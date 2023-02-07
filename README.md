# Tetrate Service Bridge on Minikube


## Introduction

The purpose of this repo is to showcase TSB multi cluster and VM onboarding capabilities. In order to do so, we
will deploy a micro-service based demo application called **App ABC**:

 - You have the ability to deploy it in active mode
 - You have the ability to deploy it in active/standby mode
 - You have the ability to deploy it on VMs

We will be using [minikube](https://minikube.sigs.k8s.io/docs/start) and [virtualbox](https://www.virtualbox.org) to spin up the demo environment.

Before digging into the demo ENV itself, we highly recommend reading up on the conceptual
introduction in our official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/concepts).

> **Note:** make sure to rad the [resource requirement](#Resource requirements) for your scenario.

## Prequisites

The demo is fully scripted using shell scripts and makefile target.

```console
$ make
help                           This help
prereqs                        Make sure prerequisites are satisfied
infra-mgmt-up                  Bring up and configure mgmt minikube cluster
infra-active-up                Bring up and configure active minikube cluster
infra-standby-up               Bring up and configure standby minikube cluster
infra-vm-up                    Bring up and configure vms
infra-mgmt-down                Bring down and delete mgmt minikube cluster
infra-active-down              Bring down and delete active minikube cluster
infra-standby-down             Bring down and delete standby minikube cluster
infra-vm-down                  Bring down and delete vms
tsb-mgmt-install               Install TSB management/control/data plane in mgmt cluster (demo profile)
tsb-active-install             Install TSB control/data plane in active cluster
tsb-standby-install            Install TSB control/data plane in stanby cluster
reset-tsb                      Reset all TSB configuration
deploy-app-abc-k8s             Deploy abc application on kubernetes
deploy-app-abc-vm              Deploy abc application on vms
undeploy-app-abc-k8s           Undeploy abc application from kubernetes
undeploy-app-abc-vm            Undeploy abc application from vms
test-app-abc                   Generate curl commands to test ABC traffic
info                           Get infra environment info
clean                          Clean up all resources
```

In order to be able to sync the TSB docker images, you will need to set the following
environment variables before running the scripts.

```console
export TSB_DOCKER_USERNAME=<username>
export TSB_DOCKER_PASSWORD=<password>
```

Note that the following binaries needs to be installed and runnable on the system:

 - **awk** : to parse command line output
 - **curl** : to download cloud ubuntu vm
 - **docker** : to pull tsb images
 - **expect** : to automate shell interaction
 - **genisoimage** : to generate cloud-init for vms
 - **kubectl** : to interact with the kubernetes clusters
 - **minikube** : we will be using the virtualbox driver
 - **tctl** : the command line utility to interact with the tsb api's
 - **vboxmanage** : to automate vm handling

**DOC REF** Installation instructions for tctl can be found [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/reference/cli/guide/index#installation)


## Architecture

### TSB cluster design

The following diagram shows the overal architecture of the demo in terms of how various TSB 
components are deployed throughout the 3 clusters.

<p align="center">
  <img src="./imgs/POC-TSB-Clusters.drawio.png">
</p>

**DOC REF** More information on the overal TSB architecture and its different components can
be found [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/concepts/architecture)

### Kubernetes deployment design

#### Active/Standby Scenario

The following diagram shows to application deployments and its corresponding tier1, ingress and
east-west gateways for an active/standby scenario.

<p align="center">
  <img src="./imgs/POC-Kubernetes.drawio.png">
</p>

Although ingress and eastwest gateways can be combined into one single gateway, we have chosen
to deploy seperate instances for the sake of clarity, seperation of concerns and security.

**DOC REF** More information on the different gateway types supported by TSB can be found
[here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/howto/gateway)

#### Active/VMs Scenario

The following diagram shows to application deployments and its corresponding tier1, ingress and
vms for a k8s/vm scenario.

<p align="center">
  <img src="./imgs/POC-VM.drawio.png">
</p>

Every micro-service can be deployed as pod, as vm or both. In case the full application is deployed
as both pods and vm, full redudancy is provided (equal load balancing).

Note that this capability allows for a gradual vm to pod migration, but also allows integration
of vm workloads that are for some reasons not able/desired to run as pod.

**DOC REF** More information our different vm onboarding options can be found
[here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding)


### TSB multi-tenancy design

The following diagram shows how we configured TSB multi-tenancy concepts like organization,
tenants, workspaces and groups, which form the foundation of our RBAC system and also play
an important role in the configuration of traffic control and security.

<p align="center">
  <img src="./imgs/POC-TSB-Tenancy.drawio.png">
</p>

Note that TSB, by leveraging namespace selectors, is able to create an abstraction of your
application deployment strategy and therefor provides a mapping to your organizational 
structure, compared to traditional K8s RBAC approaches.

**DOC REF** More information on our tenancy concepts can be found in the official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/concepts/security)

Note also that the multi-tenancy design takes complete abstraction of your workloads in terms of where
and how they are hosted (PODs vs VMs).


## Installation

### STEP1: prepare minikube ENV

In order to be able to sync the TSB docker images, you will need to set the following
environment variables before preparing the minikube ENV.

```console
$ export TSB_DOCKER_USERNAME=<username>
$ export TSB_DOCKER_PASSWORD=<password>
```

In order to provide full demo flexibily, several scenario based [makefile](./Makefile) variables are available
to tweak the behavior of your setup.

| variable     | default | description                                 |
|--------------|---------|---------------------------------------------|
| TSB_VERSION  | 1.6.0   | TSB version                                 |
| K8S_VERSION  | 1.24.9  | Kubernetes version                          |
| TIER1_MODE   | http    | Tier1 exposure mode (http/https/mtls)       |
| TIER2_MODE   | http    | Tier2 expose mode (http/https)              |
| APP_ABC_MODE | active  | ABC deploy strategy (active/active-standby) |
| VM_APP_A     | enabled | deploy app-a as VM (enabled/disabled)       |
| VM_APP_B     | enabled | deploy app-b as VM (enabled/disabled)       |
| VM_APP_C     | enabled | deploy app-c as VM (enabled/disabled)       |

You have the option to change them manually at the top of the [makefile](./Makefile) or pass them as parameters
with your chosen target.

The following sequence will deploy the full demo ENV, including standby cluster and vms.
```console
$ export TSB_DOCKER_USERNAME=<username>
$ export TSB_DOCKER_PASSWORD=<password>

$ make APP_ABC_MODE=active-standby infra-mgmt-up infra-active-up infra-standby-up
$ make APP_ABC_MODE=active-standby infra-vm-up 
$ make APP_ABC_MODE=active-standby tsb-mgmt-install tsb-active-install tsb-standby-install
$ make APP_ABC_MODE=active-standby deploy-app-abc-k8s deploy-app-abc-vm
```

Note that the initial step might take some time (20-30min), as we need to pull all the TSB docker images
and also load them into the 2 or 3 different minikube profiles accordingly.

After this step has successfully completed, you should be able to interact with the
different clusters using kubectl.

```console
$ export TSB_DOCKER_USERNAME=<username>
$ export TSB_DOCKER_PASSWORD=<password>

$ make APP_ABC_MODE=active-standby infra-mgmt-up infra-active-up infra-standby-up
$ make APP_ABC_MODE=active-standby infra-vm-up

$ minikube profile list
|-----------------|------------|---------|----------------|------|---------|---------|-------|--------|
|    Profile      | VM Driver  | Runtime |      IP        | Port | Version | Status  | Nodes | Active |
|-----------------|------------|---------|----------------|------|---------|---------|-------|--------|
| active-cluster  | virtualbox | docker  | 192.168.59.100 | 8443 | v1.24.9 | Running |     1 |        |
| mgmt-cluster    | virtualbox | docker  | 192.168.59.101 | 8443 | v1.24.9 | Running |     1 |        |
| standby-cluster | virtualbox | docker  | 192.168.59.102 | 8443 | v1.24.9 | Running |     1 |        |
|-----------------|------------|---------|----------------|------|---------|---------|-------|--------|

$ vboxmanage list runningvms
"mgmt-cluster" {99a4ccfd-e03a-4fb2-af75-46430e467684}
"active-cluster" {cf652f97-78b7-4a38-a89b-ed3f91f1e6b6}
"standby-cluster" {4d2aaf91-5a5f-4324-9f06-bdaf48acc982}
"ubuntu-vm-a" {7e154342-f7ae-43cf-90b3-8b3f9bd11d70}
"ubuntu-vm-b" {9ed3243f-b344-4b4e-9cac-75c3a2755565}
"ubuntu-vm-c" {b25d6243-89e7-48ef-ac84-7cb8df321a5f}

$ make info
kubectl --profile mgmt-cluster get pods -A
kubectl --profile active-cluster get pods -A
kubectl --profile standby-cluster get pods -A
TSB GUI: https://admin:admin@192.168.59.40:8443
ssh -i ./config/04-ubuntu-vm-a/tsbadmin -o StrictHostKeyChecking=no tsbadmin@192.168.59.218
ssh -i ./config/05-ubuntu-vm-b/tsbadmin -o StrictHostKeyChecking=no tsbadmin@192.168.59.219
ssh -i ./config/06-ubuntu-vm-c/tsbadmin -o StrictHostKeyChecking=no tsbadmin@192.168.59.220

$ kubectl --context mgmt-cluster get pods -A
NAMESPACE        NAME                                      READY   STATUS    RESTARTS   AGE
kube-system      coredns-57575c5f89-lgn6q                  1/1     Running   0          19m
kube-system      etcd-mgmt-cluster                         1/1     Running   0          20m
kube-system      kube-apiserver-mgmt-cluster               1/1     Running   0          20m
kube-system      kube-controller-manager-mgmt-cluster      1/1     Running   0          20m
kube-system      kube-proxy-nmtsg                          1/1     Running   0          19m
kube-system      kube-scheduler-mgmt-cluster               1/1     Running   0          20m
kube-system      storage-provisioner                       1/1     Running   0          20m
metallb-system   controller-6747c7bbcb-g9sbs               1/1     Running   0          18m
metallb-system   speaker-njl6k                             1/1     Running   0          18m

$ kubectl --context active-cluster get pods -A
NAMESPACE        NAME                                        READY   STATUS    RESTARTS      AGE
kube-system      coredns-57575c5f89-6c9d8                    1/1     Running   0             19m
kube-system      etcd-active-cluster                         1/1     Running   0             19m
kube-system      kube-apiserver-active-cluster               1/1     Running   0             19m
kube-system      kube-controller-manager-active-cluster      1/1     Running   0             19m
kube-system      kube-proxy-gh9gt                            1/1     Running   0             19m
kube-system      kube-scheduler-active-cluster               1/1     Running   0             19m
kube-system      storage-provisioner                         1/1     Running   1 (18m ago)   19m
metallb-system   controller-6747c7bbcb-gw4jc                 1/1     Running   0             18m
metallb-system   speaker-qnz78                               1/1     Running   0             18m

$ kubectl --context standby-cluster get pods -A
NAMESPACE        NAME                                         READY   STATUS    RESTARTS      AGE
kube-system      coredns-57575c5f89-2mm5t                     1/1     Running   0             18m
kube-system      etcd-standby-cluster                         1/1     Running   0             19m
kube-system      kube-apiserver-standby-cluster               1/1     Running   0             19m
kube-system      kube-controller-manager-standby-cluster      1/1     Running   0             19m
kube-system      kube-proxy-4g6mz                             1/1     Running   0             18m
kube-system      kube-scheduler-standby-cluster               1/1     Running   0             19m
kube-system      storage-provisioner                          1/1     Running   1 (18m ago)   19m
metallb-system   controller-6747c7bbcb-gddkj                  1/1     Running   0             18m
metallb-system   speaker-xvxvk                                1/1     Running   0             18m
```

### Step2: install TSB mgmt plane

In this step we will be installing the TSB management plane in the management cluster. We will be leveraging the demo profile that comes with tctl, as it ships with all the necessary external
dependancies of the TSB platform (postgres and elasticsearch). In a production ENV you will be
integrating this with external services.

Note that the demo profile also installs a control and data plane in the management cluster itself.
In a production ENV this is not strictly necessary however. We will also leverage this to host our
Tier1 Gateways, which will be the entrypoints for external traffic destined for application ABC and DEF.

```
$ make tsb-mgmt-install
```

**DOC REF** More information on the mgmt plane installation, including the demo profile, can be found in the official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/management-plane-installation)

After this step has successfully completed, you should be able to log in into the management plane
GUI as provided in the traces above.

> Open your browser and go to https://192.168.49.100:8443 (admin/admin) to get a first glimps of the platform's GUI.

### Step3: onboard application clusters

In this step we will onboard the application clusters onto the management plane. 

```
$ make tsb-active-install
$ make tsb-standby-install
```

**DOC REF** More information on the control plane installation, can be found in the official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters)

### Step5: configure tsb and deploy the applications

In this step we will be configuring TSB concepts like cluster, organization and tenants, prepare our tier1 namespace and deploy the actual application ABC.

**DOC REF** More information on TSB configuration, can be found in the official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/quickstart)

If application ABC is deployed in an active/standby mode. This means that in a normal situation, as traffic is routed to the active clusters and the traffic will remain there. If however, one of the microservices in the active cluster becomes unhealthy or unavailable, traffic will automatically be routed to the standby cluster, providing zero downtime.

You have the option to terminate Tier1 connections on HTTP/80, HTTPS/443 server side TLS or HTTPS/443 mTLS (check make commands) and Tier2 (ingress) Tier1 connections on HTTP/80, HTTPS/443 server side TLS. Check the
[makefile](./Makefile) variables descrived earlier for more information.

```console
$ make deploy-app-abc-k8s
$ make deploy-app-abc-vm
```

**DOC REF** More information on application onboarding, can be found in the official documentation [here](https://docs.tetrate.io/service-bridge/1.6.x/en-us/quickstart)

For the actual microservice deployment we are using a container named `obs-tester-server`, which is also available on dockerhub [here](https://hub.docker.com/r/nacx/obs-tester-server). This demo application provides us with the flexibility to demo a variety of scenario's. It will listen as an HTTP or TCP server on a certain port, and is able to establish a new HTTP connection to a next hop, by stripping away some of the URL parameters provided in the incoming URL.

We have provided a helper makefile target to give you an idea on how to use this application.

```console
$ make test-app-abc 

Switched to context "mgmt-cluster".
Switched to context "active-cluster".
Switched to context "standby-cluster".

****************************
*** ABC Traffic Commands ***
****************************

Traffic to Active Ingress Gateway: HTTP
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:80:192.168.59.60" "http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 
Traffic to Standby Ingress Gateway: HTTP
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:80:192.168.59.80" "http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 

Traffic to Active Ingress Gateway: HTTPS
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:443:192.168.59.60" --cacert ca.crt=certs/root-cert.pem "https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 
Traffic to Standby Ingress Gateway: HTTPS
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:443:192.168.59.80" --cacert ca.crt=certs/root-cert.pem "https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 


Traffic through T1 Gateway: HTTP
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:80:192.168.59.41" "http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 

Traffic through T1 Gateway: HTTPS
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:443:192.168.59.41" --cacert ca.crt=certs/root-cert.pem "https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 

Traffic through T1 Gateway: MTLS
curl -k -v -H "X-B3-Sampled: 1" --resolve "abc.tetrate.prod:443:192.168.59.41" --cacert ca.crt=certs/root-cert.pem --cert certs/app-abc/client.abc.tetrate.prod.pem --key certs/app-abc/client.abc.tetrate.prod.key "https://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" 
```

One of the curl command above will send traffic to our Tier1 gateway in the mgmt cluster. Because of the URL path provided (proxy/app-b.ns-b/proxy/app-c.ns-c), the first hop app-a will be able to know that it needs to send traffic to app-b in namespace ns-b. It will strip that part and forward it to the next hop, where app-b will know it needs to send traffic to app-c in namespace ns-c.

You can use the same techique to deploy and test application DEF. Try sending some traffic across a path that you do not expect to be available (eg app-a => app-e etc).

Notice that we also include a header `X-B3-Sampled: 1`, in order for extra tracing headers to become available in TSB as well. It is an upstream istio requirement for any application to propagate the correct B3 tracing headers in order to have a full traffic dependancy graph. This demo application does that automatically for you.

Let's test our ABC traffic scenario:

```console
curl -k -v -H "X-B3-Sampled: 1" "http://abc.tetrate.prod/proxy/app-b.ns-b/proxy/app-c.ns-c" --resolve "abc.tetrate.prod:80:192.168.49.101"
* Added abc.tetrate.prod:80:192.168.49.101 to DNS cache
* Hostname abc.tetrate.prod was found in DNS cache
*   Trying 192.168.49.101:80...
* Connected to abc.tetrate.prod (192.168.49.101) port 80 (#0)
> GET /proxy/app-b.ns-b/proxy/app-c.ns-c HTTP/1.1
> Host: abc.tetrate.prod
> User-Agent: curl/7.81.0
> Accept: */*
> X-B3-Sampled: 1
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< content-length: 1078
< content-type: application/json
< date: Sun, 22 Jan 2023 20:03:33 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 113
< 
{
  "service": "app-c",
  "statusCode": 200,
  "traceID": "fc3a002fe73c8f1441c1f6db348c3d38",
  "headers": {
    "Accept": [
      "*/*"
    ],
    "Accept-Encoding": [
      "gzip"
    ],
    "Proxied-By": [
      "app-a",
      "app-b"
    ],
    "User-Agent": [
      "curl/7.81.0"
    ],
    "X-B3-Parentspanid": [
      "22da97fdb70ca791"
    ],
    "X-B3-Sampled": [
      "1"
    ],
    "X-B3-Spanid": [
      "915e28ca615f43cb"
    ],
    "X-B3-Traceid": [
      "fc3a002fe73c8f1441c1f6db348c3d38"
    ],
    "X-Envoy-Attempt-Count": [
      "1"
    ],
    "X-Envoy-External-Address": [
      "172.17.0.1"
    ],
    "X-Forwarded-Client-Cert": [
      "By=spiffe://active-cluster.tsb.local/ns/ns-c/sa/sa-app-c;Hash=6af04db472f2e1e08cc676116ade3d017021a0c64fa21b75f0e5984bf43dd8ac;Subject=\"\";URI=spiffe://active-cluster.tsb.local/ns/ns-b/sa/sa-app-b"
    ],
    "X-Forwarded-For": [
      "172.17.0.1,172.17.0.1, 127.0.0.6, 127.0.0.6"
    ],
    "X-Forwarded-Proto": [
      "https"
    ],
    "X-Request-Id": [
      "9f1d3c91-a210-48df-bfb8-0a7ebacbffc7"
    ]
  }
}
* Connection #0 to host abc.tetrate.prod left intact
```

As you can see, every hop within the traffic path will also enrich the HTTP response field, so we can trace in detail where and how the actual traffic has flown. In this case we have hit 4 different hops (tier1, app-a, app-b and app-c).

Now try to run this command in a while loop, while scaling the deployment of app-b in the active cluster to 0 in order to mimic an application failure. You will see the traffic automatically being switched to the standby cluster (observe the SPIFFE identifier in the above traces).

> Open your browser and go to https://192.168.49.100:8443 (admin/admin) and notice the topology and traffic patterns.

## Troubleshooting

### Known issues

In case one of the cluster fails to bootstrap all pods correctly with the error "too many open files", modify the following settings (on Ubuntu) in the file `/etc/sysctl.conf` and add these lines:

```
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

> **Reference:**  https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files


### Resource requirements

With the whole demo running in active-standby mode, the following resource consumption per cluster is observer:

```console
# kubectl --context mgmt-cluster describe nodes | grep  "Allocated resources:" -A 7
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                3950m (65%)   18700m (311%)
  memory             9306Mi (77%)  26690Mi (223%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)


# kubectl --context active-cluster describe nodes | grep  "Allocated resources:" -A 7
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                3894m (64%)   22184m (369%)
  memory             7750Mi (86%)  25498Mi (285%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)

# kubectl --context standby-cluster describe nodes | grep  "Allocated resources:" -A 7
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                3894m (64%)   22184m (369%)
  memory             7750Mi (86%)  25498Mi (285%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
```

The resource requirements reserved by the minikube vms and application vms are as follows:

| Name            | Memory | Description                  |
|-----------------|--------|------------------------------|
| mgmt-cluster    | 12 GB  | tsb management place         |
| active-cluster  | 9 GB   | active onboarded cluster     |
| standby-cluster | 9 GB   | standby onboarded cluster    |
| ubuntu-vm-a     | 2 GB   | app-a ubuntu vm              |
| ubuntu-vm-b     | 2 GB   | app-b ubuntu vm              |
| ubuntu-vm-c     | 2 GB   | app-c ubuntu vm              |
| full demo       | 36 GB  | active/standby and abc as vm |

### Debugging

In order to debug issues, you can use the `netshoot` container with debug tools in any given cluster, namespace provided.

```console
# Netshoot in mgmt-cluster and default namespace
kubectl --context mgmt-cluster -n default run tmp-shell --rm --image-pull-policy IfNotPresent -i --tty --image containers.dl.tetrate.io/netshoot -- /bin/bash

# Netshoot in active-cluster and ns-a namespace
kubectl --context active-cluster -n ns-a run tmp-shell --rm --image-pull-policy IfNotPresent -i --tty --image containers.dl.tetrate.io/netshoot -- /bin/bash

# Netshoot in standby-cluster and ns-b namespace
kubectl --context standby-cluster -n ns-b run tmp-shell --rm --image-pull-policy IfNotPresent -i --tty --image containers.dl.tetrate.io/netshoot -- /bin/bash
```
