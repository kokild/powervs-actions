#!/bin/bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "bye!"
    exit 1
}

SERVER_NAME=""
FINAL_SERVER_ID=""
PROGPATH=$(dirname $0)

# convert given seconds to HH:MM:SS
function sec2hms
{
    local HH MM SS sec
    if [[ $# -ne 1 ]]
    then
        echo "Usage: ${FUNCNAME[0]} <secs>"
        return 1
    fi
    sec=$1
    if [[ ! $sec =~ ^[0-9]+$ ]]
    then
        echo "Numerical value expected"
        echo "Usage: $0 <secs>"
        return 1
    fi
    HH=$((sec / (60 * 60) ))
    sec=$((sec - HH * 60 * 60))
    MM=$((sec / 60))
    if [[ ${#MM} -lt 2 ]]
    then
        MM=0$MM
    fi
    SS=$((sec - MM * 60))
    if [[ ${#SS} -lt 2 ]]
    then
        SS=0$SS
    fi
    echo $HH:$MM:$SS
}

function check_dependencies() {

    DEPENDENCIES=(ibmcloud jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v "$i" &> /dev/null; then
            echo "$i could not be found, exiting!"
            exit 1
        fi
    done
}

function check_connectivity() {

    if ! curl --output /dev/null --silent --head --fail http://cloud.ibm.com; then
        echo
        echo "ERROR: please, check your internet connection."
        exit 1
    fi
}

function authenticate() {
    
    local APY_KEY="$1"
    
    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit
    fi
    ibmcloud login --no-region --apikey $APY_KEY
}

function set_powervs() {
    
    local CRN="$1"
    
    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit 1
    fi
    ibmcloud pi st "$CRN"
}

function create_server () {

    local SERVER_ID=$1
    local SERVER_IMAGE=$2
    local PUBLIC_NETWORK=$3
    local SSH_KEY_NAME=$4

    # Default values.
    local SERVER_MEMORY=$5
    local SERVER_PROCESSOR=$6
    local SERVER_SYS_TYPE=$7

    local SSH_USER=$8

    echo "$(date +%Y-%m-%d" "%H:%M:%S): Creating VMName:$SERVER_NAME"
    ibmcloud pi instance-create "$SERVER_NAME" --image "$SERVER_IMAGE" --memory "$SERVER_MEMORY" \
        --network "$PUBLIC_NETWORK" --processors "$SERVER_PROCESSOR" --processor-type shared \
        --key-name "$SSH_KEY_NAME" --sys-type "$SERVER_SYS_TYPE" --json > $SERVER_ROOT/server.log 
    if head -1 $SERVER_ROOT/server.log | grep -q -w FAILED
    then
        sec_from_start=$((`date +%s` - START0))
        echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME Server create FAILED, time from start: $sec_from_start sec (`sec2hms $sec_from_start`)"
        return 1
    fi

    SERVER_ID=$(jq -r ".[].pvmInstanceID" < $SERVER_ROOT/server.log)
    SERVER_NAME=$(jq -r ".[].serverName" < $SERVER_ROOT/server.log)

    echo "$(date +%Y-%m-%d" "%H:%M:%S):  VMName:$SERVER_NAME was created with the ID: $SERVER_ID"
    FINAL_SERVER_ID=$SERVER_ID

    echo "SERVER_ID=$SERVER_ID" >> $SERVER_ROOT/server-build.log
    echo "SERVER_NAME=$SERVER_NAME" >> $SERVER_ROOT/server-build.log

    echo "$(date +%Y-%m-%d" "%H:%M:%S):  deploying the VMName:$SERVER_NAME, hold on please."
    STATUS=$(ibmcloud pi in "$SERVER_ID" --json | jq -r ".status")

    printf "%c" "    "
    while [[ "$STATUS" != "ACTIVE" && "$STATUS" != "ERROR" ]]
    do
        sleep 5s
        STATUS=$(ibmcloud pi in "$SERVER_ID" --json | jq -r ".status")
        printf "%c" "."
    done
    echo

    if [[ "$STATUS" == "ERROR" ]]; then
        echo "$(date +%Y-%m-%d" "%H:%M:%S): ERROR: VMName:$SERVER_NAME: a new VM could not be created, destroy the allocated resources..." | tee -a $SERVER_ROOT/server-build.log
        ibmcloud pi instance-delete "$SERVER_ID"
        return 1
    fi

    if [[ "$STATUS" == "ACTIVE" ]]; then
        sec_from_start=$((`date +%s` - START0))
        echo
        echo "$(date +%Y-%m-%d" "%H:%M:%S):  VMName:$SERVER_NAME is now ACTIVE, time from start: $sec_from_start sec (`sec2hms $sec_from_start`)"
        echo "  waiting for the network availability, hold on please."

        EXTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].externalIP')
        printf "%c" "    "
        while [[ -z "$EXTERNAL_IP" ]]; do
            printf "%c" "."
            EXTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].externalIP')
            INTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].ip')
            sleep 3s
        done

        echo "SERVER_EXTERNAL_IP=$EXTERNAL_IP" >> $SERVER_ROOT/server-build.log
        echo "SERVER_INTERNAL_IP=$INTERNAL_IP" >> $SERVER_ROOT/server-build.log
    fi
    printf "%c" "    "
    while ! ping -c 1 "$EXTERNAL_IP" &> /dev/null
    do
        sleep 5
        printf "%c" "."
    done
    echo
    sec_from_start=$((`date +%s` - START0))
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME ping success at public IP $EXTERNAL_IP, time from start: $sec_from_start sec (`sec2hms $sec_from_start`)"
    echo "Now checking for SSH ..."

    while true
    do
        ssh -q -oStrictHostKeyChecking=no "$SSH_USER"@"$EXTERNAL_IP" <<EOF
uname -a
echo "\$(date +%Y-%m-%d" "%H:%M:%S): \$(hostname): ssh SUCCESS"
EOF
        if [[ $? -eq 0 ]]
        then
            break
        fi
        sleep 5
    done
    sec_from_start=$((`date +%s` - START0))
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME SSH OK, time from start: $sec_from_start sec (`sec2hms $sec_from_start`)"

    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME: RMC status:"
    #ssh -oStrictHostKeyChecking=no "$SSH_USER"@"$EXTERNAL_IP" "sudo rmcdomainstatus -s ctrmc"
    ssh -q -oStrictHostKeyChecking=no "$SSH_USER"@"$EXTERNAL_IP" << EOF
sudo rmcdomainstatus -s ctrmc | sed "s/^/\$(date)  /"
EOF
    echo
    echo "$(date +%Y-%m-%d" "%H:%M:%S):  VMName:$SERVER_NAME is ready, access it using ssh at $EXTERNAL_IP."
}

function run (){

    echo "*****************************************************"

    ### Set this variables accordingly
    SERVER_IMAGE=
    PUBLIC_NETWORK=
    SSH_KEY_NAME=
    SERVER_MEMORY=
    SERVER_PROCESSOR=
    SERVER_SYS_TYPE=
    SSH_USER=
    API_KEY=
    PVS_CRN=
    ####

    # These can be passed in command line
    while [[ $1 =~ ^-- ]]
    do
        if [[ $1 =~ ^--server_image= ]]
        then
            SERVER_IMAGE=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--public_network= ]]
        then
            PUBLIC_NETWORK=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--ssh_key_name= ]]
        then
            SSH_KEY_NAME=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_memory= ]]
        then
            SERVER_MEMORY=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_processor= ]]
        then
            SERVER_PROCESSOR=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_sys_type= ]]
        then
            SERVER_SYS_TYPE=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--ssh_user= ]]
        then
            SSH_USER=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--api_key= ]]
        then
            API_KEY=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--pvs_crn= ]]
        then
            PVS_CRN=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_name= ]]
        then
            SERVER_NAME=$(cut -d= -f2- <<< $1)
        else
            echo "ERROR: Invalid option $1"
            return 1
        fi

        shift
    done

    if [[ -z $SERVER_NAME ]]
    then
        # server name not given generate one
        SERVER_ID=$(openssl rand -hex 5)
        SERVER_NAME="vm-$SERVER_ID"
    fi

    SERVER_ROOT=$PROGPATH/servers/"$SERVER_NAME"
    mkdir -p $SERVER_ROOT
    #cd $PROGPATH/servers/"$SERVER_NAME" || exit 1
    if [[ $? -ne 0 ]]
    then
        echo "ERROR: Could not create server root dir"
        return 1
    fi

    if [[ -z $SERVER_IMAGE || -z $PUBLIC_NETWORK || -z $SSH_KEY_NAME || -z $SERVER_MEMORY ||
        -z $SERVER_PROCESSOR || -z $SERVER_SYS_TYPE || -z $SSH_USER || -z $API_KEY || -z $PVS_CRN ]]
    then
        echo "ERROR: Missing args"
        return 1
    fi
    
    check_dependencies
    check_connectivity
    authenticate "$API_KEY"
    set_powervs "$PVS_CRN"

    # start of VM creation
    start=$(date +%s)
    START0=$start
    create_server "$SERVER_ID" "$SERVER_IMAGE" "$PUBLIC_NETWORK" "$SSH_KEY_NAME" \
        "$SERVER_MEMORY" "$SERVER_PROCESSOR" "$SERVER_SYS_TYPE" "$SSH_USER"
    rc=$?
    end=$(date +%s)
    echo "*****************************************************"
    runtime=$((end-start))
    if [[ $rc -ne 0 ]]
    then
        echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME VM creation ended in ERROR, time taken: $runtime seconds (`sec2hms $runtime`)"
        return 1
    fi
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME TOTAL TIME (upto ssh OK): $runtime seconds (`sec2hms $runtime`)" 

    # now wait for health OK
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME waiting for Health to become OK"
    start=$(date +%s)
    loop_cnt=0
    while true
    do
        sleep 15
        h_stat=$(ibmcloud pi in $FINAL_SERVER_ID --json | jq -r .health.status)
        if [[ $h_stat = OK ]]
        then
            echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME Health status OK now!"
	        break
        fi
        loop_cnt=$((loop_cnt + 1))
        if [[ $((loop_cnt % 4)) -eq 0 ]]
            then
            echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME Current health status: $h_stat"
        fi 
    done
    end=$(date +%s)
    ssh2healthOK=$((end - start))
    sec_from_start=$((end - START0))
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME Time taken for health OK (after ssh OK): $ssh2healthOK sec (`sec2hms $ssh2healthOK`)"
    echo "$(date +%Y-%m-%d" "%H:%M:%S): VMName:$SERVER_NAME Total time from original start: $sec_from_start sec (`sec2hms $sec_from_start`)"
}

### Main Execution ###
run "$@"
