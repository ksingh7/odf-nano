# Deploying CRC

```
crc config set consent-telemetry no
crc config set enable-cluster-monitoring true
crc config set cpus 15
crc config set memory 60000
crc config view
crc setup
crc start  --log-level debug -p /mnt/hdd_space1/pull-secret.txt
```

- If running out of space, create a symlink for .crc
```
mkdir /mnt/hdd_space1/.crc
ln -s /mnt/hdd_space1/.crc ~/.crc
```

- Deep clean previous instance of crc
```
crc delete -f
rm -rf /mnt/hdd_space1/.crc/*
sudo virsh list --all
sudo virsh destroy crc
sudo virsh undefine crc
```
- To ssh into crc vm
```
ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)"
```

# Access CRC from a remote client

### Execute on the Host running CRC VM
```
export SERVER_IP=0.0.0.0
export CRC_IP=$(crc ip)

sudo apt-get install haproxy
sudo cp haproxy.cfg haproxy.cfg.backup
vim haprox.cfg
```

```
defaults
    mode http
    log global
    option httplog
    option  http-server-close
    option  dontlognull
    option  redispatch
    option  contstats
    retries 3
    backlog 10000
    timeout client          25s
    timeout connect          5s
    timeout server          25s
    timeout tunnel        3600s
    timeout http-keep-alive  1s
    timeout http-request    15s
    timeout queue           30s
    timeout tarpit          60s
    default-server inter 3s rise 2 fall 3
    option forwardfor

frontend apps
    bind SERVER_IP:80
    bind SERVER_IP:443
    option tcplog
    mode tcp
    default_backend apps

backend apps
    mode tcp
    balance roundrobin
    option tcp-check
    server webserver1 CRC_IP check port 80

frontend api
    bind SERVER_IP:6443
    option tcplog
    mode tcp
    default_backend api

backend api
    mode tcp
    balance roundrobin
    option tcp-check
    server webserver1 CRC_IP:6443 check port 6443
```

```
sudo sed -i "s/SERVER_IP/$SERVER_IP/g" haproxy.cfg
sudo sed -i "s/CRC_IP/$CRC_IP/g" haproxy.cfg

sudo systemctl start haproxy
sudo systemctl status haproxy

sudo netstat -plunt  | grep -i haproxy
```
- Example output from `netstat`
```
$ sudo netstat -plunt  | grep -i haproxy
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      9291/haproxy
tcp        0      0 0.0.0.0:443             0.0.0.0:*               LISTEN      9291/haproxy
tcp        0      0 0.0.0.0:6443            0.0.0.0:*               LISTEN      9291/haproxy

```


## MACos Client Node 
https://www.stevenrombauts.be/2018/01/use-dnsmasq-instead-of-etc-hosts/

```
brew install dnsmasq
sudo brew services start dnsmasq
mkdir -p /usr/local/etc/dnsmasq.d
touch /usr/local/etc/dnsmasq.d/crc.conf
vim /usr/local/etc/dnsmasq.d/crc.conf
```
```
address=/.testing/192.168.1.6
```
- verify dns resolution
```
sudo brew services restart dnsmasq
dig apps-crc.testing @127.0.0.1
dig console-openshift-console.apps-crc.testing @127.0.0.1
```
```
sudo mkdir /etc/resolver
sudo vim /etc/resolver/testing
nameserver 127.0.0.1

scutil --dns

ping -c 1 foo.api.crc.testing
ping -c 1 foo.apps-crc.testing
ping -c 1 console-openshift-console.apps-crc.testing
```
### Finally access the dashboard
Access https://console-openshift-console.apps-crc.testing from client machine

## OpenShift Data Foundation on CRC

- CRC prerequisite for ODF

```
alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)"'

crc stop
virsh list
virsh dumpxml crc > crc.xml
vim crc.xml
- In the <devices> section add the following to the crc.xml configuration file and save the changes:

  <devices>
    <controller type='pci' model='pci-bridge'/>
  </devices>

    <controller type='pci' index='0' model='pci-bridge'>
      <model name='pcie-root-port'/>
      <target chassis='6' port='0x15'/>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </controller>

crc stop
virsh list
virsh dumpxml crc > crc.xml
vim crc.xml

## Don't worry this is thin provisioned
sudo -S qemu-img create -f raw ~/.crc/vdb 50G
sudo -S qemu-img create -f raw ~/.crc/vdc 50G
sudo -S qemu-img create -f raw ~/.crc/vdd 50G


    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='/mnt/hdd_space1/mohit/.crc/vdb' index='1'/>
      <backingStore/>
      <target dev='vdb' bus='virtio'/>
      <alias name='virtio-disk1'/>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='/mnt/hdd_space1/mohit/.crc/vdc' index='2/>
      <backingStore/>
      <target dev='vdc' bus='virtio'/>
      <alias name='virtio-disk2'/>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='/mnt/hdd_space1/mohit/.crc/vdd' index='3'/>
      <backingStore/>
      <target dev='vdd' bus='virtio'/>
      <alias name='virtio-disk3'/>
      <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
    </disk>

virsh define crc.xml

crc start

crcssh lsblk
```

- Deploy ODF on CRC

```
## Login to CRC
oc login -u kubeadmin -p P3EpZ-pGpYf-ITy8f-7t6NE https://api.crc.testing:6443


sh install_odf.sh
```
- Sample output
```
Setting up environment for ODF - this will take a few minutes
subscription.operators.coreos.com/ocs-subscription created
Waiting for operators to be ready
No resources found in openshift-storage namespace.
.No resources found in openshift-storage namespace.
...
.No resources found in openshift-storage namespace.
...............................Operators are ready now
Finished up preparing the local storage
ODF is installing now, please be patient
ocsinitialization.ocs.openshift.io/ocsinit patched
pod/rook-ceph-tools-7d95854fb8-b78s2 condition met
ODF is installed now
```
```
oc get sc
```
