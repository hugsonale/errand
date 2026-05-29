#!/bin/bash
# Errand Marketplace — AWS Production Setup Script
# Run once to bootstrap the production infrastructure
# Prerequisites: AWS CLI configured, key pair created

set -euo pipefail

# ─── CONFIG (edit these) ───────────────────────────────────────────────────────
APP_NAME="errand-marketplace"
REGION="eu-west-1"                    # Lagos latency: eu-west-1 (Ireland) or af-south-1 (Cape Town)
KEY_PAIR_NAME="errand-marketplace-key"
EC2_INSTANCE_TYPE="t3.medium"
RDS_INSTANCE_TYPE="db.t3.small"
DOMAIN="api.errandmarketplace.com"

# ─── COLORS ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

log() { echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

log "Starting Errand Marketplace AWS deployment..."

# ─── VPC & NETWORKING ─────────────────────────────────────────────────────────

log "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --region $REGION \
    --query 'Vpc.VpcId' \
    --output text)
aws ec2 create-tags --resources $VPC_ID --tags "Key=Name,Value=${APP_NAME}-vpc" --region $REGION
log "VPC created: $VPC_ID"

# Public subnets (2 AZs for HA)
SUBNET_PUB_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone "${REGION}a" \
    --query 'Subnet.SubnetId' --output text --region $REGION)

SUBNET_PUB_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone "${REGION}b" \
    --query 'Subnet.SubnetId' --output text --region $REGION)

# Private subnets for RDS/ElastiCache
SUBNET_PRI_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.10.0/24 \
    --availability-zone "${REGION}a" \
    --query 'Subnet.SubnetId' --output text --region $REGION)

SUBNET_PRI_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.11.0/24 \
    --availability-zone "${REGION}b" \
    --query 'Subnet.SubnetId' --output text --region $REGION)

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --output text --region $REGION)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION

# Route table for public subnets
RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text --region $REGION)
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_1 --region $REGION
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_2 --region $REGION

log "Networking configured"

# ─── SECURITY GROUPS ──────────────────────────────────────────────────────────

# App server security group
APP_SG=$(aws ec2 create-security-group \
    --group-name "${APP_NAME}-app-sg" \
    --description "Errand Marketplace App Server" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text --region $REGION)

aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION

# DB security group (only reachable from app)
DB_SG=$(aws ec2 create-security-group \
    --group-name "${APP_NAME}-db-sg" \
    --description "Errand Marketplace Database" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 5432 --source-group $APP_SG --region $REGION

# Redis security group
REDIS_SG=$(aws ec2 create-security-group \
    --group-name "${APP_NAME}-redis-sg" \
    --description "Errand Marketplace Redis" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $REDIS_SG --protocol tcp --port 6379 --source-group $APP_SG --region $REGION

log "Security groups created"

# ─── S3 BUCKET ────────────────────────────────────────────────────────────────

BUCKET_NAME="${APP_NAME}-media-$(date +%s)"
aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION

# Block all public access (presigned URLs only)
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Lifecycle rule — delete temp files after 30 days
aws s3api put-bucket-lifecycle-configuration \
    --bucket $BUCKET_NAME \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "delete-old-temp",
            "Filter": {"Prefix": "temp/"},
            "Status": "Enabled",
            "Expiration": {"Days": 30}
        }]
    }'

log "S3 bucket created: $BUCKET_NAME"

# ─── RDS POSTGRESQL ───────────────────────────────────────────────────────────

DB_SUBNET_GROUP="${APP_NAME}-db-subnet-group"
aws rds create-db-subnet-group \
    --db-subnet-group-name $DB_SUBNET_GROUP \
    --db-subnet-group-description "Errand Marketplace DB Subnet Group" \
    --subnet-ids $SUBNET_PRI_1 $SUBNET_PRI_2 \
    --region $REGION

DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

aws rds create-db-instance \
    --db-instance-identifier "${APP_NAME}-postgres" \
    --db-instance-class $RDS_INSTANCE_TYPE \
    --engine postgres \
    --engine-version "16.2" \
    --master-username errand_user \
    --master-user-password "$DB_PASSWORD" \
    --db-name errand_marketplace \
    --allocated-storage 20 \
    --storage-type gp3 \
    --storage-encrypted \
    --vpc-security-group-ids $DB_SG \
    --db-subnet-group-name $DB_SUBNET_GROUP \
    --backup-retention-period 7 \
    --no-publicly-accessible \
    --deletion-protection \
    --region $REGION

log "RDS instance created (takes ~10 min to be available)"
log "DB Password: $DB_PASSWORD  ← SAVE THIS"

# ─── EC2 INSTANCE ─────────────────────────────────────────────────────────────

# User data script — runs on first boot
USER_DATA=$(cat << 'USERDATA'
#!/bin/bash
set -e

# Update and install Docker
apt-get update -y
apt-get install -y docker.io docker-compose-plugin git curl certbot

# Start Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Clone repo (replace with your actual repo)
cd /opt
git clone https://github.com/YOUR_ORG/errand-marketplace.git
cd errand-marketplace

# Create env file placeholder
mkdir -p /etc/errand
echo "# Configure .env before starting" > /etc/errand/.env

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install

echo "✅ EC2 bootstrap complete. Configure .env then run: docker-compose -f docker-compose.prod.yml up -d"
USERDATA
)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id ami-0905a3c97561e0b69 \
    --instance-type $EC2_INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --security-group-ids $APP_SG \
    --subnet-id $SUBNET_PUB_1 \
    --associate-public-ip-address \
    --user-data "$USER_DATA" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}-server}]" \
    --query 'Instances[0].InstanceId' \
    --output text --region $REGION)

log "EC2 instance launched: $INSTANCE_ID"

# Wait for instance
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text --region $REGION)

log "Instance public IP: $PUBLIC_IP"

# ─── OUTPUT SUMMARY ──────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════"
echo "  ERRAND MARKETPLACE — DEPLOYMENT SUMMARY"
echo "════════════════════════════════════════════════════"
echo ""
echo "  VPC:         $VPC_ID"
echo "  EC2:         $INSTANCE_ID ($PUBLIC_IP)"
echo "  S3 Bucket:   $BUCKET_NAME"
echo ""
echo "  DB Password: $DB_PASSWORD"
echo ""
echo "  ⚠️  IMPORTANT NEXT STEPS:"
echo ""
echo "  1. Point DNS: $DOMAIN → $PUBLIC_IP"
echo ""
echo "  2. SSH to server:"
echo "     ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ubuntu@$PUBLIC_IP"
echo ""
echo "  3. Wait for RDS (~10min), then get endpoint:"
echo "     aws rds describe-db-instances --db-instance-identifier ${APP_NAME}-postgres"
echo "       --query 'DBInstances[0].Endpoint.Address' --output text"
echo ""
echo "  4. Edit /etc/errand/.env with your real values"
echo ""
echo "  5. Get SSL cert:"
echo "     sudo certbot certonly --standalone -d $DOMAIN"
echo ""
echo "  6. Start app:"
echo "     cd /opt/errand-marketplace"
echo "     docker-compose -f docker-compose.prod.yml up -d"
echo ""
echo "  7. Check health:"
echo "     curl https://$DOMAIN/health"
echo ""
echo "════════════════════════════════════════════════════"
