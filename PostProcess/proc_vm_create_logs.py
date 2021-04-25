#!/usr/bin/env python
# Process logs generated by VM create operation and generate a CSV

import argparse
from pvcperf_instru.common_utils import time_diff_sec

vmname_info = {}
vmname_list = []

def sec_to_hhmmss(sec):
    if isinstance(sec, str):
        sec = int(sec)
    HH = int(sec / (60 * 60))
    sec -= HH * 60 * 60
    MM = int(sec / 60)
    SS = sec - MM * 60
    hh = str(HH)
    mm = str(MM)
    if len(mm) == 1:
        mm = "0" + mm
    ss = str(SS)
    if len(ss) == 1:
        ss = "0" + ss
    return hh + ":" + mm + ":" + ss

def main():
    aparser = argparse.ArgumentParser(description="Process logs generated by VM create operation and generate a CSV")
    aparser.add_argument("--log_file", required=True, help="Input log file")
    aparser.add_argument("--out_csv", required=True, help="Output CSV file")
    args = aparser.parse_args()

    with open(args.log_file, "r") as inf:
        for line in inf:
            if line.find("Creating VMName:") >= 0:
                vmname = line.split(":")[-1].strip()
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                if not vmname in vmname_info:
                    vmname_info[vmname] = {"start_ts": ts}
                    vmname_list.append(vmname)
                else:
                    vmname_info[vmname]["start_ts"] = ts
            elif line.find("was created with the ID:") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                vmid = line.split(" ID: ")[1].split()[0]
                if not vmname in vmname_info:
                    print("ERROR: VM %s created with ID %s, prev record not found" % (vmname, vmid))
                    vmname_info[vmname] = {}
                    vmname_list.append(vmname)
                elif not "start_ts" in vmname_info[vmname]:
                    print("ERROR: VM %s created with ID %s, start_ts not found" % (vmname, vmid))
                vmname_info[vmname]["vmid"] = vmid
            elif line.find("is now ACTIVE,") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                active_time_sec = toks[-3]
                vmname_info[vmname]["active_time_ts"] = ts
                vmname_info[vmname]["active_time_sec"] = active_time_sec
            elif line.find("ping success at public IP") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                ping_success_time_sec = toks[-3]
                vmname_info[vmname]["ping_success_ts"] = ts
                vmname_info[vmname]["ping_success_time_sec"] = ping_success_time_sec
            elif line.find("SSH OK, time from start") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                ssh_ok_time_sec = toks[-3]
                vmname_info[vmname]["ssh_ok_ts"] = ts
                vmname_info[vmname]["ssh_ok_time_sec"] = ssh_ok_time_sec
            elif line.find("*** RMC CONNECTED, time from start:") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                rmc_ok_time_sec = toks[-3]
                vmname_info[vmname]["rmc_ok_ts"] = ts
                vmname_info[vmname]["rmc_ok_time_sec"] = rmc_ok_time_sec
            elif line.find("Health status OK now!") >= 0:
                vmname = line.split("VMName:")[1].split()[0]
                if vmname[-1] == ":":
                    vmname = vmname[:-1]
                toks = line.split()
                ts = toks[0] + " " + toks[1] 
                if ts[-1] == ":":
                    ts = ts[:-1]
                vmname_info[vmname]["health_ok_ts"] = ts
    # write out csv
    with open(args.out_csv, "w") as outf:
        hdr = "VM_Name,VM_ID,start_ts,active_ts,active_time_sec,ping_success_ts,ping_success_time_sec"
        hdr += ",ssh_ok_ts,ssh_ok_time_sec,rmc_ok_ts,rmc_ok_time_sec,health_ok_ts,health_ok_time_sec"
        hdr += ",rmc_to_health_ok_sec,ssh_to_rmc_ok_sec"
        outf.write(hdr + "\n")
        for vmname in vmname_list:
            VM_ID = ""
            if "vmid" in vmname_info[vmname]:
                VM_ID = vmname_info[vmname]["vmid"]
            start_ts = ""
            if "start_ts" in vmname_info[vmname]:
                start_ts = vmname_info[vmname]["start_ts"]
            active_ts = ""
            if "active_time_ts" in vmname_info[vmname]:
                active_ts = vmname_info[vmname]["active_time_ts"]
            active_time_sec = ""
            if "active_time_sec" in vmname_info[vmname]:
                active_time_sec = vmname_info[vmname]["active_time_sec"]
                active_time_sec = active_time_sec + " (" + sec_to_hhmmss(active_time_sec) + ")"
            ping_success_ts = ""
            if "ping_success_ts" in vmname_info[vmname]:
                ping_success_ts = vmname_info[vmname]["ping_success_ts"]
            ping_success_time_sec = ""
            if "ping_success_time_sec" in vmname_info[vmname]:
                ping_success_time_sec = vmname_info[vmname]["ping_success_time_sec"]
                ping_success_time_sec = ping_success_time_sec + " (" + sec_to_hhmmss(ping_success_time_sec) + ")"
            ssh_ok_ts = ""
            if "ssh_ok_ts" in vmname_info[vmname]:
                ssh_ok_ts = vmname_info[vmname]["ssh_ok_ts"]
            ssh_ok_time_sec = ""
            if "ssh_ok_time_sec" in vmname_info[vmname]:
                ssh_ok_time_sec = vmname_info[vmname]["ssh_ok_time_sec"]
                ssh_ok_time_sec = ssh_ok_time_sec + " (" + sec_to_hhmmss(ssh_ok_time_sec) + ")"
            rmc_ok_ts = ""
            if "rmc_ok_ts" in vmname_info[vmname]:
                rmc_ok_ts = vmname_info[vmname]["rmc_ok_ts"]
            rmc_ok_time_sec = ""
            if "rmc_ok_time_sec" in vmname_info[vmname]:
                rmc_ok_time_sec = vmname_info[vmname]["rmc_ok_time_sec"]
                rmc_ok_time_sec = rmc_ok_time_sec + " (" + sec_to_hhmmss(rmc_ok_time_sec) + ")"
            health_ok_ts = ""
            if "health_ok_ts" in vmname_info[vmname]:
                health_ok_ts = vmname_info[vmname]["health_ok_ts"]
            health_ok_time_sec = ""
            if start_ts and health_ok_ts:
                health_ok_time_sec = "%d" % round(time_diff_sec(start_ts, health_ok_ts))
                health_ok_time_sec = health_ok_time_sec + " (" + sec_to_hhmmss(health_ok_time_sec) + ")"
            rmc_to_health_ok_sec = ""
            if rmc_ok_ts and health_ok_ts:
                rmc_to_health_ok_sec = "%d" % round(time_diff_sec(rmc_ok_ts, health_ok_ts))
                rmc_to_health_ok_sec = rmc_to_health_ok_sec + " (" + sec_to_hhmmss(rmc_to_health_ok_sec) + ")"
            ssh_to_rmc_ok_sec = ""
            if ssh_ok_ts and rmc_ok_ts:
                ssh_to_rmc_ok_sec = "%d" % round(time_diff_sec(ssh_ok_ts, rmc_ok_ts))
                ssh_to_rmc_ok_sec = ssh_to_rmc_ok_sec + " (" + sec_to_hhmmss(ssh_to_rmc_ok_sec) + ")"

            data_line = (vmname + "," + VM_ID + "," + start_ts + "," + active_ts + "," + active_time_sec + "," +
                        ping_success_ts + "," + ping_success_time_sec + "," + ssh_ok_ts + "," + ssh_ok_time_sec + "," +
                        rmc_ok_ts + "," + rmc_ok_time_sec + "," + health_ok_ts + "," + health_ok_time_sec + "," + 
                        rmc_to_health_ok_sec + "," + ssh_to_rmc_ok_sec)
            outf.write(data_line + "\n")

    return 0

if __name__ == "__main__":
    main()
