#!/usr/bin/env bash
# Wrapper for:
# -- create a VM with given args
# -- wait for given amount of time
# -- delete the VM

progname=$(basename $0)
progpath=$(dirname $0)
keep_time_sec_def=600 #10 mins, default time to keep VM before deleting
server_name=
server_name_pref_def=vm
server_name_pref=$server_name_pref_def
server_image=
public_network=
ssh_key_name=
server_memory=
server_processor=
server_sys_type=
ssh_user=
api_key=
pvs_crn=
keep_time_sec=$keep_time_sec_def
logfile=
use_tmp_logfile=0


function usage
{
    echo "Usage: $progname [--server_name_pref=<name>] --server_image=<image_id> --public_network=<pubnet_id> --ssh_key_name=<key_name>"
    echo "        --server_memory=<memory_GB> --server_processor=<cpu> --server_sys_type=<sys_type> --ssh_user=<user>"
    echo "        --api_key=<key> --pvs_crn=<crn> [--keep_time_sec=<time before delete, default:$keep_time_sec_def>] [--logfile=<file>]"
}

function main
{
    while [[ $1 =~ ^-- ]]
    do
        if [[ $1 =~ ^--server_name_pref= ]]
        then
            server_name_pref=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_image= ]]
        then
            server_image=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--public_network= ]]
        then
            public_network=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--ssh_key_name= ]]
        then
            ssh_key_name=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_memory= ]]
        then
            server_memory=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_processor= ]]
        then
            server_processor=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--server_sys_type= ]]
        then
            server_sys_type=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--ssh_user= ]]
        then
            ssh_user=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--api_key= ]]
        then
            api_key=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--pvs_crn= ]]
        then
            pvs_crn=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--keep_time_sec= ]]
        then
            keep_time_sec=$(cut -d= -f2- <<< $1)
        elif [[ $1 =~ ^--logfile= ]]
        then
            logfile=$(cut -d= -f2- <<< $1)
        else
            echo "ERROR: Unknown oprion $1"
            usage
            return 1
        fi

        shift
    done

    if [[ -n $1 ]]
    then
        echo "ERROR: Invalid args"
        usage
        return 1
    fi

    if [[ -z $server_image || -z $public_network || -z $ssh_key_name || -z $server_memory ||
            -z $server_processor || -z $server_sys_type || -z $ssh_user || -z $api_key || -z $pvs_crn ]]
    then
        echo "Missing args"
        usage
        return 1
    fi

    server_name=${server_name_pref}-$(openssl rand -hex 5)

    if [[ -z $logfile ]]
    then
        # use a temp one
        logfile=$(mktemp)
        use_tmp_logfile=1
    fi

    cmd="bash $progpath/../create-single-vm.sh --server_name=$server_name --server_image=$server_image --public_network=$public_network \
        --ssh_key_name=$ssh_key_name --server_memory=$server_memory --server_processor=$server_processor --server_sys_type=$server_sys_type \
        --ssh_user=$ssh_user --api_key=$api_key --pvs_crn=$pvs_crn"
    if [[ -n $logfile ]]
    then
        cmd=$cmd" |& tee $logfile"
    fi
    eval "$cmd"

    #wait for given time
    echo "$(date +%Y-%m-%d" "%H:%M:%S): Sleeping for $keep_time_sec secs" | tee -a $logfile
    sleep $keep_time_sec

    # get VM id from logfile
    vm_id=$(grep "was created with the ID:" $logfile | grep $server_name | awk '{print $NF}')
    if [[ -z $vm_id ]]
    then
        echo "$(date +%Y-%m-%d" "%H:%M:%S): VM ID for VM $server_name could not be found" | tee -a $logfile
    else
        echo "$(date +%Y-%m-%d" "%H:%M:%S): Deleting VM $server_name (ID: $vm_id)" | tee -a $logfile
        ibmcloud pi instance-delete $vm_id
    fi
    echo "$(date +%Y-%m-%d" "%H:%M:%S): === TASK END ===" | tee -a $logfile
    if [[ $use_tmp_logfile -eq 1 ]]
    then
        rm -f $logfile
    fi
}

main "$@"
