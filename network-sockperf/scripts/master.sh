#!/bin/bash

# Description: Schedule test and analyse data on server.
# Maintainer: Charles Shih <schrht@gmail.com>

function show_usage() {
    echo "Schedule test and analyse data on server."
    echo "$(basename $0) <-m TESTMODE> <-c CLIENTS> <-z ZONE> [-t TIMEOUT] [-d DUPLICATES]"
    echo "  TESTMODE: The test mode to perform (pps|bw)."
    echo "   CLIENTS: The list of clients' IP address."
    echo "     ZONE:  The zone of the test"
    echo "   TIMEOUT: The interval of the test (default=30)."
    echo "DUPLICATES: The duplicates of the test (default=1)."
}

while getopts :hm:c:z:t:d: ARGS; do
    case $ARGS in
    h)
        # Help option
        show_usage
        exit 0
        ;;
    m)
        # testmode option
        testmode=$OPTARG
        ;;
    c)
        # clients option
        clients=$OPTARG
        ;;
    z)
        # zone option
        zone=$OPTARG
        ;;
    t)
        # timeout option
        timeout=$OPTARG
        ;;
    d)
        # duplicates option
        duplicates=$OPTARG
        ;;
    "?")
        echo "$(basename $0): unknown option: $OPTARG" >&2
        ;;
    ":")
        echo "$(basename $0): option requires an argument -- '$OPTARG'" >&2
        echo "Try '$(basename $0) -h' for more information." >&2
        exit 1
        ;;
    *)
        # Unexpected errors
        echo "$(basename $0): unexpected error -- $ARGS" >&2
        echo "Try '$(basename $0) -h' for more information." >&2
        exit 1
        ;;
    esac
done

if [ -z "$testmode" ]; then
    show_usage
    exit 1
elif [ "$testmode" != "pps" ] && [ "$testmode" != "bw" ]; then
    echo "Unknown TESTMODE: $testmode"
    show_usage
    exit 1
fi

if [ -z "$clients" ]; then
    show_usage
    exit 1
fi

: ${timeout:=30}
: ${duplicates:=1}

NIC=eth0
BINPATH=~/workspace
LOGPATH=~/workspace/log
BASEPORT=10000

# Main
hostip=$(ifconfig $NIC | grep -w inet | awk '{print $2}')
flavor=$(curl http://100.100.100.200/latest/meta-data/instance/instance-type 2>/dev/null)
cpu_core=$(cat /proc/cpuinfo | grep process | wc -l)
os=$(source /etc/os-release && echo ${ID}-${VERSION_ID})
timestamp=$(date +D%y%m%dT%H%M%S)

echo "hostip=$hostip"
echo "flavor=$flavor"
echo "clients=$clients"
echo "baseport=$BASEPORT"
echo "timeout=$timeout"
echo "cpu_core=$cpu_core"
echo "duplicates=$duplicates"
echo "os=$os"
echo "timestamp=$timestamp"

logdir=$LOGPATH/sockperf_${flavor}_${os}_${timestamp}
mkdir -p $logdir

for client in $clients; do
    echo "Setup $client..."
    scp $BINPATH/transmit.sh root@$client:/tmp/ || exit 1
done

if [ "$testmode" = "bw" ]; then
    # Start sockperf server for TCP throughput test
    killall -q sockperf
    for ((n = 0; n < $duplicates; n++)); do
        for ((i = 0; i < $cpu_core; i++)); do
            port=$(($BASEPORT + $n * 1000 + $i))
            echo "Listening on port $port..."
            sockperf sr --tcp -i $hostip --port $port &
        done
    done
    # Schedule sockperf server to stop
    sleep $(($timeout + 50)) && killall -q sockperf &
fi


# Bind interrupts for PPS test(> 2000W) according to https://help.aliyun.com/document_detail/419630.html
# On g8y/c8y/r8y/c8a/r8a/c8ae/r8ae/ebmg6e/g9i/g9as/g9a/g9ae instances, the device is virtio1 not virtio2 (default)
# Need to set cpu=64 for g8y/c8y/r8y on RHEL8 since the network card is on numa 1
# On ebmg8y/ebmc8y/ebmr8y/ebmg8i/ebmc8i/ebmc8ae/ebmg8a, the device is virtio0

# a=$(cat /proc/interrupts | grep virtio1-input | awk -F ':' '{print $1}')
# cpu=0
# for irq in $a; do
#     echo $cpu >/proc/irq/$irq/smp_affinity_list
#     let cpu+=2
# done

# Trigger workload
client_num=0
for client in $clients; do
    client_num=$((client_num + 1))
    echo "Starting test from client $client..."
    log=$logdir/transmit_${flavor}_${os}_${client}.log
    ssh root@$client "/tmp/transmit.sh -m $testmode -s $hostip \
        -p $BASEPORT -d $duplicates -t $(($timeout + 40))" &>$log &
done

# Collect data
safile=$logdir/master_${flavor}_${os}_${timestamp}.sa
sleep 20 # ramp time
sar -A 1 $timeout -o $safile &>/dev/null
wait # waiting for clients

# Analyse data
links=$(cat $logdir/transmit_*.log | grep -c 'sockperf: Starting test...')
rxpckps=$(sar -n DEV -f $safile | grep "Average.*$NIC" | awk '{print $3}')
rxkpps=$(echo "scale=2; ${rxpckps:-0} / 1000" | bc)
rxkBps=$(sar -n DEV -f $safile | grep "Average.*$NIC" | awk '{print $5}')
rxGbps=$(echo "scale=2; ${rxkBps:-0} * 8 / 1000000" | bc)

# Dump results
logfile=$logdir/sockperf_${flavor}_${os}_${timestamp}.txt
echo "
Flavor  OS  Mode          CLT         CPU       DUP         Links    Duration PPSrx(k)  BWrx(Gb/s) Zone
$flavor $os ${testmode^^} $client_num $cpu_core $duplicates ${links} $timeout ${rxkpps} ${rxGbps}  ${zone}
" | column -t >$logfile

tarfile=$LOGPATH/sockperf_${flavor}_${os}_${timestamp}.tar.gz
cd $logdir && tar -zcvf $tarfile *.sa *.log *.txt

echo "---"
cat $logfile
