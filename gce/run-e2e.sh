#!/bin/bash

set -o nounset
set -o pipefail
set -o xtrace

# When running in prow, the working directory is the root of the test-infra
# repository.

# In some test scenarios, cluster may not be stable at the beginning,  wait
# until it is stable, # i.e. both the control plane and nodes are up / running
# reliably before start running the tests.
sleep ${INIT_TIMEOUT:-1s}

# Taint the Linux nodes to prevent the test workloads from landing on them.
# TODO: remove this once the issue is resolved:
# https://github.com/kubernetes/kubernetes/issues/69892
LINUX_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=linux -o name)
LINUX_NODE_COUNT=$(echo ${LINUX_NODES} | wc -w)
if [[ ! -v NO_LINUX_POOL_TAINT ]]; then
  for node in $LINUX_NODES; do
    kubectl taint node $node node-under-test=false:NoSchedule
  done
fi

# Untaint the windows nodes to allow test workloads without tolerations to be
# scheduled onto them.
WINDOWS_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=windows -o name)
for node in $WINDOWS_NODES; do
  kubectl taint node $node node.kubernetes.io/os:NoSchedule-
done

# Run prepull if PREPULL_YAML is set to a value.
if [[ -v PREPULL_YAML && ! -z "$PREPULL_YAML" ]]; then
  # Pre-pull all the test images. The images are currently hard-coded.
  # Eventually, we should get the list directly from
  # https://github.com/kubernetes/kubernetes/blob/master/test/utils/image/manifest.go.
  PREPULL_FILE=${PREPULL_YAML:-prepull-head.yaml}
  SCRIPT_ROOT=$(cd `dirname $0` && pwd)
  kubectl create -f ${SCRIPT_ROOT}/${PREPULL_FILE}
  # Wait a while for the test images to be pulled onto the nodes. In empirical
  # testing it could take up to 30 minutes to finish pulling all the test
  # containers on a node.
  timeout ${PREPULL_TIMEOUT:-30m} kubectl wait --for=condition=ready pod -l prepull-test-images=e2e --timeout -1s
  # Check the status of the pods.
  kubectl get pods -o wide
  kubectl describe pods
  # Delete the pods anyway since pre-pulling is best-effort
  kubectl delete -f ${SCRIPT_ROOT}/${PREPULL_FILE}
  # Wait a few more minutes for the pod to be cleaned up.
  timeout 3m kubectl wait --for=delete pod -l prepull-test-images=e2e --timeout -1s
fi

# When using customized test command (which we are now), report-dir is not set
# by default, so set it here.
# The test framework will not proceed to run tests unless all nodes are ready
# AND schedulable. Allow not-ready nodes since we make Linux nodes
# unschedulable.
./hack/ginkgo-e2e.sh $@ --report-dir=${ARTIFACTS} --allowed-not-ready-nodes=${LINUX_NODE_COUNT} --disable-log-dump
