# Windows Test Images

Test images in this directory are no longer maintained. https://github.com/kubernetes/kubernetes/tree/master/test/images contains the most up-to-date test images.

## Image Repository List

Currently, for Windows jobs, we override the test image registry by defining the environment variable `KUBE_TEST_REPO_LIST`, which points to a YAML file before running the test suite. The YAML schema is defined in [test/utils/image/manifest.go](https://github.com/kubernetes/kubernetes/blob/b86b78917cbff4bbc09f39fa6cc10d20afa15b1e/test/utils/image/manifest.go#L31-L47). The following table describes which image repository list should be used for which Kubernetes branch/Windows OS version:

| Kubernetes Branch | Windows OS Version | Image Repository List                                                                                  |
|-------------------|--------------------|--------------------------------------------------------------------------------------------------------|
| >= release-1.21 and <= release-1.24            | *                  | https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list |
| >= release-1.25        | WS 2022 or WS 2019    | https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-private-registry |
| >= release-1.25        | WS 2019              | none - can use the image-repo-list-private-registry or non for ws 2019  |

The private image repository doesn't have a way to promote images: https://github.com/kubernetes/k8s.io/pull/1929. We don't have a Windows Server 2022 image in the `gcr.io/authenticated-image-pulling` and use the `e2eprivate` dockerhub repository instead which allows sig-windows to update images for new Server versions.
