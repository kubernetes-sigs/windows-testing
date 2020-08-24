#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set  +x

log() {
    local msg=$1
    echo "$(date -R): $msg"
}


export KUBECONFIG="$(find /home/*/.kube/config)"
export KUBECTL="kubectl --kubeconfig=${KUBECONFIG}"
export -f log

log "starting configure-hyperv-webhook extension"

# untaint master nodes (they were tainted by win-e2e-master-extension)
log "untainting master nodes"
master_node=$(${KUBECTL} get nodes | grep master | awk '{print $1}')
${KUBECTL} taint nodes "$master_node" node-role.kubernetes.io/master=:NoSchedule- || true

log "tainting Windows agent nodes"
agent_nodes=$(${KUBECTL} get nodes | grep agent | awk '{print $1}' | tr '\n' ' ')
${KUBECTL} taint nodes $agent_nodes os=windows:NoSchedule

log "installing runtime-class"
${KUBECTL} apply -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/2004-hyperv-runtimeclass.yaml

log "installing cert-manager"
${KUBECTL} apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.15.2/cert-manager.yaml

log "wait for cert-manager pods to start"
timeout 5m ${KUBECTL} wait --for=condition=ready pod --all -n cert-manager --timeout -1s

log "installing admission controller webhook"
${KUBECTL} apply -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/deployment.yaml

log "wait for webhook pods to go start"
timeout 5m ${KUBECTL} wait --for=condition=ready pod --all -n hyper-v-mutator-system --timeout -1s

log "taining master nodes again"
${KUBECTL} taint nodes "$master_node" node-role.kubernetes.io/master=:NoSchedule || true

log "exiting configure-hyperv-webhook extension"