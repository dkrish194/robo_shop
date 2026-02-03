#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
trap 'log ERROR "Failed at line $LINENO"' ERR

# --- LOG Section
LOG_DIR="aws_logs"
LOG_FILE="$(date +'%Y-%B-%d-%A_%H-%M-%S').log"
LOG_PATH="${LOG_DIR}/${LOG_FILE}"
LOG_LEVEL="INFO"
declare -A LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

# ---- Varibles
AMI_ID="ami-0220d79f3f480ecf5"
SECURITY_GROUP="sg-02a6e8c9e38480783"
SUCCESS_CODE=0
DOMAIN_NAME="dasarikrishna.online"
HOSTED_ZONE="Z08579941T4CEU56ALPQS"
#FAILURE=1

# --- Functions
function log() {
    local level="$1"; shift
    local msg="$*"
    [[ ${LEVELS[$level]} -ge ${LEVELS[$LOG_LEVEL]} ]] || return
    local line="$(date '+%F %T') [$level] $msg"
    echo "$line" | tee -a "$LOG_FILE"
    logger -t my_script "$line"
}

function validate_exit_code(){

    # -- received Previoues command exit statue in $1 and  message in $2
    if (( $1 == SUCCESS_CODE ));then
        echo -e " $2 .. SUCCESS"
    else
        echo -e " $2 .. FAILURE"
    fi
}

# --- creating Log Directory and log file
mkdir -p $LOG_DIR
touch "$LOG_PATH"

log INFO    "LOG_DIR : $LOG_DIR"
log INFO    "LOG_FILE : $LOG_FILE"
log INFO    "LOG_PATH : $LOG_PATH"


if (( $# == 0 ));then
    echo -e "given wrong input , please pass arguemnts like  ./script <arg1> <arg2> .. <arg N>"
else
    echo -e "number of arguemnts $# "

    for arg in "$@" ; do
        echo -e " Given arguemnts : \t $arg"
    done
fi



for instance in "$@"; do
    echo -e "creating instance for $instance"
    INSTANCE_ID=$( aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type t3.micro \
        --security-group-ids $SECURITY_GROUP \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text )

        echo "krishna INSTANCE_ID: $INSTANCE_ID"

    validate_exit_code $? "create EC2 instance"
    log INFO "INSTANCE ID: $INSTANCE_ID "
    sleep 2
        # Defensive trim (one-liner, very important)
    echo -e "BEFORE remove: $INSTANCE_ID"
    INSTANCE_ID="${INSTANCE_ID//$'\n'/}"
    echo -e "AFTER remove: $INSTANCE_ID"

    echo "Instance ID: $INSTANCE_ID"

    # ✅ WAIT properly (THIS IS THE KEY FIX)
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
    validate_exit_code $? "wait for instance running"

    # - get private ip or public ip based on aws instance name
    
        PUBLIC_IP_ADDRESS=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text)
        echo -e "PUBLIC_IP is : $PUBLIC_IP_ADDRESS"
        PRIVATE_IP_ADDRESS=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[].Instances[].PrivateIpAddress' \
            --output text)
        echo -e "PRIVATE_IP is : $PRIVATE_IP_ADDRESS"
    if [[ $instance == "frontend" ]];then
        SUB_DOMAIN_NAME="$DOMAIN_NAME"
        log INFO "sub domain name: $SUB_DOMAIN_NAME"
    else
        SUB_DOMAIN_NAME="${instance}.$DOMAIN_NAME"
        log INFO "sub domain name: $SUB_DOMAIN_NAME"


    fi

    cat > record.json <<EOF
    {
    "Comment": "DNS update via bash",
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
        "Name": "$SUB_DOMAIN_NAME",
        "Type": "A",
        "TTL": 1,
        "ResourceRecords": [{ "Value": "$PRIVATE_IP_ADDRESS" }]
        }
                }]
    }
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE" \
        --change-batch file://record.json

    validate_exit_code $? "Added Route53 record"
    log INFO "SUB DOMAIN NAME: $SUB_DOMAIN_NAME "
    log INFO "PRIVATE IP: $PRIVATE_IP_ADDRESS"
    log INFO "PUBLIC IP: $PUBLIC_IP_ADDRESS"
    
done





rm -f record.json
echo -e " ------- SCRIPT ENDED -----------"
