#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

log() {
	local msg=$1
	echo "$(date -R): $msg"
}

update_coredns() {
	# Get the IP of the DC as soon as it is available
	while [[ -z "${DCIP:-}" ]]; do
		DCIP=$(${KUBECTL} get node --selector="agentpool=windowsgmsa" -o jsonpath="{.items[*].status.addresses[?(@.type=='InternalIP')].address}") > /dev/null 2>&1
		sleep 5
	done

  cat << EOF >> coredns-custom.sed
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  Corefile: |
    k8sgmsa.lan:53 {
      errors
      cache 30
      log
      forward . DCIP
    }
EOF

	# Place the IP for the DC into the config file
	sed "s/DCIP/${DCIP}/g" coredns-custom.sed > coredns-custom.yml

	# Apply the config file
	${KUBECTL} apply -f coredns-custom.yml

	# Restart the CoreDNS pods to pick up the changes
	${KUBECTL} -n kube-system rollout restart deployment coredns
}


# require exports for timeout which spawns new sub shell
export KUBECONFIG="$(find /home/*/.kube/config)"
export KUBECTL="kubectl --kubeconfig=${KUBECONFIG}"
export -f update_coredns
export -f log

log "start updating core dns for gmsa node"

time timeout 500 bash -c update_coredns

# Check the status of all the pods.
${KUBECTL} get pods -A -o wide
${KUBECTL} describe nodes
log "finish updating core dns for gmsa node"
