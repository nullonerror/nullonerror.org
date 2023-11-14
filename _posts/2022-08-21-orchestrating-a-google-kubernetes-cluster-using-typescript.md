---
layout: post
title: >
  Orchestrating a Google Kubernetes cluster using TypeScript
---

![kubectl](/public/2022-08-21-orchestrating-a-google-kubernetes-cluster-using-typescript/kubectl.jpg){: .center }

This post is more to me remember how to do this in the future, but in any case, someone else can need.

### Dependencies

First of all, you need two dependencies. There is no need to install the types because these libraries are written in TypeScript:

```shell
npm install --save @google-cloud/container @kubernetes/client-node
```

- `@google-cloud/container` is needed to get access to the Google Kubernetes Engine.
- `@kubernetes/client-node` is required to operate Kubernetes, deploy manifests, get pods, and everything that kubectl does.

At this time, you may have an error during the build, to solve this, add this extra dev dependency.

```shell
npm install --save-dev @types/tar
```

### Authorizing

If you are running your code inside any Google Cloud service, you do not need to do anything else besides the lines below:

```typescript
import * as googleContainer from "@google-cloud/container";

const client = new googleContainer.v1.ClusterManagerClient();

async function getCredentials(cluster: string, zone: string) {
  const projectId = await client.getProjectId();
  const accessToken = await client.auth.getAccessToken();
  const request = {
    projectId: projectId,
    zone: zone,
    clusterId: cluster,
  };

  const [response] = await client.getCluster(request);
  return {
    endpoint: response.endpoint,
    certificateAuthority: response.masterAuth?.clusterCaCertificate,
    accessToken: accessToken,
  };
}
```

Then to use it is pretty simple:

```typescript
import * as k8s from "@kubernetes/client-node";

const clusterName = "cluster-1";
const zone = "us-central1-c";

const k8sCredentials = await getCredentials(clusterName, zone);
const k8sClientConfig = new k8s.KubeConfig();

k8sClientConfig.loadFromOptions({
  clusters: [
    {
      name: clusterName,
      caData: k8sCredentials.certificateAuthority,
      server: `https://${k8sCredentials.endpoint}`,
    },
  ],
  users: [
    {
      name: clusterName,
      token: k8sCredentials.accessToken,
    },
  ],
  contexts: [
    {
      name: clusterName,
      user: clusterName,
      cluster: clusterName,
    },
  ],
  currentContext: clusterName,
});

const k8sApi = await k8sClientConfig.makeApiClient(k8s.CoreV1Api);
```

`k8sApi` is all you need to operate a Kubernetes cluster.

### Applying a manifest

The code below does the same of `kubectl apply -f manifest.yaml`:

```typescript
import { promises as fs } from "fs";
import * as yaml from "js-yaml";
import * as path from "path";
import type { KubernetesObject } from "@kubernetes/client-node";

const specs = yaml.loadAll(await fs.readFile(path.resolve("manifest.yaml"), "utf-8")) as KubernetesObject[];

const validSpecs = specs.filter((spec) => spec && spec.kind && spec.metadata);

for (const spec of validSpecs) {
  spec.metadata = spec.metadata || {};
  spec.metadata.annotations = spec.metadata.annotations || {};
  delete spec.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"];
  spec.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"] = JSON.stringify(spec);

  try {
    // if exists, update it
    await k8sApi.read(spec);
    await k8sApi.patch(spec);
  } catch (e) {
    // if not exist, create it
    await k8sApi.create(spec);
  }
}
```

The code above works fine in a Firebase Function and should work in any Google Cloud product without any change. If you want to run in another environment, you need to load Google's credentials before all. To know how to do this, see my other post [Accessing Google Firestore on Vercel](https://nullonerror.org/2021/06/14/accessing-google-firestore-on-vercel/).
