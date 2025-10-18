#!/bin/bash

# Set region where AMI is available
export AWS_DEFAULT_REGION=us-east-1

# Use verified AMI
AMI_ID="ami-09c813fb71547fc4f"
SG_ID="sg-01c6441a49a9f3d18"
SUBNET_ID="subnet-0b439d8814bf5d584"
INSTANCES=("mongodb" "redis" "mysql" "rabbitmq" "catalogue" "user" "cart" "shipping" "payment" "dispatch" "frontend")
ZONE_ID="Z04937802OYFAGU4M6BTX"
DOMAIN_NAME="trinath.online"

for instance in "${INSTANCES[@]}"
do
  echo "Launching $instance..."

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
    --query "Instances[0].InstanceId" \
    --output text)

  if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Failed to launch $instance. Skipping DNS record creation."
    continue
  fi

  echo "Waiting for $instance to initialize..."
  aws ec2 wait instance-running --instance-ids $INSTANCE_ID

  if [ "$instance" != "frontend" ]; then
    IP=$(aws ec2 describe-instances \
      --instance-ids $INSTANCE_ID \
      --query "Reservations[0].Instances[0].PrivateIpAddress" \
      --output text)
    RECORD_NAME="$instance.$DOMAIN_NAME"
  else
    IP=$(aws ec2 describe-instances \
      --instance-ids $INSTANCE_ID \
      --query "Reservations[0].Instances[0].PublicIpAddress" \
      --output text)
    RECORD_NAME="$DOMAIN_NAME"
  fi

  if [ "$IP" == "None" ] || [ -z "$IP" ]; then
    echo "Could not fetch IP for $instance. Skipping DNS record creation."
    continue
  fi

  echo "$instance IP address: $IP"

  aws route53 change-resource-record-sets \
    --hosted-zone-id $ZONE_ID \
    --change-batch '{
      "Comment": "Creating or Updating a record set for '$instance'",
      "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "'$RECORD_NAME'",
          "Type": "A",
          "TTL": 1,
          "ResourceRecords": [{
            "Value": "'$IP'"
          }]
        }
      }]
    }'
done
