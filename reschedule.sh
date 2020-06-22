#!/bin/bash

set -e

log() { echo "$@" >&2; }

patch_kubevirt_deployments() {
	log "Patching Kubevirt deployments"
	YAML_FILE=$(mktemp -p /tmp -t kv_patch.XXX)
	cat << EOF > $YAML_FILE
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
		oc patch deployment $dpl --patch "$(cat $YAML_FILE)"
	done
}

patch_kubevirt_ds() {
	log "Patching Kubevirt DaemonSets"
	YAML_FILE=$(mktemp -p /tmp -t kv_patch.XXX)
	cat << EOF > $YAML_FILE
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
EOF
	oc patch ds virt-handler --patch "$(cat $YAML_FILE)"
}

patch_cluster_service_version() {
	log "Patching CNV Cluster Service Version for virt-operator deployment"
	CSV_NAME=$(oc get csv -n openshift-cnv -o custom-columns=:metadata.name)
	VIRT_OPERATOR_SEQ_NUM=$(($(oc get csv $CSV_NAME -o=jsonpath='{range .spec.install.spec.deployments[*]}{.name}{"\n"}{end}' | grep -n "virt-operator" | cut -f1 -d:)-1))

	oc patch csv ${CSV_NAME} -n openshift-cnv --type=json -p "[{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/tolerations','value': [{'effect': 'NoSchedule','key': 'node-role.kubernetes.io/master','operator': 'Equal'}]},{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/nodeSelector','value': {'node-role.kubernetes.io/master': ''}}]"
}

if [ -z "$(which oc)" ]; then
       echo "OC tool is not installed"
       exit 1
fi
