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
    export PRIVATE_TESTING="${PRIVATE_TESTING:-""}"

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
    if [[ ! "${PRIVATE_TESTING}" == "true" ]]; then
        chmod +x "${SCRIPT_ROOT}/run-k8s-e2e-test.sh"
        "${SCRIPT_ROOT}/run-k8s-e2e-test.sh"
    else
        run_e2e_test_in_pod
    fi
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
        elif [[ "${PRIVATE_TESTING}" == "true" ]]; then
            template="$SCRIPT_ROOT"/templates/private-test.yaml
        fi
        echo "Using $template"
        
        az capi create -mg "${CLUSTER_NAME}" -y -w -n "${CLUSTER_NAME}" -l "$AZURE_LOCATION" --template "$template" --tags creationTimestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        
        # copy generated template to logs
        mkdir -p "${ARTIFACTS}"/clusters/bootstrap
        cp "${CLUSTER_NAME}.yaml" "${ARTIFACTS}"/clusters/bootstrap || true
        log "cluster creation complete"
    fi

    # set the kube config to the workload cluster only if tests run on local system
    if [[ ! "${PRIVATE_TESTING}" == "true" ]]; then
        export KUBECONFIG="$PWD"/"${CLUSTER_NAME}".kubeconfig
    fi
}

run_e2e_test_in_pod(){
    export SKIP_TEST="${SKIP_TEST:-"false"}"
    if [[ ! "$SKIP_TEST" == "true" ]]; then
        log "delete test-pod if exist"
        kubectl delete pod test-pod --ignore-not-found=true
        kubectl apply -f "$SCRIPT_ROOT"/private/run-e2e-test-sa.yaml
        < "$SCRIPT_ROOT"/private/e2etest-pod.yaml envsubst | kubectl apply -f -
        max_item=50
        counter=0
        log "wait test to completed or error ..."
        ret=1
        while [ $ret -ne 0 ] && [ "$counter" -lt "$max_item" ]; do
            log "Check status again #$counter"
            (( counter++ ))
            current_status=$(kubectl get pod test-pod --no-headers -o=custom-columns=:.status.phase)
            if [[ "${current_status,,}" == "failed" ]] || [[ "${current_status,,}" == "succeeded" ]]; then
                log "error occure in test-pod, exiting ..."
                counter=$max_item    
            fi
            ret=0
            kubectl wait --timeout 3m --for=condition=Ready pod/test-pod || ret=$?
        done
        if [ $ret == 0 ]; then
            echo "Tests are completed. Copying artifacts from test-pod:_artifacts to ${ARTIFACTS}"
            kubectl cp test-pod:_artifacts/ "${ARTIFACTS}/"
        fi
        kubectl logs test-pod -c e2e-test
        kubectl logs test-pod -c e2e-test > "${ARTIFACTS}/e2e-test.log"
	    #kubectl delete pod test-pod
        exitcode=$(< "${ARTIFACTS}/exit-code.txt")
        return "$exitcode"
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
