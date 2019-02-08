# kubernetes-sigs/windows-testing

This repo is a collection of scripts, containers, and documentation needed to run Kubernetes test passes on clusters with Windows worker nodes. It is maintained by [sig-windows](https://github.com/kubernetes/community/tree/master/sig-windows).


## Running a e2e test pass

> This section is still a work-in-progress and will be changed as we continue to move in files from other repos.

Daily test passes are scheduled by Prow ([see: config](https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes-sigs/sig-windows/sig-windows-config.yaml)), and results are on [TestGrid](https://testgrid.k8s.io/sig-windows).

### Cluster Setup


### Running SIG-Windows tests

All of the SIG-Windows tests are included in the `e2e.test` binary. You need to set a few options to connect to the cluster, and use the right Windows images.

```bash
export KUBECONFIG=path/to/kubeconfig
curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-ws2019 -o repo_list
export KUBE_TEST_REPO_LIST=$(pwd)/repo_list

./e2e.test --provider=local --ginkgo.noColor --ginkgo.focus="\[sig-windows\]" --node-os-distro="windows"
```

### Running adapted Conformance tests

> TODO: copy & simplify steps from https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes-sigs/sig-windows/sig-windows-config.yaml


## Building Tests

### e2e.test

Make sure you have a working [Kubernetes development environment](https://github.com/kubernetes/community/blob/master/contributors/devel/development.md).
```bash
go get -d k8s.io/kubernetes
cd $GOPATH/src/k8s.io/kubernetes
./build/run.sh make WHAT=test/e2e/e2e.test
```
Once complete, the binary will be available at: `~/go/src/k8s.io/kubernetes/_output/dockerized/bin/linux/amd64/e2e.test`

If building on Mac or Windows, you can specify `KUBE_BUILD_PLATFORMS`.

For Windows
```bash
./build/run.sh make KUBE_BUILD_PLATFORMS=windows/amd64
```

For Mac
```bash
./build/run.sh make KUBE_BUILD_PLATFORMS=darwin/amd64
```

Your binaries will be available at `~/go/src/k8s.io/kubernetes/_output/dockerized/bin/linux/amd64/e2e.test` where `linux/amd64/` is replaced by `KUBE_BUILD_PLATFORMS` if you are building on Mac or Windows.

### Images

[images/](images/README.md) - has all of the container images used in e2e test passes and the scripts to build them. They are replacement Windows containers for those in [kubernetes/test/images](https://github.com/kubernetes/kubernetes/tree/master/test/images)
