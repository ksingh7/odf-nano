#!/bin/bash
function configure_crc(){
    crc config set consent-telemetry no
    crc config set enable-cluster-monitoring true 
    crc config set cpus ${1} 
    crc config set memory ${2} 
    crc config view
}

read -p "Reconfigure CPUs Example: 15 > " CPU_COUNT
read -p "Reconfigure Memory size in MB Example: 60000 > " VOLUME_SIZE



CRC_STATUS=$(crc status | grep "CRC VM:" | awk '{print $3}')

if [ ${CRC_STATUS} == "Running" ];
then 
    crc stop 
    configure_crc ${CPU_COUNT} ${VOLUME_SIZE} 
else 
    configure_crc ${CPU_COUNT} ${VOLUME_SIZE} 
fi 


read -p "Would you like to start CRC? (y/n)" -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]]
then
    crc start
    echo "Block creation validation"
    crcssh lsblk

    echo "To restore configutation run the following."
    echo "$ sudo virsh define ~/crc-backup.xml"
    echo "$ crc start "
fi


