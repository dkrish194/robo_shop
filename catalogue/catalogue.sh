#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
trap '"log ERROR Failed at line $LINE "' ERR

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
# Get the directory where the script is actually located
#SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
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


# --- enabling nodejs version 20
if dnf module enable nodejs:20 -y ;then
    log INFO "Enabled Nodejs version 20"
fi

if dnf install nodejs -y ; then
    log INFO "Installed Nodejs package"
fi


# --- add user if not exist
if ! id roboshop ;then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop
    log INFO "Added USER roboshop"
else    
     log INFO "USER roboshop already exist so skipping to add again"
fi

# --- create directory to place code
mkdir -p /app
log INFO "created app directory"

log INFO "remove /app data before download code"
rm -rf /app/*

log INFO "downloading and unziping the code into app directory"
curl -o /tmp/catalogue.zip https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip 
cd /app 
unzip /tmp/catalogue.zip
cd /app 

log INFO "Installing npm packages"

if npm install &>> /dev/null ; then
    log INFO "Installed Packages"
fi

# --- copy service to systemd
log INFO "SCRIPT DIR: $SCRIPT_DIR "
cp "${SCRIPT_DIR}/catalogue.service" /etc/systemd/system/catalogue.service

log INFO "systemctl daemon relaod"
systemctl daemon-reload


log INFO "Enable and start service"
if ! systemctl enable catalogue ; then
    log INFO "Enabling catalogue service"
    systemctl enable catalogue
else
    log INFO "cataloue service already enabled .. skipping"
fi

if ! systemctl is-active catalogue ; then
    log INFO "starting catalogue service"
    systemctl start catalogue
else
    log INFO "cataloue service already started .. skipping"
fi


# --- copy monodb repo
cp "${SCRIPT_DIR}/mongo.repo" /etc/yum.repos.d/mongo.repo

# --- installing mongodb package
# --- install mongodb package if not installed
if ! rpm -q mongodb-mongosh &>/dev/null; then
    log INFO "Installing mongodb-mongosh package"
    dnf install -y mongodb-mongosh
    log INFO "mongodb-mongosh package installed"
else
    log INFO "mongodb-mongosh package already installed, skipping"
fi

INDEX=$(mongosh --host $MONGODB_HOST --quiet  --eval 'db.getMongo().getDBNames().indexOf("catalogue")')

if [[ $INDEX -le 0 ]]; then
    mongosh --host $MONGODB_HOST </app/db/master-data.js
    validate_exit_code $? "Loading products"
else
    echo -e "Products already loaded ...  SKIPPING "
fi

systemctl restart catalogue
log INFO "Restarting catalogue service"
