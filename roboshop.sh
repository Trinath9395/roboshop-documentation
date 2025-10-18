#!/bin/bash

AMI_ID="ami-09c813fb71547fc4f"
VPC_ID="vpc-0c973999712c8fb25"
SG_ID="sg-01c6441a49a9f3d18" # replace with your SG ID
SUBNET_ID="subnet-0b439d8814bf5d584" # ✅ added usage below
INSTANCES=("mongodb" "redis" "mysql" "rabbitmq" "catalogue" "user" "cart" "shipping" "payment" "dispatch" "frontend")
ZONE_ID="Z04937802OYFAGU4M6BTX" # replace with your ZONE ID
DOMAIN_NAME="trinath.online" # replace with your domain

for instance in "${INSTANCES[@]}"
#for instance in $@
do
    # ✅ Added --subnet-id and variable references
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type t2.micro \
        --security-group-ids $SG_ID \
        --subnet-id $SUBNET_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
        --query "Instances[0].InstanceId" \
        --output text)

    echo "Launched $instance with Instance ID: $INSTANCE_ID"

    # ✅ Wait for instance to be running before getting IP
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    if [ "$instance" != "frontend" ]
    then
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
        RECORD_NAME="$instance.$DOMAIN_NAME"
    else
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
        RECORD_NAME="$DOMAIN_NAME"
    fi

    echo "$instance IP address: $IP"

    # ✅ Skip if IP is empty or None
    if [[ -z "$IP" || "$IP" == "None" ]]; then
        echo "⚠️ Skipping Route53 record for $instance — no valid IP found."
        continue
    fi

    aws route53 change-resource-record-sets \
    --hosted-zone-id $ZONE_ID \
    --change-batch "
    {
        \"Comment\": \"Creating or Updating record set for $instance\",
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"$RECORD_NAME\",
                \"Type\": \"A\",
                \"TTL\": 60,
                \"ResourceRecords\": [{\"Value\": \"$IP\"}]
            }
        }]
    }"
done
