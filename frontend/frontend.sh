#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
trap 'log ERROR "Failed at line $LINE " ' ERR

# --- LOG section
LOG_DIR="/var/log/mangodb_logs"
LOG_FILE="$(date +'%Y-%B-%d-%A_%H-%M-%S').log"
LOG_PATH="${LOG_DIR}/${LOG_FILE}"
LOG_LEVEL="INFO"
declare -A LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
# Get the directory where the script is actually located
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
MONGODB_HOST="mongodb.dasarikrishna.online"
# --- Variables
SUCCESS_CODE=0

# --- Functions
function log() {
    local level="$1"; shift
    local msg="$*"
    [[ ${LEVELS[$level]} -ge ${LEVELS[$LOG_LEVEL]} ]] || return
    local line="$(date '+%F %T') [$level] $msg"
    echo "$line" | tee -a "$LOG_PATH"
    logger -t my_script "$line"
}

function validate_exit_code(){

    # -- received Previoues command exit statue in $1 and  message in $2
    if (( $1 == SUCCESS_CODE ));then
        echo -e " $2 .. SUCESS"
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

# --- check user id if non-root user exit script
user_id=$(id -u)
if [[ $user_id -eq 0 ]];then
    log INFO "USER is root"
else
    log INFO "USER is not root, so Exiting Script"
    exit 1
fi


log INFO "Enabling nginx version 1.24"
dnf module enable nginx:1.24 -y

log INFO "Installing nginx package"
dnf install nginx -y

log INFO "Enabling nginx service"
systemctl enable nginx

log INFO "starting nginx service"
systemctl start nginx 

log INFO "removing the content from  nginx/html"
rm -rf /usr/share/nginx/html/* 

log INFO "download frontend code"
curl -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip

log INFO "unzip the nginx code"
cd /usr/share/nginx/html 
unzip /tmp/frontend.zip

log INFO "cp nginx.conf to /etc/nginx/"
cp "${SCRIPT_DIR}/nginx.conf" /etc/nginx/nginx.conf

