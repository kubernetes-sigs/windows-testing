# kubernetes-sigs/windows-testing

This repo is a collection of scripts, containers, and documentation needed to run Kubernetes test passes on clusters with Windows worker nodes. It is maintained by [sig-windows](https://github.com/kubernetes/community/tree/master/sig-windows).


If you're looking for the latest test results, look at [TestGrid](https://testgrid.k8s.io/sig-windows) for the SIG-Windows results. These are the periodic test passes scheduled by Prow ([see: config](https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes-sigs/sig-windows/sig-windows-config.yaml)). If you have questions interpreting the results, please join us on Slack in #SIG-Windows.


If you're new to building and testing Kubernetes, it's probably best to read the official [End-to-End Testing in Kubernetes](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md) page first. The rest of this page has a summary of those steps tailored to testing clusters with Windows nodes.


## Building Tests

### e2e.test

The official steps are in [kubernetes/community](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md#building-kubernetes-and-running-the-tests). For more details, be sure to read that doc. This is just a short summary.

Make sure you have a working [Kubernetes development environment](https://github.com/kubernetes/community/blob/master/contributors/devel/development.md) on a Mac or Linux machine. If you're using Windows, you can use WSL, but it will be slower than a Linux VM. The tests can be run from the same VM, as long as you have a working KUBECONFIG.

```bash
go get -d k8s.io/kubernetes
cd $GOPATH/src/k8s.io/kubernetes
./build/run.sh make WHAT=test/e2e/e2e.test
```
Once complete, the binary will be available at: `~/go/src/k8s.io/kubernetes/_output/dockerized/bin/linux/amd64/e2e.test`

#### Cross-building for Mac or Windows

To build a binary to run on Mac or Windows, you can add `KUBE_BUILD_PLATFORMS`.

For Windows
```bash
./build/run.sh make KUBE_BUILD_PLATFORMS=windows/amd64 WHAT=test/e2e/e2e.test
```

For Mac
```bash
./build/run.sh make KUBE_BUILD_PLATFORMS=darwin/amd64 WHAT=test/e2e/e2e.test
```

Your binaries will be available at `~/go/src/k8s.io/kubernetes/_output/dockerized/bin/linux/amd64/e2e.test` where `linux/amd64/` is replaced by `KUBE_BUILD_PLATFORMS` if you are building on Mac or Windows.


## Running an e2e test pass


### Using an existing cluster

All of the tests are built into the `e2e.test` binary, which you can as a standalone binary to test an existing cluster.

There are a few important parameters that you need to use:

- `--provider=skeleton` - this will avoid using a cloud provider to provision new resources such as storage volumes or load balancers
- `--ginkgo.focus="..."` - this regex chooses what [Ginkgo](http://onsi.github.io/ginkgo/) tests to run.
- `--node-os-distro="windows"` - some test cases have different behavior on Linux & Windows. This tells them to test Windows.
- `--ginkgo.skip="..."` - this regex chooses what tests to skip
- If you're not sure what test cases will run, add `--gingkgo.dryRun=true` and it will give a list of test cases selected without actually running them.

`e2e.test` also needs a few environment variables set to connect to the cluster, and choose the right test container images. Here's an example:

```bash
export KUBECONFIG=path/to/kubeconfig
curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-ws2019 -o repo_list
export KUBE_TEST_REPO_LIST=$(pwd)/repo_list
```

Once those are set, you could run all the `[SIG-Windows]` tests with:

```
./e2e.test --provider=skeleton --ginkgo.noColor --ginkgo.focus="\[sig-windows\]" --node-os-distro="windows"
```

The full list of what is run for TestGrid is in the [sig-windows-config.yaml](https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes-sigs/sig-windows/sig-windows-config.yaml) after `--test-args`. You can copy the parameters there for a full test pass.

```
./e2e.test --provider=skeleton --node-os-distro=windows --ginkgo.focus=\\[Conformance\\]|\\[NodeConformance\\]|\\[sig-windows\\]|\\[sig-apps\\].CronJob --ginkgo.skip=\\[LinuxOnly\\]|\\[k8s.io\\].Pods.*should.cap.back-off.at.MaxContainerBackOff.\\[Slow\\]\\[NodeConformance\\]|\\[k8s.io\\].Pods.*should.have.their.auto-restart.back-off.timer.reset.on.image.update.\\[Slow\\]\\[NodeConformance\\]"
```

### Using kubetest to deploy, test, and clean up a cluster

Kubetest is a wrapper that includes everything needed to deploy a cluster, test it (using e2e.test), gather logs, then upload the results to a Google Storage account. It has built-in cloud provider scripts to build Linux+Windows clusters using Azure and GCP.


#### Azure

> TODO: This section is still under construction

Set environment variables:

`AZURE_SSH_PUBLIC_KEY_FILE` - Path to the SSH public key you want to use for connecting to the cluster nodes. This is probably `~/.ssh/id_rsa.pub`

`AZURE_CREDENTIALS` - Path to a TOML file with a service account credential that will be used for creating the Azure resources

```toml
[Creds]
  ClientID = ""
  ClientSecret = ""
  SubscriptionId = ""
  TenantID = ""
  StorageAccountName = ""
  StorageAccountKey = ""
```

Once those are set, you can run `kubetest` and it will do the rest. The full set of tests will take 6-7 hours.

```bash
export KUBE_MASTER_IP=#IP of master node if running remotely, or localhost if running on master node
export KUBE_MASTER_URL="http://${KUBE_MASTER_IP}:8080"
export KUBECONFIG=#path/to/kubeconfig
curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-ws2019 -o repo_list
export KUBE_TEST_REPO_LIST=$(pwd)/repo_list
export AZURE_CREDENTIALS=TODO
kubetest --test=true \
  --up=true \
  --down=true \
  --deployment=acsengine \
  --provider=skeleton \
  --build=bazel \
  --acsengine-location=westus \
  --acsengine-admin-username=azureuser \
  --acsengine-admin-password=MakeItSecure123! \
  --acsengine-creds=$AZURE_CREDENTIALS \
  --acsengine-download-url=https://github.com/Azure/aks-engine/releases/download/v0.30.0/aks-engine-v0.30.0-linux-amd64.tar.gz \
  --acsengine-public-key=$AZURE_SSH_PUBLIC_KEY_FILE \
  --acsengine-winZipBuildScript=https://raw.githubusercontent.com/Azure/acs-engine/master/scripts/build-windows-k8s.sh \
  --acsengine-orchestratorRelease=1.13 \
  --acsengine-template-url=https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/job-templates/kubernetes_release.json \
  --acsengine-agentpoolcount=3 \
  --test_args=--node-os-distro=windows --ginkgo.focus=\\[Conformance\\]|\\[NodeConformance\\]|\\[sig-windows\\]|\\[sig-apps\\].CronJob --ginkgo.skip=\\[LinuxOnly\\]|\\[k8s.io\\].Pods.*should.cap.back-off.at.MaxContainerBackOff.\\[Slow\\]\\[NodeConformance\\]|\\[k8s.io\\].Pods.*should.have.their.auto-restart.back-off.timer.reset.on.image.update.\\[Slow\\]\\[NodeConformance\\]
```

## Running unit test

Note: This assumes the Windows node is running on GCE, but should be applicable
to other platforms with slight changes.

Unit tests for files that have a `// +build windows` at the first line should be
running on windows environment. Running in Linux with command

```
GOOS=windows GOARCH=amd64 go test
```

will usually have a `exec format error`.

### Steps for running unit tests on windows environment

#### Install golang on Windows machine

Download the go msi for windows from [here](https://golang.org/dl/) and scp it
to windows node for installation.

Add go path to the `PATH` environment variable:

```
$env:PATH=$env:PATH+";C"\go\bin"
```

Set the `GOPATH` environment variable:

```
$env:GOPATH="C:\go\pkg"
```

#### Install git using chocolatey

Follow the instruction [here](https://chocolatey.org/install) to install
chocolatey on Windows node. Then run

```
choco install git.install
```

to install git.

#### Scp the files and corresponding test files to the Windows machine

```
gcloud compute scp --recurse [FILE_PATHS_LOCAL]  [WINDOWS_NODE_NAME]:/C:/[PATH_ON_WINDOWS]
```

#### Run the tests

```
go get  # Install the required packages
go test  # Run the tests
```

#### Google Compute Platform

> TODO: This section is still under construction

## Building Test Images

[images/](images/README.md) - has all of the container images used in e2e test passes and the scripts to build them. They are replacement Windows containers for those in [kubernetes/test/images](https://github.com/kubernetes/kubernetes/tree/master/test/images)
