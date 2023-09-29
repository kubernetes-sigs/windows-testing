#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -o functrace

SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_ROOT=$(dirname "${SCRIPT_PATH}")
export CAPZ_DIR="${CAPZ_DIR:-"${GOPATH}/src/sigs.k8s.io/cluster-api-provider-azure"}"
: "${CAPZ_DIR:?Environment variable empty or not defined.}"
if [[ ! -d $CAPZ_DIR ]]; then
    echo "Must have capz repo present"
fi
export AZURE_CLOUD_PROVIDER_ROOT="${AZURE_CLOUD_PROVIDER_ROOT:-"${GOPATH}/src/sigs.k8s.io/cloud-provider-azure"}"
: "${AZURE_CLOUD_PROVIDER_ROOT:?Environment variable empty or not defined.}"
if [[ ! -d $AZURE_CLOUD_PROVIDER_ROOT ]]; then
    echo "Must have azure cloud provider repo present"
fi

main() {
    # defaults
    export KUBERNETES_VERSION="${KUBERNETES_VERSION:-"latest"}"
    export CONTROL_PLANE_MACHINE_COUNT="${AZURE_CONTROL_PLANE_MACHINE_COUNT:-"1"}"
    export WINDOWS_WORKER_MACHINE_COUNT="${WINDOWS_WORKER_MACHINE_COUNT:-"2"}"
    export WINDOWS_SERVER_VERSION="${WINDOWS_SERVER_VERSION:-"windows-2019"}"
    export WINDOWS_CONTAINERD_URL="${WINDOWS_CONTAINERD_URL:-"https://github.com/containerd/containerd/releases/download/v1.7.0/containerd-1.7.0-windows-amd64.tar.gz"}"
    export GMSA="${GMSA:-""}" 
    export HYPERV="${HYPERV:-""}"
    export KPNG="${WINDOWS_KPNG:-""}"

    # other config
    export ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
    export CLUSTER_NAME="${CLUSTER_NAME:-capz-conf-$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 6 ; echo '')}"
    export CAPI_EXTENSION_SOURCE="${CAPI_EXTENSION_SOURCE:-"https://github.com/Azure/azure-capi-cli-extension/releases/download/v0.1.5/capi-0.1.5-py2.py3-none-any.whl"}"
    export IMAGE_SKU="${IMAGE_SKU:-"${WINDOWS_SERVER_VERSION:=windows-2019}-containerd-gen1"}"
    
    # CI is an environment variable set by a prow job: https://github.com/kubernetes/test-infra/blob/master/prow/jobs.md#job-environment-variables
    export CI="${CI:-""}"

    set_azure_envs
    set_ci_version
    IS_PRESUBMIT="$(capz::util::should_build_kubernetes)"
    if [[ "${IS_PRESUBMIT}" == "true" ]]; then
        "${CAPZ_DIR}/scripts/ci-build-kubernetes.sh";
        trap run_capz_e2e_cleanup EXIT # reset the EXIT trap since ci-build-kubernetes.sh also sets it.
    fi
    if [[ "${GMSA}" == "true" ]]; then create_gmsa_domain; fi

    create_cluster
    apply_cloud_provider_azure
    apply_workload_configuraiton
    wait_for_nodes
    if [[ "${HYPERV}" == "true" ]]; then apply_hyperv_configuration; fi
    run_e2e_test
}

create_gmsa_domain(){
    log "running gmsa setup"

    export CI_RG="${CI_RG:-capz-ci}"
    export GMSA_ID="${RANDOM}"
    export GMSA_NODE_RG="gmsa-dc-${GMSA_ID}"
    export GMSA_KEYVAULT_URL="https://${GMSA_KEYVAULT:-$CI_RG-gmsa}.vault.azure.net"

    log "setting up domain vm in $GMSA_NODE_RG with keyvault $CI_RG-gmsa"
    "${SCRIPT_ROOT}/gmsa/ci-gmsa.sh"

    # export the ip Address so it can be used in e2e test
    vmname="dc-${GMSA_ID}"
    vmip=$(az vm list-ip-addresses -n ${vmname} -g $GMSA_NODE_RG --query "[?virtualMachine.name=='$vmname'].virtualMachine.network.privateIpAddresses" -o tsv)
    export GMSA_DNS_IP=$vmip
}

run_capz_e2e_cleanup() {
    log "cleaning up"

    capz::ci-build-azure-ccm::cleanup || true

    if [[ "$(capz::util::should_build_kubernetes)" == "true" ]]; then
        capz::ci-build-kubernetes::cleanup || true
    fi

    kubectl get nodes -owide

    # currently KUBECONFIG is set to the workload cluster so reset to the management cluster
    unset KUBECONFIG

    if [[ -z "${SKIP_LOG_COLLECTION:-}" ]]; then
        log "collecting logs"
        pushd "${CAPZ_DIR}"

        # there is an issue in ci with the go client conflicting with the kubectl client failing to get logs for 
        # control plane node.  This is a mitigation being tried 
        rm -rf "$HOME/.kube/cache/"
        # don't stop on errors here, so we always cleanup
        go run -tags e2e "${CAPZ_DIR}/test/logger.go" --name "${CLUSTER_NAME}" --namespace default --artifacts-folder "${ARTIFACTS}" || true
        popd

        "${CAPZ_DIR}/hack/log/redact.sh" || true
    else
        log "skipping log collection"
    fi

    if [[ -z "${SKIP_CLEANUP:-}" ]]; then
        log "deleting cluster"
        az group delete --name "$CLUSTER_NAME" --no-wait -y --force-deletion-types=Microsoft.Compute/virtualMachines --force-deletion-types=Microsoft.Compute/virtualMachineScaleSets || true

        # clean up GMSA NODE RG
        if [[ -n ${GMSA:-} ]]; then
            echo "Cleaning up gMSA resources $GMSA_NODE_RG with keyvault $GMSA_KEYVAULT_URL"
            az keyvault secret list --vault-name "${GMSA_KEYVAULT:-$CI_RG-gmsa}" --query "[? contains(name, '${GMSA_ID}')].name" -o tsv | while read -r secret ; do
                az keyvault secret delete -n "$secret" --vault-name "${GMSA_KEYVAULT:-$CI_RG-gmsa}"
            done

            az group delete --name "$GMSA_NODE_RG" --no-wait -y --force-deletion-types=Microsoft.Compute/virtualMachines --force-deletion-types=Microsoft.Compute/virtualMachineScaleSets || true
        fi
    else
        log "skipping clean up"
    fi
}

create_cluster(){
    export SKIP_CREATE="${SKIP_CREATE:-"false"}"
    if [[ ! "$SKIP_CREATE" == "true" ]]; then
        # create cluster
        log "starting to create cluster"
        az extension add -y --upgrade --source "$CAPI_EXTENSION_SOURCE" || true

        # select correct template
        template="$SCRIPT_ROOT"/templates/windows-ci.yaml
        if [[ "${IS_PRESUBMIT}" == "true" ]]; then
            template="$SCRIPT_ROOT"/templates/windows-pr.yaml;
        fi
        if [[ "${GMSA}" == "true" ]]; then
            if [[ "${IS_PRESUBMIT}" == "true" ]]; then
                template="$SCRIPT_ROOT"/templates/gmsa-pr.yaml;
            else
                template="$SCRIPT_ROOT"/templates/gmsa-ci.yaml
            fi
        fi
        echo "Using $template"
        
        az capi create -mg "${CLUSTER_NAME}" -y -w -n "${CLUSTER_NAME}" -l "$AZURE_LOCATION" --template "$template" --tags creationTimestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        
        # copy generated template to logs
        mkdir -p "${ARTIFACTS}"/clusters/bootstrap
        cp "${CLUSTER_NAME}.yaml" "${ARTIFACTS}"/clusters/bootstrap || true
        log "cluster creation complete"
    fi

    # set the kube config to the workload cluster
    # the kubeconfig is dropped to the current folder but move it to a location that is well known to avoid issues if end up in wrong folder due to other scripts.
    if [[ "$PWD" != "$SCRIPT_ROOT" ]]; then
        mv "$PWD"/"${CLUSTER_NAME}".kubeconfig "$SCRIPT_ROOT"/"${CLUSTER_NAME}".kubeconfig
    fi
    export KUBECONFIG="$SCRIPT_ROOT"/"${CLUSTER_NAME}".kubeconfig
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

apply_cloud_provider_azure() {
    echo "KUBERNETES_VERSION = ${KUBERNETES_VERSION}"

    echo "Building cloud provider images"
    # shellcheck disable=SC1091
    "${CAPZ_DIR}/hack/ensure-acr-login.sh"
    # shellcheck disable=SC1091
    source "${CAPZ_DIR}/scripts/ci-build-azure-ccm.sh" || false
    trap run_capz_e2e_cleanup EXIT # reset the EXIT trap since ci-build-azure-ccm.sh also sets it.
    echo "Will use the ${IMAGE_REGISTRY}/${CCM_IMAGE_NAME}:${IMAGE_TAG_CCM} cloud-controller-manager image for external cloud-provider-cluster"
    echo "Will use the ${IMAGE_REGISTRY}/${CNM_IMAGE_NAME}:${IMAGE_TAG_CNM} cloud-node-manager image for external cloud-provider-azure cluster"

    CCM_IMG_ARGS=(--set cloudControllerManager.imageRepository="${IMAGE_REGISTRY}"
    --set cloudNodeManager.imageRepository="${IMAGE_REGISTRY}"
    --set cloudControllerManager.imageName="${CCM_IMAGE_NAME}"
    --set cloudNodeManager.imageName="${CNM_IMAGE_NAME}"
    --set-string cloudControllerManager.imageTag="${IMAGE_TAG_CCM}"
    --set-string cloudNodeManager.imageTag="${IMAGE_TAG_CNM}")

    echo "Installing cloud-provider-azure components via helm"
    helm upgrade cloud-provider-azure --install --repo https://raw.githubusercontent.com/kubernetes-sigs/cloud-provider-azure/master/helm/repo cloud-provider-azure "${CCM_IMG_ARGS[@]}"
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

        ADDITIONAL_E2E_ARGS=()
        if [[ "$CI" == "true" ]]; then
            # private image repository doesn't have a way to promote images: https://github.com/kubernetes/k8s.io/pull/1929
            # So we are using a custom repository for the test "Container Runtime blackbox test when running a container with a new image should be able to pull from private registry with secret [NodeConformance]"
            # Must also set label preset-windows-private-registry-cred: "true" on the job
            export KUBE_TEST_REPO_LIST="$SCRIPT_ROOT/../images/image-repo-list-private-registry"
            ADDITIONAL_E2E_ARGS+=("--docker-config-file=${DOCKER_CONFIG_FILE}")
        fi

        # K8s 1.24 and below use ginkgo v1 which has slighly different args
        ginkgo_v1="false"
        if [[ "${KUBERNETES_VERSION}" =~ 1.24 ]]; then
            ginkgo_v1="true"
        fi

        if [[ "${ginkgo_v1}" == "true" ]]; then
            ADDITIONAL_E2E_ARGS+=("--ginkgo.slowSpecThreshold=120.0")
        else
            ADDITIONAL_E2E_ARGS+=("--ginkgo.slow-spec-threshold=120s")
            ADDITIONAL_E2E_ARGS+=("--ginkgo.timeout=4h")
        fi

        log "starting to run e2e tests"
        set -x
        "$PWD"/kubernetes/test/bin/ginkgo --nodes="${GINKGO_NODES}" "$PWD"/kubernetes/test/bin/e2e.test -- \
            --provider=skeleton \
            --ginkgo.noColor \
            --ginkgo.focus="$GINKGO_FOCUS" \
            --ginkgo.skip="$GINKGO_SKIP" \
            --node-os-distro="windows" \
            --disable-log-dump \
            --ginkgo.progress=true \
            --ginkgo.flakeAttempts=0 \
            --ginkgo.trace=true \
            --num-nodes="$WINDOWS_WORKER_MACHINE_COUNT" \
            --ginkgo.v=true \
            --dump-logs-on-failure=true \
            --report-dir="${ARTIFACTS}" \
            --prepull-images=true \
            --v=5 "${ADDITIONAL_E2E_ARGS[@]}"
        set +x
        log "e2e tests complete"
    fi
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

    if [[ "${GMSA}" == "true" ]]; then
        log "Configuring workload cluster nodes for gmsa tests"
        # require kubeconfig to be pointed at management cluster 
        unset KUBECONFIG
        pushd  "$SCRIPT_ROOT"/gmsa/configuration
        go run --tags e2e configure.go --name "${CLUSTER_NAME}" --namespace default
        popd
        export KUBECONFIG="$SCRIPT_ROOT"/"${CLUSTER_NAME}".kubeconfig
    fi

}

set_azure_envs() {
    # shellcheck disable=SC1091
    source "${CAPZ_DIR}/hack/ensure-tags.sh"
    # shellcheck disable=SC1091
    source "${CAPZ_DIR}/hack/parse-prow-creds.sh"
    # shellcheck disable=SC1091
    source "${CAPZ_DIR}/hack/util.sh"
    # shellcheck disable=SC1091
    source "${CAPZ_DIR}/hack/ensure-azcli.sh"

    # Verify the required Environment Variables are present.
    capz::util::ensure_azure_envs

    # Generate SSH key.
    capz::util::generate_ssh_key

    export AZURE_LOCATION="${AZURE_LOCATION:-$(capz::util::get_random_region)}"

    if [[ "${CI:-}" == "true" ]]; then
        # we don't provide an ssh key in ci so it is created.  
        # the ssh code in the logger and gmsa configuration
        # can't find it via relative paths so 
        # give it the absolute path
        export AZURE_SSH_PUBLIC_KEY_FILE="${PWD}"/.sshkey.pub
    fi
}

log() {
	local msg=$1
	echo "$(date -R): $msg"
}

set_ci_version() {
    # select correct windows version for tests
    if [[ "$(capz::util::should_build_kubernetes)" == "true" ]]; then
        #todo - test this
        : "${REGISTRY:?Environment variable empty or not defined.}"
        "${CAPZ_DIR}"/hack/ensure-acr-login.sh

        export E2E_ARGS="-kubetest.use-pr-artifacts"
        export KUBE_BUILD_CONFORMANCE="y"
        # shellcheck disable=SC1091
        source "${CAPZ_DIR}/scripts/ci-build-kubernetes.sh"
    else
        if [[ "${KUBERNETES_VERSION:-}" =~ "latest" ]]; then
            CI_VERSION_URL="https://dl.k8s.io/ci/${KUBERNETES_VERSION}.txt"
        else
            CI_VERSION_URL="https://dl.k8s.io/ci/latest.txt"
        fi
        export CI_VERSION="${CI_VERSION:-$(curl -sSL "${CI_VERSION_URL}")}"
        export KUBERNETES_VERSION="${CI_VERSION}"

        log "Selected Kubernetes version:"
        log "$KUBERNETES_VERSION"
    fi
}

trap run_capz_e2e_cleanup EXIT
main
