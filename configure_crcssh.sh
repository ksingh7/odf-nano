#!/bin/bash 

echo "alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@`crc ip`'" >>  ~/.bash_aliases 