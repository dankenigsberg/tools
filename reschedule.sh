#!/bin/bash

set -e

CNV_INSTALLED_NS=${CNV_INSTALLED_NS:-openshift-cnv}
MASTER_LABEL=${MASTER_LABEL:-node-role.kubernetes.io/master}
WORKER_LABEL=${WORKER_LABEL:-node-role.kubernetes.io/worker}

log() { printf "$@\n" >&2; }

oc_get_pods() {
	oc get pods -n "$CNV_INSTALLED_NS" -owide | grep "$1" | grep "$2" > /dev/null 2>&1
}

wait_until_moved_from() {
	local NODE_TYPE="$1"
	local DEPLOYMENT_NAME="$2"
	set +e
	oc_get_pods $NODE_TYPE $DEPLOYMENT_NAME
	while [ "$?" -eq "0" ] ; do
		log "Waiting for $DEPLOYMENT_NAME deployment pods to be moved from $NODE_TYPE..."
		sleep 5
		oc_get_pods $NODE_TYPE $DEPLOYMENT_NAME
	done
        log "$DEPLOYMENT_NAME has been moved from $NODE_TYPE"
	set -e
}

oc_patch_csv() {
	local OPERATOR_NAME="$1"
	local CSV_NAME="$2"
	log "Patching CNV Cluster Service Version for $OPERATOR_NAME deployment"
	VIRT_OPERATOR_SEQ_NUM=$(($(oc get csv "$CSV_NAME" -n "$CNV_INSTALLED_NS" -o=jsonpath='{range .spec.install.spec.deployments[*]}{.name}{"\n"}{end}' | grep -n "$OPERATOR_NAME" | cut -f1 -d:)-1))
	oc patch csv "${CSV_NAME}" -n "$CNV_INSTALLED_NS" --type=json -p "[{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/tolerations','value': [{'effect': 'NoSchedule','key': '$MASTER_LABEL','operator': 'Equal'}]},{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/nodeSelector','value': {'$MASTER_LABEL': ''}}]"
}

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
        key: $MASTER_LABEL
        operator: Equal
      nodeSelector:
        $MASTER_LABEL: ""
EOF
	for dpl in virt-api virt-controller; do
		oc patch deployment $dpl -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
		wait_until_moved_from worker $dpl
	done
}

patch_cdi_deployments() {
	log "Patching CDI deployments"
	local YAML_FILE
	YAML_FILE=$(mktemp -p /tmp -t cdi_patch.XXX)
	cat << EOF > "$YAML_FILE"
spec:
  template:
    spec:
      tolerations:
      - effect: NoSchedule
        key: $MASTER_LABEL
        operator: Equal
      nodeSelector:
        $MASTER_LABEL: ""
EOF
	oc scale deployment cdi-operator -n "$CNV_INSTALLED_NS" --replicas=0
	for dpl in cdi-apiserver cdi-uploadproxy cdi-deployment; do
		oc patch deployment $dpl -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
		wait_until_moved_from worker $dpl
	done
	oc scale deployment cdi-operator -n "$CNV_INSTALLED_NS" --replicas=1
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
        $WORKER_LABEL: ""
EOF
	oc patch ds virt-handler -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
        oc patch ds virt-handler -n openshift-cnv --type merge --patch '{"spec":{"template":{"spec":{"tolerations":[{"key":"worker","operator":"Equal","value":"load-balancer"}]}}}}'
}

patch_cluster_service_version() {
	local CSV_NAME
	local VIRT_OPERATOR_SEQ_NUM
	CSV_NAME=$(oc get csv -n "$CNV_INSTALLED_NS" -o custom-columns=:metadata.name | grep kubevirt-hyperconverged)
	for operator in virt-operator kubevirt-ssp-operator cluster-network-addons-operator cdi-operator hostpath-provisioner-operator hco-operator; do
		oc_patch_csv $operator $CSV_NAME
		wait_until_moved_from worker $operator
	done	
}

patch_ssp_deployments() {
	log "Patching SSP components"
	
	local YAML_FILE
	YAML_FILE=$(mktemp -p /tmp -t ssp_patch.XXX)
	cat << EOF > "$YAML_FILE"
spec:
  template:
    spec:
      tolerations:
      - effect: NoSchedule
        key: $MASTER_LABEL
        operator: Equal
      nodeSelector:
        $MASTER_LABEL: ""
EOF
	oc scale deployment kubevirt-ssp-operator -n "$CNV_INSTALLED_NS" --replicas=0
	oc patch deployment virt-template-validator -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
	oc patch ds kubevirt-node-labeller -n "$CNV_INSTALLED_NS" --type json -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {'$WORKER_LABEL': ""}}]'
	oc scale deployment kubevirt-ssp-operator -n "$CNV_INSTALLED_NS" --replicas=1
}

patch_v2v_deployments() {
	log "Patching V2V deployments"
	local YAML_FILE
	YAML_FILE=$(mktemp -p /tmp -t v2v_patch.XXX)
	cat << EOF > "$YAML_FILE"
spec:
  template:
    spec:
      tolerations:
      - effect: NoSchedule
        key: $MASTER_LABEL
        operator: Equal
      nodeSelector:
        $MASTER_LABEL: ""
EOF
	
	oc scale deployment vm-import-operator -n "$CNV_INSTALLED_NS" --replicas=0
	for dpl in vm-import-controller; do
		oc patch deployment $dpl -n "$CNV_INSTALLED_NS" --patch "$(cat "$YAML_FILE")"
		wait_until_moved_from worker $dpl
	done
	oc scale deployment vm-import-operator -n "$CNV_INSTALLED_NS" --replicas=1
}

main() {
	patch_ssp_deployments
	patch_cdi_deployments
	patch_kubevirt_deployments
	patch_kubevirt_ds
#	patch_v2v_deployments
	patch_cluster_service_version
}

if [ -z "$(which oc)" ]; then
       echo "OC tool is not installed"
       exit 1
else
	main
fi
