---
layout: post
title: >
  Kubernetes in Docker with Docker compose
---

### What is this?

Kind is _Kubernetes IN Docker_, a local clusters for testing Kubernetes.

### Requirements

First of all, you will need [kind](https://kind.sigs.k8s.io/), [go](https://go.dev/dl/) and [Docker](https://www.docker.com/) (with [compose](https://docs.docker.com/compose/)) installed. Go is not necessary because we only will use Docker.

Then, clone my [repository](https://github.com/skhaz/kind-with-docker-compose)

```shell
git clone git@github.com:skhaz/kind-with-docker-compose.git
```

### Running

Run `make cluster` to create a new cluster.

Here is a simple Go app that lists all deployments on the default namespace

```go
package main

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"
)

var ctx = context.Background()

func main() {
	clientset := kubernetes.NewForConfigOrDie(ctrl.GetConfigOrDie())

	list, err := clientset.AppsV1().Deployments("default").List(ctx, metav1.ListOptions{})
	if err != nil {
		panic(err)
	}

	for _, item := range list.Items {
		fmt.Printf("Deploy %v\n", item)
	}
}

```

Run `make compose` and notice the following error:

```shell
panic: Get "https://127.0.0.1:33977/apis/apps/v1/namespaces/default/deployments": dial tcp 127.0.0.1:33977: connect: connection refused
```

That is because kind is _not running_ on the same network as the application. Let's fix it, on docker-compose.yaml add the following:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

And let's replace the hardcoded IP address from `kind.conf` to this hostname on `Makefile`

```shell
kubectl config view --raw | sed -E 's/127.0.0.1|localhost/host.docker.internal/' > kind.conf
```

Now let's run again `make compose`

```shell
panic: Get "https://host.docker.internal:33977/apis/apps/v1/namespaces/default/deployments": x509: certificate is valid for kind-control-plane, kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, localhost, not host.docker.internal
```

Nice, now the app can connect to kind, but the certificates that kind are issuing are not for `host.docker.internal`. To fix it, it is necessary to instruct kind to issue for _host.docker.internal_ too. To achieve this, passing a config during the creation of the cluster with a YAML file.

### Issuing the certificate

```shell
kind create cluster --config=kind.yaml
```

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatchesJSON6902:
  - group: kubeadm.k8s.io
    version: v1beta3
    kind: ClusterConfiguration
    patch: |
      - op: add
        path: /apiServer/certSANs/-
        value: host.docker.internal
```

Now destroy the cluster and create it again `make clean cluster`.

Create a deployment:

```shell
kubectl create deployment hello-node --image=k8s.gcr.io/echoserver
```

Run `make compose` again and see that it is connecting and listing all deployments 🎉

```shell
app_1  | Deploy hello-node  default  a9f91c80-1746-479c-a24d-f32b31c20cbd 398 1 2022-08-27 13:44:05 +0000... [very long line]
```

A special thanks to [Benjamin Elder](https://twitter.com/BenTheElder), who helped me with the certificate issuing.

[Full example](https://github.com/skhaz/kind-with-docker-compose)
