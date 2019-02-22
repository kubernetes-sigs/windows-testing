#!/bin/bash
set -eo pipefail

NSSM_VERSION=2.24
NSSM_URL=https://k8stestinfrabinaries.blob.core.windows.net/nssm-mirror/nssm-${NSSM_VERSION}.zip

exec_with_retry() {

      local retry=0
      local max_retries=$1
      local cmd=${@:2}
      local exit_code=0

      while [[ ${retry} -lt ${max_retries} ]]; do
          eval $cmd || exit_code=$?
          if [[ ${exit_code} -eq 0 ]]; then
              return ${exit_code}
          fi
          let retry=retry+1
     done
     if [[ ! ${exit_code} -eq 0 ]]; then
          echo "Failed to execute command: $cmd with exit_code: ${exit_code}"
          return ${exit_code}
    fi
}

create_dist_dir() {
	mkdir -p ${DIST_DIR}
}

build_kubelet() {
	echo "building kubelet.exe..."
	$KUBEPATH/build/run.sh make WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=windows/amd64 KUBE_VERBOSE=0
	cp ${GOPATH}/src/k8s.io/kubernetes/_output/dockerized/bin/windows/amd64/kubelet.exe ${DIST_DIR}
}

build_kubeproxy() {
	echo "building kube-proxy.exe..."
	$KUBEPATH/build/run.sh make WHAT=cmd/kube-proxy KUBE_BUILD_PLATFORMS=windows/amd64 KUBE_VERBOSE=0
	cp ${GOPATH}/src/k8s.io/kubernetes/_output/dockerized/bin/windows/amd64/kube-proxy.exe ${DIST_DIR}
}

build_kubectl() {
	echo "building kubectl.exe..."
	$KUBEPATH/build/run.sh make WHAT=cmd/kubectl KUBE_BUILD_PLATFORMS=windows/amd64 KUBE_VERBOSE=0
	cp ${GOPATH}/src/k8s.io/kubernetes/_output/dockerized/bin/windows/amd64/kubectl.exe ${DIST_DIR}
}

build_kube_binaries_for_upstream_e2e() {
	$KUBEPATH/build/run.sh make WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=linux/amd64 KUBE_VERBOSE=0

	build_kubelet
	build_kubeproxy
	build_kubectl
}

download_nssm() {
	echo "downloading nssm ..."
	exec_with_retry 5 "curl --fail ${NSSM_URL} -o /tmp/nssm-${NSSM_VERSION}.zip"
	unzip -q -d /tmp /tmp/nssm-${NSSM_VERSION}.zip
	cp /tmp/nssm-${NSSM_VERSION}/win64/nssm.exe ${DIST_DIR}
	chmod 775 ${DIST_DIR}/nssm.exe
	rm -rf /tmp/nssm-${NSSM_VERSION}*
}

download_wincni() {
	echo "downloading wincni ..."
	mkdir -p ${DIST_DIR}/cni/config
	WINSDN_URL=https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/
	WINCNI_EXE=cni/wincni.exe
	HNS_PSM1=hns.psm1
	exec_with_retry 5 "curl --fail -L ${WINSDN_URL}${WINCNI_EXE} -o ${DIST_DIR}/${WINCNI_EXE}"
	exec_with_retry 5 "curl --fail -L ${WINSDN_URL}${HNS_PSM1} -o ${DIST_DIR}/${HNS_PSM1}"
}

create_zip() {
	ZIP_NAME="${k8s_e2e_upstream_version:-"v${ACS_VERSION}int.zip"}"
	cd ${DIST_DIR}/..
	zip -r ../${ZIP_NAME} k/*
	cd -
}

usage() {
	echo "$0 [-v version] [-p acs_patch_version]"
	echo " -u <version build for kubernetes upstream e2e tests>: k8s_e2e_upstream_version"
	echo " -z <zip path>: zip_path"
}

while getopts ":u:z:" opt; do
  case ${opt} in
	u)
	  k8s_e2e_upstream_version=${OPTARG}
	  ;;
	z)
	  zip_path=${OPTARG}
	  ;;  
    *)
			usage
			exit
      ;;
  esac
done

KUBEPATH=${GOPATH}/src/k8s.io/kubernetes


DIST_DIR=${zip_path}/k
create_dist_dir
build_kube_binaries_for_upstream_e2e
download_nssm
download_wincni
create_zip
