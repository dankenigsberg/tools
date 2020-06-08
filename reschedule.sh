#!/bin/bash

set -e

if [ -z $(which oc) ]; then
       echo "OC tool is not installed"
       exit 1
fi

rm -rf patch_taint.yaml patch_taint_worker.yaml patch_taint_csv.yaml

cat << EOF > patch_taint.yaml
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

cat << EOF > patch_taint_worker.yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
EOF

#Patch deployments
for dpl in virt-api virt-controller; do
	oc patch deployment $dpl --patch "$(cat patch_taint.yaml)"
done

#Patch DaemonSets
for dst in virt-handler; do
	oc patch ds $dst --patch "$(cat patch_taint_worker.yaml)"
done

##Patch ClusterServiceVersion

# get the CNV's CSV name
CSV_NAME=$(oc get csv -n openshift-cnv -o custom-columns=:metadata.name)

# get the virt-operator deployment sequence number in the CSV (subtracting 1 as it's starts from 0)
VIRT_OPERATOR_SEQ_NUM=$(($(oc get csv $CSV_NAME -o=jsonpath='{range .spec.install.spec.deployments[*]}{.name}{"\n"}{end}' | grep -n "virt-operator" | cut -f1 -d:)-1))

# patch the virt-operator deployment with the tolerations and node selector
oc patch csv ${CSV_NAME} -n openshift-cnv --type=json -p "[{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/tolerations','value': [{'effect': 'NoSchedule','key': 'node-role.kubernetes.io/master','operator': 'Equal'}]},{'op': 'add','path': '/spec/install/spec/deployments/$VIRT_OPERATOR_SEQ_NUM/spec/template/spec/nodeSelector','value': {'node-role.kubernetes.io/master': ''}}]"

