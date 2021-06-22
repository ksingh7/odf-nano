#!/bin/bash

echo "Terminating up Spot Instance ..."
EC2_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=instance-type,Values=t3.medium" "Name=instance-state-code,Values=16" --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --output text)
aws ec2 terminate-instances --instance-ids $EC2_INSTANCE_ID > /dev/null 2>&1

echo "Destroying EBS Volume ..."
EBS_VOLUME_ID=$(aws  ec2 describe-volumes --filters "Name=tag:environment,Values=crc" --query "Volumes[*].{ID:VolumeId}" --output text)

aws ec2 delete-volume --volume-id $EBS_VOLUME_ID > /dev/null 2>&1

echo "Removing Role from Instance Profile ... [Done]"
aws iam remove-role-from-instance-profile --instance-profile-name crc-Instance-Profile --role-name crc-ec2-volume-role > /dev/null 2>&1

echo "Deleting Role Policy ... [Done]"
aws iam delete-role-policy --role-name crc-ec2-volume-role --policy-name crc-ec20-volume-policy > /dev/null 2>&1

echo "Deleting Role ... [Done]"
aws iam delete-role --role-name crc-ec2-volume-role > /dev/null 2>&1

echo "Deleting Instance Profile ... [Done]"
aws iam delete-instance-profile --instance-profile-name crc-Instance-Profile > /dev/null 2>&1

echo "Deleting Security Group... [Done]"
sleep 10
aws ec2 delete-security-group --group-name crc-sg
#SG_ID=$(aws ec2 describe-security-groups --filter "Name=tag:environment,Values=crc" --query 'SecurityGroups[*].[GroupId]' --output text)
