#!/bin/bash
# bash post_install.sh ~/pull-secret.txt true
PULL_SECRET_PATH=$1
EXPAND_CRC_DISK_SIZE=$2

CRC_XML_FILE=~/crc.xml
if [ -f "$CRC_XML_FILE" ]; then
    echo "Previously configured CRC environment detected ... "
    echo "Reconfiguring CRC ..."
    for service in  libvirtd.service libvirtd.socket ; do sudo systemctl start $service ; done
    for service in  libvirtd.service libvirtd.socket ; do sudo systemctl enable $service ; done
    sudo virsh define ~/crc.xml
fi

echo "Settingup CRC ... "
crc setup

if [ -n "$PULL_SECRET_PATH" ]; then
    echo "Starting CRC ... "
    crc start -p $PULL_SECRET_PATH
elif  [ -f "~/pull-secret.txt" ]; then
    echo "Starting CRC ... "
    crc start -p ~/pull-secret.txt
else
    echo "Error: CRC Pull Secret not provided, Exiting..." 
    echo "Get your pull secret from https://cloud.redhat.com/openshift/create/local and save it as ~/pull-secret.txt"
    exit 1
fi

if [ ! -f "$CRC_XML_FILE" ]; then
    echo "Stopping CRC temporarily ... "
    crc stop
    
    if [[ "$EXPAND_CRC_DISK_SIZE" == "true" ]]; then
        echo "Expanding CRC ROOT Disk Size by +40G ..."
        # Increase DISK size
        CRC_MACHINE_IMAGE=${HOME}/.crc/machines/crc/crc.qcow2
        # This resize is thin-provisioned
        sudo qemu-img resize ${CRC_MACHINE_IMAGE} +40G
        sudo cp ${CRC_MACHINE_IMAGE} ${CRC_MACHINE_IMAGE}.ORIGINAL  
        #increase the /dev/sda4 (known as vda4 in the VM) disk partition size by an additional 20GB
        sudo virt-resize --expand /dev/sda4 ${CRC_MACHINE_IMAGE}.ORIGINAL ${CRC_MACHINE_IMAGE}
        sudo rm ${CRC_MACHINE_IMAGE}.ORIGINAL
    fi

    echo "Listing Libvirt VMs ... "
    sudo virsh list --all
    echo "Dumping VM config in XML  ... "
    sudo virsh dumpxml crc > ~/crc.xml
    echo "Starting CRC ... "
    crc start -p ~/pull-secret.txt
fi

sleep 10

echo "Setting up HAPROXY on host machine ..."
SERVER_IP=0.0.0.0
CRC_IP=$(crc ip)
sudo cp /etc/haproxy/haproxy.cfg{,.bak}
sudo semanage port -a -t http_port_t -p tcp 6443
sudo tee /etc/haproxy/haproxy.cfg &>/dev/null <<EOF
global
    log /dev/log local0

defaults
    balance roundrobin
    log global
    maxconn 100
    mode tcp
    timeout connect 5s
    timeout client 500s
    timeout server 500s

listen apps
    bind 0.0.0.0:80
    server crcvm $CRC_IP:80 check

listen apps_ssl
    bind 0.0.0.0:443
    server crcvm $CRC_IP:443 check

listen api
    bind 0.0.0.0:6443
    server crcvm $CRC_IP:6443 check
EOF
echo "Starting HAPROXY Service ..."
sudo systemctl restart haproxy

echo "========= Post Launch Configuration Completed Successfully =============="
