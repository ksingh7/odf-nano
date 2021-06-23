```
bash launch.sh
ssh -i "ksingh-mumbai.pem" fedora@ec2-13-235-62-230.ap-south-1.compute.amazonaws.com cat /var/log/crc_status
ssh -i "ksingh-mumbai.pem" fedora@ec2-13-233-149-189.ap-south-1.compute.amazonaws.com tail -f /var/log/crc_setup.log
ssh -i "ksingh-mumbai.pem" fedora@ec2-13-235-62-230.ap-south-1.compute.amazonaws.com tail -f /var/log/cloud-init-output.log
ssh -i "ksingh-mumbai.pem" fedora@ec2-13-235-62-230.ap-south-1.compute.amazonaws.com
wget https://gist.githubusercontent.com/ksingh7/7245aabdf6b9772ca8ef3c4df998d2fa/raw/1e63ba398edd229bf47e9ce99d2ad9d282e7ccc8/pull-secret.txt
crc setup
crc start -p ~/pull-secret.txt
#  Configure haproxy


alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)"'
crc stop

# Increase DISK size
CRC_MACHINE_IMAGE=${HOME}/.crc/machines/crc/crc.qcow2

# This resize is thin-provisioned
sudo qemu-img resize ${CRC_MACHINE_IMAGE} +40G
sudo cp ${CRC_MACHINE_IMAGE} ${CRC_MACHINE_IMAGE}.ORIGINAL

#increase the /dev/sda4 (known as vda4 in the VM) disk partition size by an additional 20GB
sudo virt-resize --expand /dev/sda4 ${CRC_MACHINE_IMAGE}.ORIGINAL ${CRC_MACHINE_IMAGE}
sudo rm ${CRC_MACHINE_IMAGE}.ORIGINAL

sudo virsh list --all
sudo virsh dumpxml crc > crc.xml

# Relaunch new spot instance
#automate these steps
sudo virsh define ~/crc.xml
sudo virsh list --all
crc setup
crc start -p ~/pull-secret.txt

- Fix virt-resize
- Test virsh define crc.xml 
- automate that
- create keypairs
- add tags to instance
- destroy.sh , search by tag instead of instance type
- delete spot request
- parameterize delete.sh , full delete , or delete just instance
An error occurred (DependencyViolation) when calling the DeleteSecurityGroup operation: resource sg-0deb585fffca6c599 has a dependent object
- above when instance takes time to get delete
- add getops to bash script (launch and delete
- launch script , add logic to check the sg before creating, skip if already present


```
- Configure Local machine to use CRC on Spot
```
sudo rm /usr/local/etc/dnsmasq.d/crc.conf
EC2_PUB_IP=3.6.39.231
echo "address=/apps-crc.testing/$EC2_PUB_IP" >> /usr/local/etc/dnsmasq.d/crc.conf
echo "address=/api.crc.testing/$EC2_PUB_IP" >> /usr/local/etc/dnsmasq.d/crc.conf
sudo brew services restart dnsmasq
dig apps-crc.testing @127.0.0.1
dig console-openshift-console.apps-crc.testing @127.0.0.1

```

address=/apps-crc.testing/3.6.39.231
address=/api.crc.testing/13.235.84.223