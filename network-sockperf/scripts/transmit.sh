#!/bin/bash

# Description: Generate workloads by sockperf.
# Maintainer: Charles Shih <schrht@gmail.com>

function show_usage() {
    echo "Generate workloads by sockperf."
    echo "$(basename $0) <-m TRAFFICMODE> <-s SERVERIP> [-p BASEPORT] [-t TIMEOUT] [-d DUPLICATES]"
    echo "TRAFFICMODE: The traffic mode to transmit (pps|bw)."
    echo "   SERVERIP: The server's IP address."
    echo "   BASEPORT: The ports start from (default=10000)."
    echo "    TIMEOUT: The interval of the test (default=30)."
    echo " DUPLICATES: The duplicates of the test (default=1)."
}

while getopts :hm:s:p:t:d: ARGS; do
    case $ARGS in
    h)
        # Help option
        show_usage
        exit 0
        ;;
    m)
        # trafficmode option
        trafficmode=$OPTARG
        ;;
    s)
        # serverip option
        serverip=$OPTARG
        ;;
    p)
        # baseport option
        baseport=$OPTARG
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

if [ -z "$trafficmode" ]; then
    show_usage
    exit 1
elif [ "$trafficmode" != "pps" ] and [ "$trafficmode" != "bw" ]; then
    echo "Unknown TRAFFICMODE: $trafficmode"
    show_usage
    exit 1
fi

if [ -z "$serverip" ]; then
    show_usage
    exit 1
fi

: ${baseport:=10000}
: ${timeout:=30}
: ${duplicates:=1}

# Main
killall -q sockperf
rm -f /tmp/sockperf.log.*

#cpu_core=$(cat /proc/cpuinfo | grep process | wc -l)
cpu_core=64
flavor=$(curl http://100.100.100.200/latest/meta-data/instance/instance-type 2>/dev/null)

echo "---"
echo "flavor=$flavor"
echo "cpu_core=$cpu_core"
echo "serverip=$serverip"
echo "baseport=$baseport"
echo "timeout=$timeout"
echo "duplicates=$duplicates"
echo "---"

for ((n = 0; n < $duplicates; n++)); do
    for ((i = 0; i < $cpu_core; i++)); do
        port=$(($baseport + $n * 1000 + $i))
        echo "Starting test on port $port..."
        if [ "$trafficmode" = "pps" ]; then
            sockperf tp -i $serverip --pps max -m 14 \
                -t $timeout --port $port &>/tmp/sockperf.log.$port &
        else
            sockperf tp -i $serverip -m 50000 \
                -t $timeout --port $port --tcp &>/tmp/sockperf.log.$port &
        fi
    done
done

wait

echo "---"
grep ^ /tmp/sockperf.log.* 2>/dev/null
