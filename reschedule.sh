#!/bin/bash

set -e

CNV_INSTALLED_NS={$CNV_INSTALLED_NS-:openshift-cnv}

log() { echo "$@" >&2; }

patch_kubevirt_deployments() {
	log "Patching Kubevirt deployments"
	local YAML_FILE
	YAML_FILE=$(mktemp -p /tmp -t kv_patch.XXX)
	cat << EOF > "$YAML_FILE"
spec:
  template:
    spec:
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Equal
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOF
	for dpl in virt-api virt-controller; do
		oc patch deployment $dpl -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
	done
}

patch_kubevirt_ds() {
	log "Patching Kubevirt DaemonSets"
	local YAML_FILE
	YAML_FILE=$(mktemp -p /tmp -t kv_patch.XXX)
	cat << EOF > "$YAML_FILE"
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
EOF
	oc patch ds virt-handler -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
}

patch_cluster_service_version() {
	log "Patching CNV Cluster Service Version for virt-operator deployment"
	local CSV_NAME
	local VIRT_OPERATOR_SEQ_NUM
	CSV_NAME=$(oc get csv -n "$CNV_INSTALLED_NS" -o custom-columns=:metadata.name)
	VIRT_OPERATOR_SEQ_NUM=$(($(oc get csv "$CSV_NAME" -o=jsonpath='{range .spec.install.spec.deployments[*]}{.name}{"\n"}{end}' | grep -n "virt-operator" | cut -f1 -d:)-1))
	oc patch csv "${CSV_NAME}" -n openshift-cnv --type=json -p "[{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/tolerations','value': [{'effect': 'NoSchedule','key': 'node-role.kubernetes.io/master','operator': 'Equal'}]},{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/nodeSelector','value': {'node-role.kubernetes.io/master': ''}}]"
}

patch_ssp_deployments() {
	log "Patching SSP node labeller Daemonset"
	local namespace_labeller
	local namespace_ssp_operator
	namespace_labeller=$(oc get ds --all-namespaces | grep node-labeller | cut -d" " -f1)
	namespace_ssp_operator=$(oc get deployments --all-namespaces | grep kubevirt-ssp-operator | cut -d" " -f1)
	oc scale deployment kubevirt-ssp-operator -n "$namespace_ssp_operator" --replicas=0
	oc patch ds kubevirt-node-labeller -n "$namespace_labeller" --type json -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"node-role.kubernetes.io/worker": ""}}]'
}

main() {
	patch_kubevirt_deployments 
	patch_kubevirt_ds
	patch_cluster_service_version
	patch_ssp_deployments
}

if [ -z "$(which oc)" ]; then
       echo "OC tool is not installed"
       exit 1
else
	main
fi
