## Authors
## cblum@redhat.com
## karasing@redhat.com
## jelopez@redhat.com

#!/bin/bash
set +x
echo "Setting up environment for ODF - this will take a few minutes"

oc label "$(oc get no -o name)" cluster.ocs.openshift.io/openshift-storage='' --overwrite >/dev/null

oc create ns openshift-storage >/dev/null
oc project openshift-storage >/dev/null

cat <<EOF | oc create -f - >/dev/null
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ocs-catalogsource
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/mulbc/ocs-operator-index:katacoda-46
  displayName: OpenShift Container Storage
  publisher: Red Hat
EOF

sleep 10

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-subscription
  namespace: openshift-storage
spec:
  channel: alpha
  name: ocs-operator
  source: ocs-catalogsource
  sourceNamespace: openshift-marketplace
EOF

echo "Waiting for operators to be ready"
#
# Modified this to look until the CSV is deployed successfully
#
while [ "$(oc get csv -n openshift-storage | grep -c Succeeded)" -lt 1 ]; do echo -n "."; sleep 5; done

#
# Commentted this out as you already created the Subscription
#
#cat <<EOF | oc create -f - >/dev/null 2>&1
#apiVersion: operators.coreos.com/v1alpha1
#kind: Subscription
#metadata:
#  name: ocs-subscription
#  namespace: openshift-storage
#spec:
#  channel: alpha
#  name: ocs-operator
#  source: ocs-catalogsource
#  sourceNamespace: openshift-marketplace
#EOF
#  sleep 3
#done

echo "Operators are ready now"

cat <<EOF | oc create -f - >/dev/null
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: localblock
provisioner: kubernetes.io/no-provisioner
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-vdb
spec:
  capacity:
    storage: 100Gi
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: localblock
  local:
    path: /dev/odf/disk1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node.openshift.io/os_id
          operator: In
          values:
          - rhcos
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-vdc
spec:
  capacity:
    storage: 100Gi
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: localblock
  local:
    path: /dev/odf/disk2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node.openshift.io/os_id
          operator: In
          values:
          - rhcos
EOF

seq 20 30 | xargs -n1 -P0 -I {} oc patch pv/pv00{} -p '{"metadata":{"annotations":{"volume.beta.kubernetes.io/storage-class": "localfile"}}}' >/dev/null

echo "Finished up preparing the local storage"
#
# This is available starting with ODF 4.7.
# I think that this might already be in his code but we never know.
# Worst case scenario I have included a workaround later on. Do
# not worry as until 4.7 this will simply be overwritten by the
# ODF operator.
#
echo "Creating custom ODF configuration for CRC"

cat <<EOF | oc create -f - >/dev/null>/dev/null
apiVersion: v1
data:
  config: |2

    [global]
    mon_osd_full_ratio = .85
    mon_osd_backfillfull_ratio = .80
    mon_osd_nearfull_ratio = .75
    mon_max_pg_per_osd = 600
    osd_pool_default_min_size = 1
    osd_pool_default_size = 2
    [osd]
    osd_memory_target_cgroup_limit_ratio = 0.5
kind: ConfigMap
metadata:
  name: rook-config-override
  namespace: openshift-storage
EOF
#
# See later on for workaround
#

cat <<EOF | oc create -f - >/dev/null
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  resources:
    mon:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 125m
        memory: 128Mi
    mds:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 125m
        memory: 128Mi
    mgr:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 125m
        memory: 128Mi
    rgw:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 125m
        memory: 128Mi
  managedResources:
    cephConfig:
      reconcileStrategy: ignore
    cephBlockPools:
      reconcileStrategy: ignore
    cephFilesystems:
      reconcileStrategy: ignore
    cephObjectStoreUsers:
      reconcileStrategy: ignore
    cephObjectStores:
      reconcileStrategy: ignore
    snapshotClasses:
      reconcileStrategy: manage
    storageClasses:
      reconcileStrategy: manage
  multiCloudGateway:
    reconcileStrategy: ignore
  manageNodes: false
  monDataDirHostPath: /var/lib/rook
  storageDeviceSets:
  - count: 2
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1
        storageClassName: localblock
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 1
EOF

echo "ODF is installing now, please be patient"

oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
sleep 3
oc wait --for=condition=Ready --timeout=10m pod -l app=rook-ceph-tools
export POD=$(oc get po -l app=rook-ceph-tools -o name)
sleep 60
echo "Now configuring your ODF cluster"
#
# Woraround for config override and just in case
#
rookoperator=$(oc get pods -n openshift-storage -o name --field-selector='status.phase=Running' | grep 'rook-ceph-operator')
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config  config set global osd_pool_default_size 2 >/dev/null
#
# End workaround
#
echo "Configure your block environment"

cat <<EOF | oc create -f - >/dev/null
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: ocs-storagecluster-cephblockpool
  namespace: openshift-storage
spec:
  compressionMode: ""
  crushRoot: ""
  deviceClass: ""
  enableRBDStats: true
  erasureCoded:
    algorithm: ""
    codingChunks: 0
    dataChunks: 0
  failureDomain: osd
  replicated:
    requireSafeReplicaSize: false
    size: 2
EOF

cat <<EOF | oc create -f - >/dev/null
allowVolumeExpansion: true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ocs-storagecluster-ceph-rbd
parameters:
  clusterID: openshift-storage
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: openshift-storage
  csi.storage.k8s.io/fstype: ext4
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: openshift-storage
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: openshift-storage
  imageFeatures: layering
  imageFormat: "2"
  pool: ocs-storagecluster-cephblockpool
provisioner: openshift-storage.rbd.csi.ceph.com
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

#
# Try with this fixed for OCP 4.7
#
#cat <<EOF | oc create -f - >/dev/null
#apiVersion: snapshot.storage.k8s.io/v1
#deletionPolicy: Delete
#driver: openshift-storage.rbd.csi.ceph.com
#kind: VolumeSnapshotClass
#metadata:
#  name: ocs-storagecluster-rbdplugin-snapclass
#parameters:
#  clusterID: openshift-storage
#  csi.storage.k8s.io/snapshotter-secret-name: rook-csi-rbd-provisioner
#  csi.storage.k8s.io/snapshotter-secret-namespace: openshift-storage
#EOF

echo "Configuring your file environment"

cat <<EOF | oc create -f - >/dev/null 2>&1
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: ocs-storagecluster-cephfilesystem
  namespace: openshift-storage
spec:
  dataPools:
  - compressionMode: ""
    crushRoot: ""
    deviceClass: ""
    enableRBDStats: false
    erasureCoded:
      algorithm: ""
      codingChunks: 0
      dataChunks: 0
    failureDomain: osd
    replicated:
      requireSafeReplicaSize: false
      size: 2
  metadataPool:
    compressionMode: ""
    crushRoot: ""
    deviceClass: ""
    enableRBDStats: false
    erasureCoded:
      algorithm: ""
      codingChunks: 0
      dataChunks: 0
    failureDomain: osd
    replicated:
      requireSafeReplicaSize: false
      size: 2
  metadataServer:
    activeCount: 1
    activeStandby: false
    resources:
      limits:
        cpu: "1"
        memory: 1Gi
      requests:
        cpu: "500m"
        memory: 256Mi
  preservePoolsOnDelete: false
EOF

#
# Scale down the extra MDSs (replicaset and deployment)
#
secondmdsreplicaset=$(oc get replicaset -o name | grep mds | grep 'cephfilesystem-b')
oc scale ${secondmdsreplicaset} -n openshift-storage --replicas=0 >/dev/null 2>&1
secondmds=$(oc get deployment -o name -n openshift-storage | grep mds | grep 'cephfilesystem-b')
oc scale ${secondmds} -n openshift-storage --replicas=0 >/dev/null 2>&1
#
# Now make sure no HEALTH_WARNING shows up
#
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config fs set ocs-storagecluster-cephfilesystem standby_count_wanted 0 >/dev/null

cat <<EOF | oc create -f -
allowVolumeExpansion: true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ocs-storagecluster-cephfs
parameters:
  clusterID: openshift-storage
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: openshift-storage
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: openshift-storage
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: openshift-storage
  fsName: ocs-storagecluster-cephfilesystem
provisioner: openshift-storage.cephfs.csi.ceph.com
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

#
# Try with this fixed for OCP 4.7
#
#cat <<EOF | oc create -f - >/dev/null
#apiVersion: snapshot.storage.k8s.io/v1
#deletionPolicy: Delete
#driver: openshift-storage.cephfs.csi.ceph.com
#kind: VolumeSnapshotClass
#metadata:
#  name: ocs-storagecluster-cephfsplugin-snapclass
#parameters:
#  clusterID: openshift-storage
#  csi.storage.k8s.io/snapshotter-secret-name: rook-csi-cephfs-provisioner
#  csi.storage.k8s.io/snapshotter-secret-namespace: openshift-storage
#EOF

#
# Fix the device metrics pool incorrect settings here
#
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config  osd pool set device_health_metrics size 2 >/dev/null
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config  osd pool set device_health_metrics min_size 1 >/dev/null
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config  osd pool set device_health_metrics pg_num 8 >/dev/null
oc rsh -n openshift-storage ${rookoperator} ceph -c /var/lib/rook/openshift-storage/openshift-storage.config  osd pool set device_health_metrics pgp_num 8 >/dev/null
#
# This portion left commented out for now until we can discuss if we want this
# Worst case scenario what we have to do is like in https://red-hat-storage.github.io/ocs-training/training/ocs4/ocs4-enable-rgw.html
# But needs to be adapted for number of RGW as well as pool setting to have an osd failure domain.
# Other thing is if you want noobaa. Then we might have to do some more tricks to start noobaa but only have 1 RGW running as a backing
# Let's discuss this tomorrow Karan.
#
echo "Configuring you S3 environment"

cat <<EOF | oc create -f - >/dev/null
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: ocs-storagecluster-cephobjectstore
  namespace: openshift-storage
spec:
  dataPool:
    crushRoot: ""
    deviceClass: ""
    erasureCoded:
      algorithm: ""
      codingChunks: 0
      dataChunks: 0
    failureDomain: osd
    replicated:
      requireSafeReplicaSize: false
      size: 2
  gateway:
    allNodes: false
    instances: 1
    placement: {}
    port: 80
    resources: {}
    securePort: 0
    sslCertificateRef: ""
  metadataPool:
    crushRoot: ""
    deviceClass: ""
    erasureCoded:
      algorithm: ""
      codingChunks: 0
      dataChunks: 0
    failureDomain: osd
    replicated:
      size: 2
      requireSafeReplicaSize: false
EOF

cat <<EOF | oc create -f - >/dev/null
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: ocs-storagecluster-ceph-rgw
provisioner: openshift-storage.ceph.rook.io/bucket
parameters:
  objectStoreName: ocs-storagecluster-cephobjectstore
  objectStoreNamespace: openshift-storage
  region: us-east-1
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

cat <<EOF | oc create -f - >/dev/null
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: rgw
  namespace: openshift-storage
  labels:
    app: rook-ceph-rgw
    ceph_daemon_id: ocs-storagecluster-cephobjectstore
    ceph_daemon_type: rgw
    rgw: ocs-storagecluster-cephobjectstore
    rook_cluster: openshift-storage
    rook_object_store: ocs-storagecluster-cephobjectstore
spec:
  to:
    kind: Service
    name: rook-ceph-rgw-ocs-storagecluster-cephobjectstore
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Allow
EOF

echo "ODF is installed now"
