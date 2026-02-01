#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
trap 'log ERROR "Failed at line $LINE " ' ERR

# --- LOG section
LOG_DIR="logs"
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
    echo "$line" | tee -a "$LOG_FILE"
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


log INFO "Copying mongodb repo to /etc/yum.repos.d"
cp mongodb.repo /etc/yum.repos.d/mongo.repo

log INFO "Installing mongodb package"
dnf install mongodb-org -y 
sleep 1
validate_exit_code "$?" "MONGODB PACKAGE INSTALLATION"

# -- enable & start monogdb service
systemctl enable mongod
sleep 1
systemctl start mongod
validate_exit_code "$?" "START MONGOD SERVICE"

# --- change local host ip address to 0.0.0.0
sed -i 's/127.0.0.1/0.0.0.0' /etc/mongod.cnonf
validate_exit_code "$?" "Updated Localhost to 0.0.0.0"


# --- restart monogod service
systemctl restart mongod
validate_exit_code "$?" "RE-START MONGOD SERVICE"




