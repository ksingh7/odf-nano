#!/bin/bash

oc delete -n openshift-storage storagecluster --all  --wait=true --timeout=10s
for i in  storageclusters.ocs.openshift.io/ocs-storagecluster cephblockpools.ceph.rook.io/ocs-storagecluster-cephblockpool cephfilesystems.ceph.rook.io/ocs-storagecluster-cephfilesystem cephobjectstores.ceph.rook.io/ocs-storagecluster-cephobjectstore cephclusters.ceph.rook.io/ocs-storagecluster-cephcluster ; do oc delete $i --wait=true --timeout=10s ; done
