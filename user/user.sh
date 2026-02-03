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


log INFO "enabling nodejs version"
log_cmd dnf module disable nodejs -y

log INFO "installing nodejs version"
log_cmd dnf install nodejs -y

log INFO "check and add roboshop user"
if ! id roboshop ; then
    log INFO "roboshop user not exit, so adding"
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop
else
    log INFO " roboshop user alread exist , so skipping"
fi

log INFO "creating application directory"
mkdir -p /app

log INFO "removing code from app directory"
rm -rf /app/*

log INFO "downloading and unzipping user code"
log_cmd curl -L -o /tmp/user.zip https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip 
cd /app 
log_cmd unzip /tmp/user.zip

log INFO "installing npm packages"
cd /app 
log_cmd npm install 

log INFO "copy user service file to /etc/systemd/system/user.service"
cp "${SCRIPT_DIR}/user.service" /etc/systemd/system/user.service

log INFO "reload daemon"
systemctl daemon-reload

log INFO "enable and start service"
systemctl enable user 
systemctl start user