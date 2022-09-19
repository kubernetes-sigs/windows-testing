For upstream e2e testing, we use aks-engine (https://github.com/Azure/aks-engine) released versions. However, there may be
necessary to build custom versions of aks-engine to work around some issues (i.e. removed flags) that occur because of released
versions of aks-engine don't support latest k8s built from master, thus cluster deployment might fail.

We download the aks-engine binary for the test runs from the following URL: https://aka.ms/aks-engine/aks-engine-k8s-e2e.tar.gz
This is actually a short URL that points to the download link for aks-engine: either released versions here https://github.com/Azure/aks-engine/releases
or custom versions hosted in Azure Storage. It is a convenient way to ensure updates in aks-engine versions as fast as possible
with minimum test disruption (test job config won't need updating).

This file is intended to be a log of all the custom builds of aks-engine that we use for upstream tests at any given time, and the
commits/branch that are used for that build.

08/22/2019

- using aks-engine release version: 0.39.1 (https://github.com/Azure/aks-engine/releases/download/v0.39.1/aks-engine-v0.39.1-linux-amd64.tar.gz)

06/28/2019

- using aks-engine built from: https://github.com/adelina-t/aks-engine/tree/fix_labels_bug
- reason: https://github.com/Azure/aks-engine/issues/1546



