#!/bin/bash
echo "Installing necessary packages ..."
sudo apt-get update -y 2>&1 > /dev/null
sudo apt-get install -y qemu-kvm libvirt-daemon libvirt-daemon-system network-manager libguestfs-tools wget git 2>&1 > /dev/null

echo "Downloading latest version of CRC ..."
echo "---------------------------------"
wget https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-linux-amd64.tar.xz -q --show-progress

echo "Downloading latest version of OC client ..."
echo "---------------------------------------"
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -q --show-progress

echo "Extracting CRC binary ..."
echo "---------------------"
tar xvf crc-linux-amd64.tar.xz
sudo cp crc-linux-*-amd64/crc /usr/bin/crc

echo "Extracting OC binary ..."
echo "--------------------"

tar xvf openshift-client-linux.tar.gz
sudo cp oc /usr/bin/oc

rm -rf crc-linux* 2>&1 > /dev/null
rm openshift-client*  2>&1 > /dev/null
rm kubectl oc  2>&1 > /dev/null
echo "Cleanup ... [Done]"
echo "-------"

echo -n "Get your pull-secret from : https://cloud.redhat.com/openshift/create/local ~/pull-secret.txt"
