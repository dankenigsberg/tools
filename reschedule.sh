#!/bin/bash

set -e

if [ -z $(which oc) ]; then
       echo "OC tool is not installed"
       exit 1

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

cat << EOF > patch_taint_csv.yaml
spec:
  install:
    spec:
      deployments:
      - name: virt-operator
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

#Patch deployments
for dpl in virt-api virt-controller; do
	oc patch deployment $dpl --patch "$(cat patch_taint.yaml)"
done

#Patch DaemonSets
for dst in virt-handler; do
	oc patch ds $dst --patch "$(cat patch_taint_worker.yaml)"
done



