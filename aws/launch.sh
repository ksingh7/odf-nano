#!/bin/bash
#set -x
REGION=$(aws configure get region)
SPOTPRICE=$1
# aws ec2 describe-spot-price-history --start-time=$(date +%s) --instance-types c5n.metal --product-descriptions="Linux/UNIX"
#SPOTPRICE=0.016
KEY_NAME=ksingh-mumbai
INSTANCE_TYPE=c5n.metal # c5n.metal , t3.medium
AWS_ACCOUNT_NUMBER=903134789966

if [ -n "$SPOTPRICE" ]; then
    echo ""
else
    echo "Error : SPOT Price missing , please provide SPOT price"
    echo "------- You can run the below command to get spot price history ------- "
    echo 'aws ec2 describe-spot-price-history --start-time=$(date +%s) --instance-types c5n.metal --product-descriptions="Linux/UNIX"'
    exit 1
fi

echo "Creating IAM Role ..."
aws iam create-role --role-name crc-ec2-volume-role --assume-role-policy-document file://assets/EC2-Trust.json  > /dev/null 2>&1

echo "Adding policy to IAM Role ..."
aws iam put-role-policy --role-name crc-ec2-volume-role --policy-name crc-ec20-volume-policy --policy-document file://assets/iam-instance-role-ec2-volume-policy.json > /dev/null 2>&1

echo "Creating Instance Profile ..."
aws iam create-instance-profile --instance-profile-name crc-Instance-Profile  > /dev/null 2>&1

echo "Adding Role to Instance Profile ..."
aws iam add-role-to-instance-profile --instance-profile-name crc-Instance-Profile --role-name crc-ec2-volume-role > /dev/null 2>&1

echo "Creating Security Group ..."
SG_ID=$(aws ec2 create-security-group --group-name crc-sg --description "CRC Security Group" --tag-specifications 'ResourceType=security-group,Tags=[{Key="environment",Value="crc"}]'  | jq -r .GroupId)
for PORT in 22 80 443 6443 ; do aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port $PORT --cidr '0.0.0.0/0' ; done

## Todo - Improve this
echo "Generating Launch Specification file ..."
SG_ID=sg-060dd2842db31f58a
sed 's/SG_ID/'$SG_ID'/' assets/spot-instance-specification-template.json > assets/spot-instance-specification.json
sed -i ' ' 's/KEY_NAME/'$KEY_NAME'/' assets/spot-instance-specification.json
sed -i ' ' 's/INSTANCE_TYPE/'$INSTANCE_TYPE'/' assets/spot-instance-specification.json
sed -i ' ' 's/AWS_ACCOUNT_NUMBER/'$AWS_ACCOUNT_NUMBER'/' assets/spot-instance-specification.json

echo "Launching SPOT Instance, Please Wait ..."
aws ec2 request-spot-instances --availability-zone-group $REGION --spot-price $SPOTPRICE --instance-count 1 --type "one-time" --launch-specification file://assets/spot-instance-specification.json  --tag-specifications 'ResourceType=spot-instances-request,Tags=[{Key="environment",Value="crc"}]' 
rm assets/spot-instance-specification.json
sleep 30

echo "Please allow 5 minutes for instance configuration"
