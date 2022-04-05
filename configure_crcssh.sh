#!/bin/bash 

if grep -q "crcssh=" ~/.bash_aliases 
then 
   echo "crcssh already exists in ~/.bash_aliases "
else
   echo "alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@`crc ip`'" >>  ~/.bash_aliases 
fi
