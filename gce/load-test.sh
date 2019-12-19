#!/bin/bash

set -o nounset
set -o pipefail
set -o xtrace

# When running in prow, the working directory is the root of the test-infra
# repository.

# Taint the Linux nodes to prevent the test workloads from landing on them.
# TODO: remove this once the issue is resolved:
# https://github.com/kubernetes/kubernetes/issues/69892
LINUX_NODES=$(kubectl get nodes -l kubernetes.io/os=linux -o name)
LINUX_NODE_COUNT=$(echo ${LINUX_NODES} | wc -w)
for node in $LINUX_NODES; do
  kubectl taint node $node node-under-test=false:NoSchedule
done

# Untaint the windows nodes to allow test workloads without tolerations to be
# scheduled onto them.
WINDOWS_NODES=$(kubectl get nodes -l kubernetes.io/os=windows -o name)
for node in $WINDOWS_NODES; do
  kubectl taint node $node node.kubernetes.io/os:NoSchedule-
done

# Pre-pull all the test images.
SCRIPT_ROOT=$(cd `dirname $0` && pwd)
kubectl create -f ${SCRIPT_ROOT}/loadtest-prepull.yaml
# Wait for the test images to be pulled onto the nodes.
sleep ${PREPULL_TIMEOUT:-3m}
# Check the status of the pods.
kubectl get pods -o wide
# Delete the pods anyway since pre-pulling is best-effort
kubectl delete -f ${SCRIPT_ROOT}/loadtest-prepull.yaml
# Wait a few more minutes for the pod to be cleaned up.
sleep 1m

$GOPATH/src/k8s.io/perf-tests/run-e2e.sh $@
