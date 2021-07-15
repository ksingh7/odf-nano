#!/bin/bash
shopt -s expand_aliases
source ~/.bash_aliases

read -p "Enter volume count Example: 2 > " VOLUME_COUNT
read -p "Enter volume size Example: 100 > " VOLUME_SIZE

if [ ${VOLUME_COUNT} -gt 5 ];
then 
  echo "Volume count of ${VOLUME_COUNT} is too high"
  echo "A max of five volumes may be added."
  exit 1
fi


if [ ${VOLUME_COUNT} -lt 2 ];
then 
  echo "setting default volume count to 2"
  VOLUME_COUNT=2
fi

if [ ${VOLUME_SIZE} -lt 100 ]
then 
  echo "setting default volume size to 100"
  VOLUME_SIZE=100
fi

virtual_drive[1]="vdb"
virtual_drive[2]="vdc"
virtual_drive[3]="vdd"
virtual_drive[4]="vde"
virtual_drive[5]="vdf"

for  (( i = 1; i <= $VOLUME_COUNT; i++ ))
do
  echo "Create ${virtual_drive[$i]} for ODF-Nano"
  sudo -S qemu-img create -f raw ~/.crc/${virtual_drive[$i]} ${VOLUME_SIZE}G
done

CRC_STATUS=$(crc status | grep "CRC VM:" | awk '{print $3}')
if [ $CRC_STATUS == "Running" ];
then 
  echo "crc stop"
  crc stop 
fi 
sudo virsh list --all
sudo virsh dumpxml crc > ~/crc.xml

BUS=$(grep -o '0x03' ~/crc.xml| egrep -o '.{1}$')

for  (( i = 1; i <= $VOLUME_COUNT; i++ ))
do
    echo "Checking that ${virtual_drive[$i]} exists on crc"
    if grep '/home/admin/.crc/'${virtual_drive[$i]}''  ~/crc.xml  > /dev/null
    then
    echo "$HOME/.crc/${virtual_drive[$i]} already exists in ~/crc.xml"
    exit 1
    fi
done 

if [ ${BUS} -ne 3 ];
then 
 echo "Incorrect address bus for drive"
 exit 1
fi 

if [ -f ~/crc-patch.xml ];
then 
  rm ~/crc-patch.xml
  touch ~/crc-patch.xml
else
  touch ~/crc-patch.xml
fi 

echo '    </disk>' >  ~/crc-patch.xml 
for  (( i = 1; i <= $VOLUME_COUNT; i++ ))
do
  echo ${virtual_drive[$i]}
  address_bus=$(($BUS + $i + 1)) 

sudo tee -a ~/crc-patch.xml > /dev/null <<EOT
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='$HOME/.crc/${virtual_drive[$i]}' index='$i'/>
      <backingStore/>
      <target dev='${virtual_drive[$i]}' bus='virtio'/>
      <alias name='virtio-disk$i'/>
      <address type='pci' domain='0x0000' bus='0x0${address_bus}' slot='0x00' function='0x0'/>
    </disk>
EOT
done

cp ~/crc.xml ~/crc-backup.xml

line=$(grep -n '</disk>' ~/crc.xml | cut -d ":" -f 1)
line=$(grep -n '</disk>' ~/crc.xml | cut -d ":" -f 1)
{ head -n $(($line-1)) ~/crc.xml; cat ~/crc-patch.xml; tail -n +$(($line+1)) ~/crc.xml; } > ~/crc-mod.xml
cat  ~/crc-mod.xml
sed -i "s|~|$HOME|g" ~/crc-mod.xml
sudo virsh define ~/crc-mod.xml || exit $?

read -p "Would you like to start CRC? (y/n)" -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]]
then
    crc start
fi

echo "Block creation validation"
crcssh lsblk

echo "To restore configutation run the following."
echo "$ sudo virsh define ~/crc-backup.xml"
echo "$ crc start "