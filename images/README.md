# Windows Test Images

Test images in this directory are no longer maintained. https://github.com/kubernetes/kubernetes/tree/master/test/images contains the most up-to-date test images.

## Image Repository List

Currently, for Windows jobs, we override the test image registry by defining the environment variable `KUBE_TEST_REPO_LIST`, which points to a YAML file before running the test suite. The YAML schema is defined in [test/utils/image/manifest.go](https://github.com/kubernetes/kubernetes/blob/b86b78917cbff4bbc09f39fa6cc10d20afa15b1e/test/utils/image/manifest.go#L31-L47). The following table describes which image repository list should be used for which Kubernetes branch/Windows OS version:

| Kubernetes Branch | Windows OS Version | Image Repository List                                                                                  |
|-------------------|--------------------|--------------------------------------------------------------------------------------------------------|
| *                 | 2004               | https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-2004   |
| master            | *                  | https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-master |
| release-1.xx      | *                  | https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list        |
