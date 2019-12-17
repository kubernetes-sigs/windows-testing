#!/bin/bash

set -o nounset
set -o pipefail
set -o xtrace

# When running in prow, the working directory is the root of the test-infra
# repository.

# Taint the Linux nodes to prevent the test workloads from landing on them.
# TODO: remove this once the issue is resolved:
# https://github.com/kubernetes/kubernetes/issues/69892
LINUX_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=linux -o name)
LINUX_NODE_COUNT=$(echo ${LINUX_NODES} | wc -w)
for node in $LINUX_NODES; do
  kubectl taint node $node node-under-test=false:NoSchedule
done

# Untaint the windows nodes to allow test workloads without tolerations to be
# scheduled onto them.
WINDOWS_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=windows -o name)
for node in $WINDOWS_NODES; do
  kubectl taint node $node node.kubernetes.io/os:NoSchedule-
done

# Pre-pull all the test images. The images are currently hard-coded.
# Eventually, we should get the list directly from
# https://github.com/kubernetes-sigs/windows-testing/blob/master/images/PullImages.ps1
SCRIPT_ROOT=$(cd `dirname $0` && pwd)
kubectl create -f ${SCRIPT_ROOT}/prepull.yaml
# Wait 10 minutes for the test images to be pulled onto the nodes.
sleep ${PREPULL_TIMEOUT:-15m}
# Check the status of the pods.
kubectl get pods -o wide
# Delete the pods anyway since pre-pulling is best-effort
kubectl delete -f ${SCRIPT_ROOT}/prepull.yaml
# Wait a few more minutes for the pod to be cleaned up.
sleep 3m

# Download and set the list of test image repositories to use.
curl \
  https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list \
  -o ${WORKSPACE}/repo-list.yaml
export KUBE_TEST_REPO_LIST=${WORKSPACE}/repo-list.yaml

# When using customized test command (which we are now), report-dir is not set
# by default, so set it here.
# The test framework will not proceed to run tests unless all nodes are ready
# AND schedulable. Allow not-ready nodes since we make Linux nodes
# unschedulable.
# Do not set --disable-log-dump because upstream cannot handle dumping logs
# from windows nodes yet.
./hack/ginkgo-e2e.sh $@ --report-dir=${ARTIFACTS} --allowed-not-ready-nodes=${LINUX_NODE_COUNT}
