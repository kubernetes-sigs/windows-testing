#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

main() {
    ensure_envs
    apply_workload_configuraiton
    wait_for_nodes
    if [[ "${HYPERV}" == "true" ]]; then apply_hyperv_configuration; fi
    run_e2e_test
}

ensure_envs() {
    : "${KUBECONFIG:?Environment variable empty or not defined.}"
    : "${CAPZ_DIR:?Environment variable empty or not defined.}"
    : "${ARTIFACTS:?Environment variable empty or not defined.}"
    : "${CI_VERSION:?Environment variable empty or not defined.}"
    : "${WINDOWS_WORKER_MACHINE_COUNT:?Environment variable empty or not defined.}"
    : "${CONTROL_PLANE_MACHINE_COUNT:?Environment variable empty or not defined.}"
}

wait_for_nodes() {
    log "Waiting for ${CONTROL_PLANE_MACHINE_COUNT} control plane machine(s) and ${WINDOWS_WORKER_MACHINE_COUNT} windows machine(s) to become Ready"
    kubectl get nodes -o wide
    kubectl get pods -A -o wide
    
    # Ensure that all nodes are registered with the API server before checking for readiness
    local total_nodes="$((CONTROL_PLANE_MACHINE_COUNT + WINDOWS_WORKER_MACHINE_COUNT))"
    while [[ $(kubectl get nodes -ojson | jq '.items | length') -ne "${total_nodes}" ]]; do
        sleep 10
    done

    kubectl get nodes -o wide
    kubectl get pods -A -o wide

    log "waiting for nodes to be Ready"
    kubectl wait --for=condition=Ready node --all --timeout=20m
    log "Nodes Ready"
    kubectl get nodes -owide
}

apply_workload_configuraiton(){
    # Only patch up kube-proxy if $WINDOWS_KPNG is unset
    if [[ -z "$KPNG" ]]; then
        # A patch is needed to tell kube-proxy to use CI binaries.  This could go away once we have build scripts for kubeproxy HostProcess image.
        kubectl apply -f "${CAPZ_DIR}"/templates/test/ci/patches/windows-kubeproxy-ci.yaml
        kubectl rollout restart ds -n kube-system kube-proxy-windows
    fi

    # apply additional helper manifests (logger etc)
    kubectl apply -f "${CAPZ_DIR}"/templates/addons/windows/containerd-logging/containerd-logger.yaml
    kubectl apply -f "${CAPZ_DIR}"/templates/addons/windows/csi-proxy/csi-proxy.yaml
    kubectl apply -f "${CAPZ_DIR}"/templates/addons/metrics-server/metrics-server.yaml
}

apply_hyperv_configuration(){
    set -x
    log "applying contirguration for testing hyperv isolated containers"

    log "installing hyperv runtime class"
    kubectl apply -f "${SCRIPT_ROOT}/../helpers/hyper-v-mutating-webhook/hyperv-runtimeclass.yaml"

    # ensure cert-manager and webhook pods land on Linux nodes
    log "untainting control-plane nodes"
    mapfile -t cp_nodes < <(kubectl get nodes | grep control-plane | awk '{print $1}')
    kubectl taint nodes "${cp_nodes[@]}" node-role.kubernetes.io/control-plane:NoSchedule- || true

    log "tainting windows nodes"
    mapfile -t windows_nodes < <(kubectl get nodes -o wide | grep Windows | awk '{print $1}')
    kubectl taint nodes "${windows_nodes[@]}" os=windows:NoSchedule

    log "installing cer-manager"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml

    log "wait for cert-manager pods to start"
    timeout 5m kubectl wait --for=condition=ready pod --all -n cert-manager --timeout -1s

    log "installing admission controller webhook"
    kubectl apply -f "${SCRIPT_ROOT}/../helpers/hyper-v-mutating-webhook/deployment.yaml"

    log "wait for webhook pods to go start"
    timeout 5m kubectl wait --for=condition=ready pod --all -n hyperv-webhook-system  --timeout -1s

    log "untainting Windows agent nodes"
    kubectl taint nodes "${windows_nodes[@]}" os=windows:NoSchedule-

    log "taining master nodes again"
    kubectl taint nodes "${cp_nodes[@]}" node-role.kubernetes.io/control-plane:NoSchedule || true

    log "done configuring testing for hyperv isolated containers"
    set +x
}

run_e2e_test() {
    export SKIP_TEST="${SKIP_TEST:-"false"}"
    ret=0
    if [[ ! "$SKIP_TEST" == "true" ]]; then
        ## get and run e2e test 
        ## https://github.com/kubernetes/sig-release/blob/master/release-engineering/artifacts.md#content-of-kubernetes-test-system-archtargz-on-example-of-kubernetes-test-linux-amd64targz-directories-removed-from-list
        curl -L -o /tmp/kubernetes-test-linux-amd64.tar.gz https://storage.googleapis.com/k8s-release-dev/ci/"${CI_VERSION}"/kubernetes-test-linux-amd64.tar.gz
        tar -xzvf /tmp/kubernetes-test-linux-amd64.tar.gz

        if [[ ! "${RUN_SERIAL_TESTS:-}" == "true" ]]; then
            export GINKGO_FOCUS=${GINKGO_FOCUS:-"\[Conformance\]|\[NodeConformance\]|\[sig-windows\]|\[sig-apps\].CronJob|\[sig-api-machinery\].ResourceQuota|\[sig-scheduling\].SchedulerPreemption"}
            export GINKGO_SKIP=${GINKGO_SKIP:-"\[LinuxOnly\]|\[Serial\]|\[Slow\]|\[Excluded:WindowsDocker\]|Networking.Granular.Checks(.*)node-pod.communication|Guestbook.application.should.create.and.stop.a.working.application|device.plugin.for.Windows|Container.Lifecycle.Hook.when.create.a.pod.with.lifecycle.hook.should.execute(.*)http.hook.properly|\[sig-api-machinery\].Garbage.collector"}
            export GINKGO_NODES="${GINKGO_NODES:-"4"}"
        else
            export GINKGO_FOCUS=${GINKGO_FOCUS:-"(\[sig-windows\]|\[sig-scheduling\].SchedulerPreemption|\[sig-autoscaling\].\[Feature:HPA\]|\[sig-apps\].CronJob).*(\[Serial\]|\[Slow\])|(\[Serial\]|\[Slow\]).*(\[Conformance\]|\[NodeConformance\])|\[sig-api-machinery\].Garbage.collector"}
            export GINKGO_SKIP=${GINKGO_SKIP:-"\[LinuxOnly\]|\[Excluded:WindowsDocker\]|device.plugin.for.Windows"}
            export GINKGO_NODES="${GINKGO_NODES:-"1"}"
        fi

        log "starting to run e2e tests"
        set -x
        set +e
        "$PWD"/kubernetes/test/bin/ginkgo --nodes="${GINKGO_NODES}" "$PWD"/kubernetes/test/bin/e2e.test -- \
            --provider=skeleton \
            --ginkgo.noColor \
            --ginkgo.focus="$GINKGO_FOCUS" \
            --ginkgo.skip="$GINKGO_SKIP" \
            --node-os-distro="windows" \
            --disable-log-dump \
            --ginkgo.progress=true \
            --ginkgo.slowSpecThreshold=120.0 \
            --ginkgo.flakeAttempts=0 \
            --ginkgo.trace=true \
            --ginkgo.timeout=24h \
            --num-nodes="$WINDOWS_WORKER_MACHINE_COUNT" \
            --ginkgo.v=true \
            --dump-logs-on-failure=true \
            --report-dir="${ARTIFACTS}" \
            --prepull-images=true \
            --v=5 "${ADDITIONAL_E2E_ARGS[@]}"
        ret=$?
        set +x
        set -e
        log "e2e tests complete"
    fi
    return $ret
}

log() {
	local msg=$1
	echo "$(date -R): $msg"
}

main
