# Upstream kubernetes e2e testing with CAPZ for Windows

These scripts and templates are used with [cluster-api-provider-azure](https://github.com/kubernetes-sigs/cluster-api-provider-azure) and [azure cli extension](https://github.com/Azure/azure-capi-cli-extension).  

## Running the scripts

To run these scripts some setup is required.

First clone and configure the following repositories

### CAPZ repo setup

Clone the [cluster-api-provider-azure](https://github.com/kubernetes-sigs/cluster-api-provider-azure) and checkout / sync out the latest release branch.

### Cloud Provider Azure repo setup

Clone the [cloud-provider-azure](https://github.com/kubernetes-sigs/cloud-provider-azure) and checkout / sync to the correct branch

- if testing kubernetes@master then checkout / sync to the master branch
- if testing a released version of Kubernetes then checkout / sync the corresponding release branch in the cloud-provider-azure repo

> Note: To run e2e tests with the same configurations as the upstream e2e test passes, look at the `extra_refs` section of the **ci-kubernetes-e2e-capz-master-windows** in
[release-master-windows.yaml](https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes-sigs/sig-windows/release-master-windows.yaml) to see which branches the SIG-Windows e2e test passes are using during the periodic jobs.

### Set environment variables

#### Required

```bash
export AZURE_SUBSCRIPTION_ID=<sub-id>
export AZURE_CLIENT_ID=<client-id>
export AZURE_CLIENT_SECRET=<client-secret>
export AZURE_TENANT_ID=<tenantid>
export CAPZ_DIR="$HOME/<path-to-repo>/cluster-api-provider-azure"
export AZURE_CLOUD_PROVIDER_ROOT="$HOME/<path-to-repo>/cloud-provider-azure"

# run-capz-e2e.sh builds and publishes cloud-provider-azure container images
# to the registry specified below.  Ensure you are logged in to the registry
# prior to running the script!
# TODO: Figure out how to use pre-built images here...
export REGISTRY="<registry>"

# optional for ability to use your own ssh key (otherwise it generates one)
# NOTE: Azure does not support ed25519 encrypted SSH keys!
export AZURE_SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_rsa.pub"
```

#### Optional

| ENV variable  | Description  |
| ------------- | ------------ |
| `API_SERVER_FEATURE_GATES` | Comma-separated list of feature-gates and their values to pass to the kube-apiserver (Defaults to "") |
| `AZURE_LOCATION` | The azure region to deploy resources into. If not specified a random region will be selected) |
| `KUBERNETES_VERSION`  | Valid values are `latest` (default) and  `latest-1.xx` where x is valid kubernetes minor version such as `latest-1.24` |
| `NODE_FEATURE_GATES` | Comma-seperated list of feature-gates and their values to pass to the kubelet (Defaults to "HPAContainerMetrics=true") |
| `NODE_MACHINE_TYPE` | The [Azure vm size](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes) to use for the nodes  |
| `RUN_SERIAL_TESTS` | If set to `true` then serial slow tests will be run with default ginkgo settings |
| `SKIP_CREATE` | Don't create a cluster.  Must set `CLUSTER_NAME` and have current a workload cluster kubeconfig file with name `./"${CLUSTER_NAME}".kubeconfig` |
| `SKIP_LOG_COLLECTION` | If set to `true` don't collect logs from the cluster |
| `SKIP_TEST`  | If set to `true` only creates the cluster, will not run tests |
| `SKIP_CLEANUP` | If set to `true` don't delete the cluster / resource group after script executions |
| `SCHEDULER_FEATURE_GATES` | Comma-separated list of feature-gates and their values to pass to the kube-scheduler (Defaults to "") |
| `WINDOWS_CONTAINERD_URL` | URL to a containerd release tarball to use for the Windows nodes (defaults to containerd v1.7.0)|
| `WINDOWS_KPNG` | If specified, will create a cluster using an out-of-tree kube-proxy implementation from [k-sigs/windows-service-proxy](https://github.com/kubernetes-sigs/windows-service-proxy) |
| `WINDOWS_SERVER_VERSION` | Set to `windows-2019` (default) or `windows-2022` to test Windows Server 2019 or Windows Server 2022 |
| `WINDOWS_WORKER_MACHINE_COUNT` | Number of **Windows** worker nodes to provision in the cluster (Defaults to 2) |

## GMSA support

Set the environment variable `GMSA=true`.

This requires additional set up in the Azure Subscriptions. See the readme in [gmsa folder](gmsa/readme.md).

## Testing custom Kubernetes components

`run-capz-e2e.sh` can provision clusters with custom Kubernetes components built from a local K8s repository.
This is used in PR jobs to validate the changes in the PR.

To do so ensure your local K8s repository is:

- cloned to **$GOPATH/src/k8s.io/kubernetes**
- checked out to the desired branch / commit

Additionally the following enviroment variables will need to be set:

| ENV variable | Description  |
| ------------- | ------------ |
| `AZURE_STORAGE_ACCOUNT` | The name of the Azure storage account to use for the custom builds |
| `AZURE_STORAGE_KEY` | A key for the Azure storage account |
| `JOB_NAME` | A unique job name used as a subpath in the AZURE_STORAGE_ACCOUNT to store the custom builds |

> Note: [ci-build-kubernetes.sh](https://github.com/kubernetes-sigs/cluster-api-provider-azure/blob/main/scripts/ci-build-kubernetes.sh) is called by run_capz_e2e.sh which will build the custom components and upload them to the Azure storage account!

## Hyper-V isolated containers support

Requires containerd v1.7+ deployed to the Windows nodes.

Set the environment variable `HYPERV=true`.

See [the HyperV testing README](../helpers/hyper-v-mutating-webhook/README.md) for more information.
