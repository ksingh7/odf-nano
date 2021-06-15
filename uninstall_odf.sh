#!/bin/bash

oc annotate storagecluster ocs-storagecluster uninstall.ocs.openshift.io/cleanup-policy="delete" --overwrite
oc annotate storagecluster ocs-storagecluster uninstall.ocs.openshift.io/mode="forced" --overwrite

oc delete -n openshift-storage storagecluster --all  --wait=true --timeout=10s

for i in  storageclusters.ocs.openshift.io/ocs-storagecluster cephblockpools.ceph.rook.io/ocs-storagecluster-cephblockpool cephfilesystems.ceph.rook.io/ocs-storagecluster-cephfilesystem cephobjectstores.ceph.rook.io/ocs-storagecluster-cephobjectstore cephclusters.ceph.rook.io/ocs-storagecluster-cephcluster ; do oc delete $i --wait=true --timeout=10s ; done

for i in  storageclusters.ocs.openshift.io/ocs-storagecluster cephblockpools.ceph.rook.io/ocs-storagecluster-cephblockpool cephfilesystems.ceph.rook.io/ocs-storagecluster-cephfilesystem cephobjectstores.ceph.rook.io/ocs-storagecluster-cephobjectstore cephclusters.ceph.rook.io/ocs-storagecluster-cephcluster ; do oc patch $i --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'  ; done

oc delete catalogsources.operators.coreos.com -n openshift-marketplace ocs-catalogsource
oc delete subscription.operators.coreos.com/ocs-subscription
oc delete csv ocs-operator.v9.9.0


for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rf  /var/lib/rook; done

oc delete project openshift-storage

for i in localblock openshift-storage.noobaa.io ocs-storagecluster-ceph-rbd ocs-storagecluster-ceph-rgw ocs-storagecluster-cephfs ; do oc delete sc $i ; done

oc delete crd backingstores.noobaa.io bucketclasses.noobaa.io cephblockpools.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephnfses.ceph.rook.io cephobjectstores.ceph.rook.io cephobjectstoreusers.ceph.rook.io noobaas.noobaa.io ocsinitializations.ocs.openshift.io storageclusters.ocs.openshift.io cephclients.ceph.rook.io cephobjectrealms.ceph.rook.io cephobjectzonegroups.ceph.rook.io cephobjectzones.ceph.rook.io cephrbdmirrors.ceph.rook.io --wait=true --timeout=30s

echo "Deleting Storage Classes"

export SC=localblock
oc get pv | grep $SC | awk '{print $1}'| xargs oc delete pv
oc delete sc $SC
oc project default
for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /mnt/local-storage/${SC}/; done
oc delete localvolumediscovery.local.storage.openshift.io/auto-discover-devices -n openshift-local-storage

alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)"'
for i in vdb vdc vdd ; do crcssh sudo  wipefs -af /dev/$i ; done
for i in vdb vdc vdd  ; do crcssh sudo sgdisk --zap-all /dev/$i ; done
for i in vdb vdc vdd  ; do crcssh sudo dd  if=/dev/zero of=/dev/$i bs=1M count=100 oflag=direct,dsync  ; done
for i in vdb vdc vdd  ; do crcssh sudo blkdiscard /dev/$i ; done

