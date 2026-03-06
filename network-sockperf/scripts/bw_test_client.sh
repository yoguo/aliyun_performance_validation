#!/bin/bash

# Description: Generate workloads by netperf.

function show_usage() {
    echo "Generate workloads by sockperf."
    echo "$(basename $0) <-s SERVERIP> [-p BASEPORT] [-t TIMEOUT]"
    echo "   SERVERIP: The server's IP address."
    echo "   BASEPORT: The ports start from (default=16000)."
    echo "    TIMEOUT: The interval of the test (default=30)."
}

while getopts :hs:p:t: ARGS; do
    case $ARGS in
    h)
        # Help option
        show_usage
        exit 0
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

if [ -z "$serverip" ]; then
    show_usage
    exit 1
fi

: ${baseport:=16000}
: ${timeout:=30}

# Main
killall -q netperf

for j in `seq 32`; do
    port=$[$baseport+j]
    netperf -H ${serverip} -l $timeout -t TCP_STREAM  -p $port  -- -s 10240000 -S 10240000 -D &
    #netperf -H ${serverip} -l $timeout -t TCP_STREAM  -p $port  -- -m 1440 -D &
    #netperf -H ${serverip} -l $timeout -t TCP_STREAM  -p $port  -- -D &
done

wait
