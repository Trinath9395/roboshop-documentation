#!/bin/bash

# 🔍 Dynamically fetch AMI ID from Community AMI
AMI_ID=$(aws ec2 describe-images \
  --owners 658775564324 \
  --filters "Name=name,Values=RHEL-9-DevOps-Practice" "Name=virtualization-type,Values=hvm" \
  --query "Images[0].ImageId" \
  --output text)

if [ "$AMI_ID" == "None" ] || [ -z "$AMI_ID" ]; then
  echo "❌ Failed to fetch AMI ID. Check if the AMI exists in your region."
  exit 1
fi

# 🔧 Configurable parameters
SG_ID="sg-01c6441a49a9f3d18"
SUBNET_ID="subnet-0b439d8814bf5d584"
INSTANCES=("mongodb" "redis" "mysql" "rabbitmq" "catalogue" "user" "cart" "shipping" "payment" "dispatch" "frontend")
ZONE_ID="Z04937802OYFAGU4M6BTX"
DOMAIN_NAME="trinath.online"

# 🚀 Launch and configure each instance
for instance in "${INSTANCES[@]}"
do
  echo "Launching $instance..."

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
    --query "Instances[0].InstanceId" \
    --output text)

  if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "❌ Failed to launch $instance. Skipping DNS record creation."
    continue
  fi

  # 🧠 Wait for instance to initialize
  echo "Waiting for $instance to initialize..."
  aws ec2 wait instance-running --instance-ids $INSTANCE_ID

  # 🌐 Fetch IP address
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
    echo "⚠️ Could not fetch IP for $instance. Skipping DNS record creation."
    continue
  fi

  echo "$instance IP address: $IP"

  # 🛠️ Create or update Route53 DNS record
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
