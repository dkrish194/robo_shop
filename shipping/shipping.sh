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

log INFO "installing maven"
log_cmd dnf install maven -y

log INFO "checking and add user if not exist"
if ! id roboshop ; then 
    log INFO "roboshop user not exist ,so adding"
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop
else
    log INFO "roboshop user already exist so skipping"
fi

log INFO "creating application directory"
mkdir -p /app

log INFO "removing code from app directory"
rm -rf /app/*

log INFO "downloading and unzipping shipping code"
curl -L -o /tmp/shipping.zip https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip 
cd /app 
unzip /tmp/shipping.zip

log INFO "doing clean package and renaming tar file"
cd /app 
mvn clean package 
mv target/shipping-1.0.jar shipping.jar 

log INFO "copy shipping service file to /etc/systemd/system/shipping.service"
cp "${SCRIPT_DIR}/shipping.service" /etc/systemd/system/shipping.service

log INFO "reload daemon"
systemctl daemon-reload

log INFO "enable and start service"
systemctl enable shipping 
systemctl start shipping

log INFO "installing mysql package"
log_cmd dnf install mysql -y 

log INFO "checking mqsql daatabase if data not exist then load"
if ! mysql -h $MYSQL_HOST -uroot -pRoboShop@1 -e 'use cities'; then
    log INFO "data is not present in database , so Loading"
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/schema.sql 
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/app-user.sql 
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/master-data.sql
else
    log INFO "data is already present in database , so skipping"
fi

log INFO "restart shipping service"
systemctl restart shipping