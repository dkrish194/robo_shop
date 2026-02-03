#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
trap '"log ERROR Failed at line $line "' ERR

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

echo -e "SCRIPT path : $SCRIPT_PATH"
echo -e "SCRIPT dir : $SCRIPT_DIR"

# --- LOG section
LOG_DIR="/var/log/mangodb_logs"
LOG_FILE="$(date +'%Y-%B-%d-%A_%H-%M-%S').log"
LOG_PATH="${LOG_DIR}/${LOG_FILE}"
LOG_LEVEL="INFO"
declare -A LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

# --- Variables
SUCCESS_CODE=0
MYSQL_HOST="mysql.dasarikrishna.online"

# --- Functions
function log() {
    local level="$1"; shift
    local msg="$*"
    [[ ${LEVELS[$level]} -ge ${LEVELS[$LOG_LEVEL]} ]] || return
    local line="$(date '+%F %T') [$level] $msg"
    echo "$line" | tee -a "$LOG_PATH"
    logger -t my_script "$line"
}
function log_cmd() {
    "$@" >>"$LOG_PATH" 2>&1
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


log "installing python packages"
log_cmd dnf install python3 gcc python3-devel -y

log "checking and add user if not exist"
if ! id roboshop ; then 
    log "roboshop user not exist ,so adding"
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop
else
    log "roboshop user already exist so skipping"
fi

log "creating application directory"
mkdir -p /app

log "removing code from app directory"
rm -rf /app/*

log "downloading and unzipping payment code"
curl -L -o /tmp/payment.zip https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip 
cd /app 
unzip /tmp/payment.zip

log "install packages from requirment"

cd /app 
log_cmd pip3 install -r requirements.txt

log "copy payment service file to /etc/systemd/system/payment.service"
cp "${SCRIPT_DIR}/payment.service" /etc/systemd/system/payment.service

log "reload daemon"
systemctl daemon-reload

log "enable and start service"
systemctl enable payment 
systemctl start payment