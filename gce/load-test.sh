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

# Pre-pull all the test images.
SCRIPT_ROOT=$(cd `dirname $0` && pwd)
PREPULL_YAML=${PREPULL_YAML:-loadtest-prepull.yaml}
kubectl create -f ${SCRIPT_ROOT}/${PREPULL_YAML}
# Wait a while for the test images to be pulled onto the nodes.
timeout ${PREPULL_TIMEOUT:-10m} kubectl wait --for=condition=ready pod -l prepull-test-images=loadtest --timeout -1s
# Check the status of the pods.
kubectl get pods -o wide
kubectl describe pods
# Delete the pods anyway since pre-pulling is best-effort
kubectl delete -f ${SCRIPT_ROOT}/${PREPULL_YAML}
# Wait a few more minutes for the pod to be cleaned up.
timeout 3m kubectl wait --for=delete pod -l prepull-test-images=loadtest --timeout -1s

$GOPATH/src/k8s.io/perf-tests/run-e2e.sh $@
