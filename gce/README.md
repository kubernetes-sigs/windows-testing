# Windows Kubernetes testing on Google Compute Engine

This directory contains scripts and data used for running Windows Kubernetes
tests on GCE.

Continuous test results can be seen on the
[sig-windows](https://testgrid.k8s.io/sig-windows#gce-windows-master) and
[google-windows](https://testgrid.k8s.io/google-windows) testgrids. The
configuration for those tests lives in
[test-infra](https://github.com/kubernetes/test-infra/blob/master/config/jobs/kubernetes/sig-windows/windows-gce.yaml).

This code previously lived at
[gce-k8s-windows-testing](https://github.com/yujuhong/gce-k8s-windows-testing).

## Bringing up a Windows Kubernetes cluster on Google Compute Engine

See the
[README](https://github.com/kubernetes/kubernetes/blob/master/cluster/gce/windows/README-GCE-Windows-kube-up.md)
in the main kubernetes repository.
