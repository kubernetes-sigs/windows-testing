#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_ROOT=$(dirname "${BASH_SOURCE[0]}")
export CAPZ_DIR="${CAPZ_DIR:-"${GOPATH}/src/sigs.k8s.io/cluster-api-provider-azure"}"
: "${CAPZ_DIR:?Environment variable empty or not defined.}"
if [[ ! -d $CAPZ_DIR ]]; then
    echo "Must have capz repo present"
fi

main() {
    # defaults
    export KUBERNETES_VERSION="${KUBERNETES_VERSION:-"latest"}"
    export CONTROL_PLANE_MACHINE_COUNT="${AZURE_CONTROL_PLANE_MACHINE_COUNT:-"1"}"
    export WINDOWS_WORKER_MACHINE_COUNT="${WINDOWS_WORKER_MACHINE_COUNT:-"2"}"
    export WINDOWS_SERVER_VERSION="${WINDOWS_SERVER_VERSION:-"windows-2019"}"
    export WINDOWS_CONTAINERD_URL="${WINDOWS_CONTAINERD_URL:-"https://github.com/containerd/containerd/releases/download/v1.6.17/containerd-1.6.17-windows-amd64.tar.gz"}"
    export GMSA="${GMSA:-""}" 
    export KPNG="${WINDOWS_KPNG:-""}"

    # other config
    export ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
    export CLUSTER_NAME="${CLUSTER_NAME:-capz-conf-$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 6 ; echo '')}"
    export CAPI_EXTENSION_SOURCE="${CAPI_EXTENSION_SOURCE:-"https://github.com/Azure/azure-capi-cli-extension/releases/download/v0.1.3/capi-0.1.3-py2.py3-none-any.whl"}"
    export IMAGE_SKU="${IMAGE_SKU:-"${WINDOWS_SERVER_VERSION:=windows-2019}-containerd-gen1"}"
    
    # CI is an environment variable set by a prow job: https://github.com/kubernetes/test-infra/blob/master/prow/jobs.md#job-environment-variables
    export CI="${CI:-""}"

    set_azure_envs
    set_ci_version
    if [[ "${GMSA}" == "true" ]]; then create_gmsa_domain; fi

    create_cluster
    apply_workload_configuraiton
    wait_for_nodes
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

cleanup() {
    log "cleaning up"
    kubectl get nodes -owide

    # currently KUBECONFIG is set to the workload cluster so reset to the management cluster
    unset KUBECONFIG

    pushd "${CAPZ_DIR}"

    # there is an issue in ci with the go client conflicting with the kubectl client failing to get logs for 
    # control plane node.  This is a mitigation being tried 
    rm -rf "$HOME/.kube/cache/"
    # don't stop on errors here, so we always cleanup
    go run -tags e2e "${CAPZ_DIR}/test/logger.go" --name "${CLUSTER_NAME}" --namespace default --artifacts-folder "${ARTIFACTS}" || true
    popd
    
    "${CAPZ_DIR}/hack/log/redact.sh" || true
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
        template="$SCRIPT_ROOT"/templates/windows-base.yaml
        if [[ "${GMSA}" == "true" ]]; then
            template="$SCRIPT_ROOT"/templates/gmsa.yaml
        fi
        echo "Using $template"
        
        az capi create -mg "${CLUSTER_NAME}" -y -w -n "${CLUSTER_NAME}" -l "$AZURE_LOCATION" --template "$template" --tags creationTimestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        
        # copy generated template to logs
        mkdir -p "${ARTIFACTS}"/clusters/bootstrap
        cp "${CLUSTER_NAME}.yaml" "${ARTIFACTS}"/clusters/bootstrap || true
        log "cluster creation complete"
    fi

    # set the kube config to the workload cluster
    export KUBECONFIG="$PWD"/"${CLUSTER_NAME}".kubeconfig
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

run_e2e_test() {
    export SKIP_TEST="${SKIP_TEST:-"false"}"
    export INCLUDE_NPM_TESTS="${INCLUDE_NPM_TESTS:-"false"}"
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
            export KUBE_TEST_REPO_LIST="$PWD"/images/image-repo-list-private-registry
            ADDITIONAL_E2E_ARGS+=("--docker-config-file=${DOCKER_CONFIG_FILE}")
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
        set +x
        log "e2e tests complete"

        if [[ "$INCLUDE_NPM_TESTS" == "true" ]]; then
            run_npm_tests
            # write all results to npm-tests directory
            mkdir -p npm-tests
            cd npm-tests
            npm_e2e
            cd ..
        fi
    fi
}


npm_e2e () {
    log "setting up npm e2e test"

    ## disable Calico NetPol
    log "running helm uninstall on calico (this will remove the tigera-operator and prevent reconciling of the calico-node ClusterRole)..."
    helm uninstall calico -n tigera-operator
    kubectl delete ns tigera-operator
    log "disabling Calico NetworkPolicy functionality by removing NetPol permission from calico-node ClusterRole..."
    kubectl get clusterrole calico-node -o yaml > original-clusterrole.yaml
    cat original-clusterrole.yaml | perl -0777 -i.original -pe 's/- apiGroups:\n  - networking.k8s.io\n  resources:\n  - networkpolicies\n  verbs:\n  - watch\n  - list\n//' > new-clusterrole.yaml
    originalLineCount=`cat original-clusterrole.yaml | wc -l`
    newLineCount=`cat new-clusterrole.yaml | wc -l`
    if [ $originalLineCount != $(($newLineCount + 7)) ]; then
        # NOTE: this check will only work the first time this script is run, since the original-clusterrole.yaml will be modified
        log "ERROR: unable to run NPM e2e. unexpected line count difference between original and new calico-node clusterrole. original: $originalLineCount, new: $newLineCount"
        return 1
    fi
    kubectl rollout restart ds -n calico-system calico-node-windows

    ## disable scheduling for all but one node for NPM tests, since intra-node connectivity is broken after disabling Calico NetPol
    kubectl get node -o wide | grep "Windows Server 2022 Datacenter" | awk '{print $1}' | tail -n +2 | xargs kubectl cordon

    # sleep for some time to let Calico CNI restart
    sleep 3m

    ## install Azure NPM
    log "installing Azure NPM..."
    # FIXME temporary URL
    npmURL=https://raw.githubusercontent.com/Azure/azure-container-networking/5712887dfbb46d04530f869269a9e24e4897a1a0/npm/examples/windows/azure-npm-capz.yaml
    kubectl apply -f $npmURL
    # FIXME temporary command (in future, can update image in final URL)
    kubectl set image -n kube-system ds azure-npm-win azure-npm=acnpublic.azurecr.io/azure-npm:capz-02-06-calico-pr # capz-02-02-no-base-acls # capz-02-03-no-base-pri900

    ## install long-running pod
    log "creating long-runner pod to ensure there's an endpoint for verifying VFP tags..."
    kubectl create ns npm-e2e-longrunner
    # FIXME temporary URL
    kubectl apply -f https://raw.githubusercontent.com/Azure/azure-container-networking/5712887dfbb46d04530f869269a9e24e4897a1a0/npm/examples/windows/long-running-pod-for-capz.yaml

    # verify VFP tags after NPM boots up
    # seems like the initial NPM Pods are always deleted and new ones are created (within the first minute of being applied it seems)
    # sleep for some time to avoid running kubectl wait on pods that get deleted
    log "waiting for NPM and long-runner to start running..."
    sleep 3m
    kubectl wait --for=condition=Ready pod -l k8s-app=azure-npm -n kube-system --timeout=15m
    kubectl wait --for=condition=Ready pod -l app=long-runner -n npm-e2e-longrunner --timeout=15m
    log "sleeping 8m for NPM to bootup, then verifying VFP tags after bootup..."
    sleep 8m
    verify_vfp_tags_using_npm

    ## NPM cyclonus
    run_npm_cyclonus
    log "sleeping 3m to allow VFP to update tags after cyclonus..."
    sleep 3m
    log "verifying VFP tags after cyclonus..."
    verify_vfp_tags_using_npm

    ## NPM conformance
    run_npm_conformance
    log "sleeping 3m to allow VFP to update tags after conformance..."
    sleep 3m
    log "verifying VFP tags after conformance..."
    verify_vfp_tags_using_npm
}

verify_vfp_tags_using_npm () {
    log "verifying VFP tags are equal to HNS SetPolicies..."
    npmNode=`kubectl get node -owide | grep "Windows Server 2022 Datacenter" | grep -v SchedulingDisabled | awk '{print $1}' | tail -n 1` || true
    if [[ -z $npmNode ]]; then
        log "ERROR: unable to find uncordoned node for NPM"
        return 1
    fi
    npmPod=`kubectl get pod -n kube-system -o wide | grep azure-npm-win | grep $npmNode | grep Running | awk '{print $1}'` || true
    if [[ -z "$npmPod" ]]; then
        log "ERROR: unable to find running azure-npm-win pod on node $npmNode"
        kubectl get pod -n kube-system -o wide
        return 1
    fi

    onNodeIPs=() ; for ip in `kubectl get pod -owide -A  | grep $npmNode | grep -oP "\d+\.\d+\.\d+\.\d+" | sort | uniq`; do onNodeIPs+=($ip); done
    matchString="" ; for ip in ${onNodeIPs[@]}; do matchString+=" \"${ip}\""; done
    matchString=`echo $matchString | tr ' ' ','`
    log "using matchString: $matchString"
    ipsetCount=`kubectl exec -n kube-system $npmPod -- powershell.exe "(Get-HNSNetwork | ? Name -Like Calico).Policies | convertto-json  > setpols.txt ; (type .\setpols.txt | select-string '\"PolicyType\":  \"IPSET\"').count" | tr -d '\r'`
    log "HNS IPSET count: $ipsetCount"
    kubectl exec -n kube-system $npmPod -- powershell.exe 'echo "attempting to delete previous results if they exist" ; Remove-Item -path vfptags -recurse ; mkdir vfptags'
    kubectl exec -n kube-system $npmPod -- powershell.exe '$endpoints = (Get-HnsEndpoint | ? IPAddress -In '"$matchString"').Id ; foreach ($port in $endpoints) { vfpctrl /port $port /list-tag > vfptags\$port.txt ; (type vfptags\$port.txt | select-string -context 2 "TAG :").count }' > vfp-tag-counts.txt

    hadEndpoints=false
    hadFailure=false
    for count in `cat vfp-tag-counts.txt | xargs -n 1 echo`; do
        hadEndpoints=true
        count=`echo $count | tr -d '\r'`
        log "VFP tag count: $count"
        if [[ $count != $ipsetCount ]]; then
            log "WARNING: VFP tag count $count does not match HNS IPSET count $ipsetCount"
            hadFailure=true
        fi
    done
    if [[ $hadEndpoints == false ]]; then
        log "WARNING: VFP tags not validated for NPM since no endpoints found on node $npmNode"
    fi
    if [[ $hadFailure == true ]]; then
        log "ERROR: VFP tags are inconsistent with HNS SetPolicies"
        capture_npm_hns_state
        return 1
    fi
}

# results in a file called npm-hns-state.zip
capture_npm_hns_state () {
    log "capturing NPM HNS state..."
    kubectl get pod -owide -A
    test -d npm-hns-state/ && rm -rf npm-hns-state/ || true
    mkdir npm-hns-state
    cd npm-hns-state
    curl -LO https://raw.githubusercontent.com/Azure/azure-container-networking/master/debug/windows/npm/win-debug.sh
    chmod u+x ./win-debug.sh
    curl -LO https://raw.githubusercontent.com/Azure/azure-container-networking/master/debug/windows/npm/pod_exec.ps1
    ./win-debug.sh
    cd ..
    zip -9qr npm-hns-state.zip npm-hns-state
    # to unzip:
    # unzip npm-hns-state.zip -d npm-hns-state
}

# currently takes ~3 hours to run
# e.g. 19:37:05 to 22:32:44 and 19:16:18 to 22:29:13
run_npm_conformance () {
    ## install NPM e2e binary
    log "ensuring NPM e2e binary is installed"
    rc=0; test -f npm-e2e.test || rc=$?
    if [[ $rc == 0 ]]; then
        log "NPM e2e binary found, skipping install"
    else
        log "NPM e2e binary not found, installing..."
        test -d npm-kubernetes/ && rm -rf npm-kubernetes/ || true
        mkdir npm-kubernetes
        cd npm-kubernetes
        # NOTE: if this is not downloaded every run, then probably need to sleep before the VFP tag verification
        git clone https://github.com/huntergregory/kubernetes.git --depth=1 --branch=quit-on-failure
        cd kubernetes
        make WHAT=test/e2e/e2e.test
        cd ../..
        mv npm-kubernetes/kubernetes/_output/local/bin/linux/amd64/e2e.test ./npm-e2e.test
        rm -rf npm-kubernetes/
    fi

    log "beginning npm conformance test..."

    toRun="NetworkPolicy"

    nomatch1="should enforce policy based on PodSelector or NamespaceSelector"
    nomatch2="should enforce policy based on NamespaceSelector with MatchExpressions using default ns label"
    nomatch3="should enforce policy based on PodSelector and NamespaceSelector"
    nomatch4="should enforce policy based on Multiple PodSelectors and NamespaceSelectors"
    cidrExcept1="should ensure an IP overlapping both IPBlock.CIDR and IPBlock.Except is allowed"
    cidrExcept2="should enforce except clause while egress access to server in CIDR block"
    namedPorts="named port"
    wrongK8sVersion="Netpol API"
    toSkip="\[LinuxOnly\]|$nomatch1|$nomatch2|$nomatch3|$nomatch4|$cidrExcept1|$cidrExcept2|$namedPorts|$wrongK8sVersion|SCTP"

    KUBERNETES_SERVICE_PORT=443 ./npm-e2e.test \
        --provider=skeleton \
        --ginkgo.noColor \
        --ginkgo.focus="$toRun" \
        --ginkgo.skip="$toSkip" \
        --allowed-not-ready-nodes=1 \
        --node-os-distro="windows" \
        --disable-log-dump \
        --ginkgo.progress=true \
        --ginkgo.slowSpecThreshold=120.0 \
        --ginkgo.flakeAttempts=0 \
        --ginkgo.trace=true \
        --ginkgo.v=true \
        --dump-logs-on-failure=true \
        --report-dir="${ARTIFACTS}" \
        --prepull-images=true \
        --v=5 "${ADDITIONAL_E2E_ARGS[@]}" | tee npm-e2e.log || true

    # grep "FAIL: unable to initialize resources: after 10 tries, 2 HTTP servers are not ready

    log "finished npm conformance test"
    ## report if there's a failure
    rc=0; cat npm-e2e.log | grep '"failed":1' > /dev/null 2>&1 || rc=$?
    if [ $rc -eq 0 ]; then
        log "ERROR: found failure in npm e2e test log"
        capture_npm_hns_state
        return 1
    fi
}

# currently takes ~3.5 hours to run
# e.g. 20:49:05 to 00:21:12
run_npm_cyclonus () {
    ## install cyclonus binary
    log "ensuring cyclonus binary is installed"
    rc=0; test -f npm-cyclonus.test || rc=$?
    if [[ $rc == 0 ]]; then
        log "cyclonus binary found, skipping install"
    else
        log "cyclonus binary not found, installing..."
        test -d cyclonus/ && rm -rf cyclonus/ || true
        git clone https://github.com/huntergregory/cyclonus.git --depth=1 --branch=stop-after-failure
        cd cyclonus/
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o ./cmd/cyclonus/cyclonus ./cmd/cyclonus
        cd ../
        mv cyclonus/cmd/cyclonus/cyclonus npm-cyclonus.test
        rm -rf cyclonus/
    fi

    log "beginning npm cyclonus test..."
    ./npm-cyclonus.test generate \
        --noisy=true \
        --retries=7 \
        --ignore-loopback=true \
        --cleanup-namespaces=true \
        --perturbation-wait-seconds=20 \
        --pod-creation-timeout-seconds=480 \
        --job-timeout-seconds=15 \
        --server-protocol=TCP,UDP \
        --exclude sctp,named-port,ip-block-with-except,multi-peer,upstream-e2e,example,end-port,namespaces-by-default-label,update-policy | tee npm-cyclonus.log || true
        # --exclude sctp,named-port,ip-block-with-except,multi-peer,upstream-e2e,example,end-port,namespaces-by-default-label,update-policy,all-namespaces,all-pods,allow-all,any-peer,any-port,any-port-protocol,deny-all,ip-block-no-except,multi-port/protocol,namespaces-by-label,numbered-port,pathological,peer-ipblock,peer-pods,pods-by-label,policy-namespace,port,protocol,rule,tcp,udp --include conflict,direction,egress,ingress,miscellaneous

    rc=0; cat npm-cyclonus.log | grep "failed" > /dev/null 2>&1 || rc=$?
    if [[ $rc == 0 ]]; then
        echo "ERROR: failures encountered in npm cyclonus test"
        capture_npm_hns_state
        return 1
    fi

    rc=0; cat npm-cyclonus.log | grep "SummaryTable:" > /dev/null 2>&1 || rc=$?
    if [[ $rc != 0 ]]; then
        log "ERROR: npm cyclonus test did not finish for some reason"
        capture_npm_hns_state
        return 1
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
        export KUBECONFIG="$PWD"/"${CLUSTER_NAME}".kubeconfig
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

trap cleanup EXIT
main
