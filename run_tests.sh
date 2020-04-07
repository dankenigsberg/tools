#!/bin/bash

export kubevirtNamespace="openshift-cnv"
_kubectl=$(which kubectl)
_oc=$(which oc)

if [[ -z ${_kubectl} && -z ${_oc} ]]; then
	echo "You don't have OC or KUBECTL installed"
	exit 1
fi

if [ -z "${KUBECONFIG}" ]; then
	echo "KUBECONFIG is not set"
	exit 1
fi

      	
cat << EOF > test_config.json
{ 
 "storageClassLocal": "hostpath-provisioner", 
 "storageClassHostPath": "hostpath-provisioner", 
 "storageClassRhel": "hostpath-provisioner", 
 "storageClassWindows": "hostpath-provisioner", 
 "manageStorageClasses": false 
}
EOF

oc create namespace kubevirt
rm -rf _out
hack/dockerized hack/build-func-tests.sh
make manifests
rm -f _out/manifests/testing/cdi-*
rm -f _out/manifests/testing/kubevirt-config.yaml
sed -i "s/namespace: kubevirt/namespace: ${kubevirtNamespace}/g" _out/manifests/testing/*.yaml
_out/tests/tests.test --cdi-namespace="openshift-cnv" \
	--config=${PWD}/test_config.json \
	--container-tag=v0.26.1 --container-tag-alt=v0.26.1_alt \
	--deploy-testing-infra \
	--ginkgo.seed=0 \
	--installed-namespace=openshift-cnv \
	--junit-output=${PWD}/xunit_results.xml \
	--kubeconfig=${KUBECONFIG} \
	--kubectl-path=${_kubectl} \
	--oc-path=${_oc} \
	--path-to-testing-infra-manifests=${PWD}/_out/manifests/testing \
	--polarion-custom-plannedin=2_3 \
	--polarion-execution=true \
	--polarion-project-id=CNV \
	--polarion-report-file=polarion_results.xml \
	--test-tier=tier1

