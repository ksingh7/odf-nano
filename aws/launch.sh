#!/bin/bash
#bash launch.sh ap-south-1 ap-south-1a true 
# aws ec2 describe-spot-price-history --start-time=$(date +%s) --instance-types c5n.metal --product-descriptions="Linux/UNIX"

#SPOTPRICE=$1
REGION=$1
AZ_NAME=$2
DEBUG=$3

KEY_PAIR_NAME="crc-key-pair"
#PUB_KEY_PATH =" "
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query "Account" --output text)
INSTANCE_TYPE=c5n.metal  #cheapest x86 baremetal instance from AWS
AMI_ID=ami-01d3bd808e1fd393c

if [ "$DEBUG" == "true"  ]; then
    set -x
fi

# if [ -n "$SPOTPRICE" ]; then
#     echo "Launching instance with SPOT PRICE of : "$"$REGION ..."
# else
#     echo "Error : SPOT Price missing , please provide SPOT price"
#     echo "------- You can run the below command to get spot price history ------- "
#     echo 'aws ec2 describe-spot-price-history --start-time=$(date +%s) --instance-types $INSTANCE_TYPE --product-descriptions="Linux/UNIX"'
#     exit 1
# fi

if [ -n "$REGION" ]; then
    echo "Launching instance in Region : $REGION ..."
else
    REGION=$(aws configure get region)
    echo "No Region provided, launching instance in Region : $REGION ..."
fi

if [ -n "$AZ_NAME" ]; then
    echo "Launching instance in AZ : $AZ_NAME ..."
else
    AZ_NAME="$REGION"c
    echo "No AZ provided, launching instance in AZ : $AZ_NAME ..."

fi

if [ -z $PUB_KEY_PATH ]; then
    echo "Please provide SSH Public Key absolute path to create AWS Key Pair in the selected Region (ex: <HOME_DIR>/.ssh/id_rsa.pub) : "
    read PUB_KEY_PATH
    if [ -a  $PUB_KEY_PATH ]; then
        aws --region $REGION ec2 import-key-pair --key-name $KEY_PAIR_NAME --tag-specifications 'ResourceType=key-pair,Tags=[{Key="environment",Value="crc"}'--public-key-material fileb://$PUB_KEY_PATH  > /dev/null 2>&1
        echo "New key-pair named "$KEY_PAIR_NAME" created in region "$REGION"..."
    else
        echo "Invalid SSH Public Key path or Key file does not exists ... exiting"
        exit 1
    fi
fi

if [[ "$IS_IAM_ROLE_EXISTS" == "crc-ec2-volume-role" ]]; then
    echo "IAM Role, Policy, Instance Profile, Already Exists, Skipping ..."
else
    echo "Creating IAM Role ..."
    aws iam create-role --role-name crc-ec2-volume-role --assume-role-policy-document file://assets/EC2-Trust.json  > /dev/null 2>&1
    echo "Adding policy to IAM Role ..."
    aws iam put-role-policy --role-name crc-ec2-volume-role --policy-name crc-ec20-volume-policy --policy-document file://assets/iam-instance-role-ec2-volume-policy.json > /dev/null 2>&1
    echo "Creating Instance Profile ..."
    aws iam create-instance-profile --instance-profile-name crc-Instance-Profile  > /dev/null 2>&1
    echo "Adding Role to Instance Profile ..."
    aws iam add-role-to-instance-profile --instance-profile-name crc-Instance-Profile --role-name crc-ec2-volume-role > /dev/null 2>&1
fi

IS_SG_EXISTS=$(aws ec2 describe-security-groups --filters "Name=tag:environment,Values=crc" --query "SecurityGroups[*].{Name:GroupName}" --output text)

if [[ "$IS_SG_EXISTS" == "crc-sg" ]]; then
    echo "Security Group Already Exists, Skipping ..."
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=tag:environment,Values=crc" --query "SecurityGroups[*].{Name:GroupId}" --output text)
else
    echo "Creating Security Group ..."
    SG_ID=$(aws ec2 create-security-group --group-name crc-sg --description "CRC Security Group" --tag-specifications 'ResourceType=security-group,Tags=[{Key="environment",Value="crc"}]'  | jq -r .GroupId)
    for PORT in 22 80 443 6443 ; do aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port $PORT --cidr '0.0.0.0/0' ; done
fi

echo "Generating User-Data script file ..."
sed 's/REGION/'$REGION'/g' assets/user-data-template.sh > assets/user-data.sh
sed -i ' ' 's/AZ_NAME/'$AZ_NAME'/g' assets/user-data.sh
sed -i ' ' 's/INSTANCE_TYPE/'$INSTANCE_TYPE'/g' assets/user-data.sh
USER_DATA_BASE_64=$(base64 assets/user-data.sh)

## Todo - Improve this
echo "Generating Launch Specification file ..."
sed 's/SG_ID/'$SG_ID'/' assets/spot-instance-specification-template.json > assets/spot-instance-specification.json
sed -i ' ' 's/KEY_PAIR_NAME/'$KEY_PAIR_NAME'/' assets/spot-instance-specification.json
sed -i ' ' 's/INSTANCE_TYPE/'$INSTANCE_TYPE'/' assets/spot-instance-specification.json
sed -i ' ' 's/AWS_ACCOUNT_NUMBER/'$AWS_ACCOUNT_NUMBER'/' assets/spot-instance-specification.json
sed -i ' ' 's/USER_DATA_BASE_64/'$USER_DATA_BASE_64'/' assets/spot-instance-specification.json
sed -i ' ' 's/AZ_NAME/'$AZ_NAME'/' assets/spot-instance-specification.json
sed -i ' ' 's/AMI_ID/'$AMI_ID'/' assets/spot-instance-specification.json

echo "Launching SPOT Instance, Please Wait ..."
sleep 10
aws ec2 request-spot-instances --availability-zone-group $REGION  --instance-count 1 --type "one-time" --launch-specification file://assets/spot-instance-specification.json  --tag-specifications 'ResourceType=spot-instances-request,Tags=[{Key="environment",Value="crc"}]'  > /dev/null 2>&1
rm assets/spot-instance-specification.json
rm assets/user-data.sh

sleep 60

SPOT_REQUEST_OUTPUT=$(aws ec2 describe-spot-instance-requests  --filters "Name=state,Values=open,active" "Name=tag:environment,Values=crc" "Name=availability-zone-group,Values=$REGION") 
#echo $SPOT_REQUEST_ID
echo "Please allow 5 minutes for instance configuration"

sleep 180

EIP=$(aws ec2 describe-instances --filters "Name=instance-type,Values=$INSTANCE_TYPE" "Name=availability-zone,Values=$AZ_NAME" --query "Reservations[*].Instances[*].PublicIpAddress" --output=text)

ssh  fedora@$EIP tail -50f /var/log/crc_setup.log