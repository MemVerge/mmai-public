# MMAI Install Guide

## Prerequisites

- Access to a Kubernetes v1.28+ cluster with `cluster-admin` role. Supported distributions are:
    - Vanilla Kubernetes
    - K3s
- CRI runtime support (https://kubernetes.io/docs/setup/production-environment/container-runtimes/):
  - `Containerd`: v1.7+.
  - `CRI-O`: v1.28+.
  - Others are not supported.
- Ingress Controller is set up in the cluster. There are many choices. See https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/.
- A default storage class is set up in the cluster to dynamically create persistent volume claims.
  - To support checkpoint feature, the storage class must be able to move a persistent volume from one node to another.
- The following helm charts are subcomponents of MMAI; they are deployed automatically, and should not be present on the cluster prior to MMAI installation:
  - `NVIDIA GPU Operator` and its dependencies (`DCGM Exporter`, `NVIDIA Device Plugin`, `Node Feature Discovery`, etc.)
  - `HAMi`
  - `Prometheus Operator` and its derivatives, such as `kube-state-metrics`
  - `Rancher`
- `kubectl` version v1.28+.
- `Helm` version v3.14+.
- Download the `mvai` package from the [releases page](https://github.com/MemVerge/mmai-public/releases) that includes:
  - Binary `mvaictl` to manage MemVerge.ai product from cmdline.
  - Script `mvai-cleanup.sh` to fully cleanup MemVerge.ai installation.

## Acquire GitHub Token

Contact MemVerge Customer Support (support@memverge.com) to acquire a personal access token of GitHub account `mv-customer-support` for downloading MMAI helm chart and container images.

## Login to GitHub Registry

```sh
helm registry login ghcr.io/memverge
# Username: mv-customer-support
# Password: <personal-access-token>
```

## Create Image Pull Secret

```sh
kubectl create namespace cattle-system

kubectl create secret generic memverge-dockerconfig --namespace cattle-system \
  --from-file=.dockerconfigjson=$HOME/.config/helm/registry/config.json \
  --type=kubernetes.io/dockerconfigjson
```

## Install cert-manager

> Skip this step if `cert-manager` is already installed.

```sh
helm repo add jetstack https://charts.jetstack.io --force-update

helm install cert-manager jetstack/cert-manager --namespace cert-manager \
  --create-namespace --set crds.enabled=true
```
Or check https://cert-manager.io/docs/installation for other options.

## Install MMAI

The MMAI management server is designed to be secure by default and requires SSL/TLS configuration.
There are three recommended options for the source of the certificate used for TLS termination at the MMAI server:

### 1. MMAI-generated Certificate

The default is for MMAI to generate a CA and uses `cert-manager` to issue the certificate for access to the MMAI server interface.

```sh
helm install --namespace cattle-system mmai oci://ghcr.io/memverge/charts/mmai \
  --wait --timeout 20m --version <version> \
  --set hostname=<load-balancer-hostname> --set bootstrapPassword=admin
```
- Set the `hostname` to the DNS name of the load balancer.
  - If there is only one control-plane node and there is no load balancer, the `hostname` can be the DNS name of the control-plane node.
  - If this single control-plane node has no DNS name, a fake domain name `<IP_OF_NODE>.sslip.io` can be used.
- Set the `bootstrapPassword` to something unique for the admin user.
- Note that the `version` should not include prefix `v`. To install the latest development version, replace the `--version <version>` option with `--devel` in the install command.

### 2. Let's Encrypt

<details>
This option uses `cert-manager` to automatically request and renew `Let's Encrypt` certificates. This is a free service that provides you with a valid certificate as `Let's Encrypt` is a trusted CA.

```sh
helm install --namespace cattle-system mmai oci://ghcr.io/memverge/charts/mmai \
  --wait --timeout 20m --version <version> \
  --set hostname=<load-balancer-hostname> --set bootstrapPassword=admin \
  --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=<me@example.org> \
  --set letsEncrypt.ingress.class=<ingress-controller-name>
```
</details>

### 3. Bring Your Own Certificate

<details>
In this option, Kubernetes secrets are created from your own certificates for MMAI to use.

When you run this command, the hostname option must match the Common Name or a Subject Alternative Names entry in the server certificate or the Ingress controller will fail to configure correctly.

```sh
helm install --namespace cattle-system mmai oci://ghcr.io/memverge/charts/mmai \
  --wait --timeout 20m --version <version> \
  --set hostname=<load-balancer-hostname> --set bootstrapPassword=admin \
  --set ingress.tls.source=secret
```

If you are using a Private CA signed certificate , add `--set privateCA=true` to the command:

```sh
helm install --namespace cattle-system mmai oci://ghcr.io/memverge/charts/mmai \
  --wait --timeout 20m --version <version> \
  --set hostname=<load-balancer-hostname> --set bootstrapPassword=admin \
  --set ingress.tls.source=secret --set privateCA=true
```
Now that MMAI is deployed, see [Adding TLS Secrets](add-tls-secrets.md) to publish your certificate files so MMAI and the Ingress controller can use them.
</details>

## Billing Database Installation
Billing features require persistent storage. By default, the cluster's default `StorageClass` is used. If the cluster doesn't have a default storage class capable of provisioning a volume for billing, there are a few alternative ways to configure persistent storage.

**Note:** NFS should be used with caution. `root-squash` is incompatible, and other configurations may cause issues, such as mount options or NFS version constraints. See the [MySQL documentation](https://dev.mysql.com/doc/refman/8.4/en/disk-issues.html#disk-issues-nfs) for details.

### Configuring Billing to Use a Non-Default StorageClass
If the cluster has an alternative `StorageClass` suitable for the billing database, you can override the default `StorageClass` by adding the following flag to the `helm install mmai` command:

```sh
--set billing.database.volume.pvc.storageClass=[StorageClass name]
```

### Configuring the Installation to Use a Predefined PVC
If the cluster administrator wants to manually define a PVC for the billing database, disable automatic PVC creation by setting the `StorageClass` to an empty string:

```sh
--set billing.database.volume.pvc.storageClass=""
```

### Configuring the Installation to Use a HostPath Mount
The billing database can be configured to use `hostPath` storage, which directly creates and mounts a directory on the host node to the billing database pod. To enable `hostPath` storage, add the following flag to the `helm install mmai` command:

```sh
--set billing.database.volume.type="hostPath"
```

By default, the directory `/data/memverge/mmai/mysql-billing` is used. This path can be overridden with the following flag:

```sh
--set billing.database.volume.hostPath.path="/desired/path/here"
```

## Uninstall MMAI

This command deletes the MMAI deployment, but leaves MMAI CRDs and user-created MMAI CRs in the cluster.

```sh
helm uninstall --namespace cattle-system mmai
```

To completely cleanup MMAI resources, run the `mvai-cleanup.sh` script from the released `mvai` package.
