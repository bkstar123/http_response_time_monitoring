#!/bin/bash
#
# This script is for monitoring the response time of a .NET core application.
# If the response time exceeds a predefined threshold, then the script will automatically generate a memory dump/profiler trace for investigation.
#
# author: Tuan Hoang
# 21 June 2024
script_name=${0##*/}
function usage()
{
    echo "###Syntax: $script_name -t <threshold> -l <URL> -f <interval>"
    echo "-l <URL> option to tell which URL to monitor http response time, format: http://hostname:port, If not given, then will be defaulted to http://localhost:80"
    echo "-f <interval> tells how frequent (in second) to poll the application, if not given, then will poll the application every 10s"
    echo "-t <threshold> tells the threshold (in ms) of application response time to collect dump/trace, if not given then will be defaulted to 1000ms"
}
function die()
{
    echo "$1" && exit $2
}
function teardown()
{
    # kill relevant process
    echo "Shutting down 'dotnet-trace collect' process..."
    kill -SIGTERM $(ps -ef | grep "/tools/dotnet-trace" | grep -v grep | tr -s " " | cut -d" " -f2 | xargs)
    echo "Shutting down 'dotnet-dump collect' process..."
    kill -SIGTERM $(ps -ef | grep "/tools/dotnet-dump" | grep -v grep | tr -s " " | cut -d" " -f2 | xargs)
    echo "Shutting down 'azcopy copy' process..."
    kill -SIGTERM $(ps -ef | grep "/tools/azcopy" | grep -v grep | tr -s " " | cut -d" " -f2 | xargs)
    echo "Shutting down $script_name process..."
    kill -SIGTERM $(ps -ef | grep "$script_name" | grep -v grep | tr -s " " | cut -d" " -f2 | xargs)
    echo "Finishing up..."
    echo "Completed"
    exit 0
}
function getsasurl()
{
    # $1-pid
    sas_url=$(cat "/proc/$1/environ" | tr '\0' '\n' | grep -w DIAGNOSTICS_AZUREBLOBCONTAINERSASURL)
    sas_url=${sas_url#*=}
    echo "$sas_url"
}
function getcomputername()
{
    # $1-pid
    instance=$(cat "/proc/$1/environ" | tr '\0' '\n' | grep -w COMPUTERNAME)
    instance=${instance#*=}
    echo "$instance"
}
function collectdump()
{
    # $1-$output_file, $2-$dump_lock_file, $3-$instance, $4-$pid
    if [[ ! -e "$2" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Acquiring lock for dumping..." >> "$1" && touch "$2" && echo "Memory dump is collected by $3" >> "$2"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Collecting memory dump...." >> "$1"
        local dump_file="dump_$3_$(date '+%Y%m%d_%H%M%S').dmp"
        local sas_url=$(getsasurl "$4")
        /tools/dotnet-dump collect -p "$4" -o "$dump_file" > /dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Memmory dump has been collected. Uploading it to Azure Blob Container 'insights-logs-appserviceconsolelogs'" >> "$1"
        /tools/azcopy copy "$dump_file" "$sas_url" > /dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Memory dump has been uploaded to Azure Blob Container 'insights-logs-appserviceconsolelogs'" >> "$1"
    fi 
}
function collecttrace()
{
    # $1-$output_file, $2-$trace_lock_file, $3-$instance, $4-$pid
    if [[ ! -e "$2" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Acquiring lock for tracing..." >> "$1" && touch "$2" && echo "Profiler trace is collected by $3" >> "$2"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Collecting profiler trace...." >> "$1"
        local trace_file="trace_$3_$(date '+%Y%m%d_%H%M%S').nettrace"
        local sas_url=$(getsasurl "$4")
        /tools/dotnet-trace collect -p "$4" -o "$trace_file" > /dev/null &
        sleep 60 # Wait 60s before stop tracing
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Stopping profiler tracing" >> "$1"
        kill -SIGTERM $(ps -ef | grep "/tools/dotnet-trace" | grep -v grep | tr -s " " | cut -d" " -f2 | xargs)
        echo "$(date '+%Y-%m-%d %H:%M:%S'): The profiler trace has been stoppped" >> "$1" 
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Profiler trace has been collected. Uploading it to Azure Blob Container 'insights-logs-appserviceconsolelogs'" >> "$1"
        /tools/azcopy copy "$trace_file" "$sas_url" > /dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Profiler has been uploaded to Azure Blob Container 'insights-logs-appserviceconsolelogs'" >> "$1"
    fi
}
while getopts ":t:l:f:o:hc" opt; do
    case $opt in
        t) 
           threshold=$OPTARG
           ;;
        l)
           location=$OPTARG
           ;;
        f)
           frequency=$OPTARG
           ;;
        o)
           option=$OPTARG
           ;;
        h)
           usage
           exit 0
           ;;
        c)
           clean_flag=1
           ;;
        *) 
           die "Invalid option: -$OPTARG" 1 >&2
           ;;
    esac
done
shift $(( OPTIND - 1 ))

# Cleaning all processes generated by the script
if [[ "$clean_flag" -eq 1 ]]; then
    teardown
fi

if [[ -z "$location" ]]; then
    echo "###Info: without specifying URL, the script will monitor http://localhost:80 by default"
    location="http://localhost:80"
fi

if [[ -z "$threshold" ]]; then
    echo "###Info: without specifying option -t <threshold>, the script will set the default threshold of http response time to 1000ms before collecting dump/trace"
    threshold=1000 # in ms
fi

if [[ -z "$frequency" ]]; then
    echo "###Info: without specifying option -f <interval>, the script will execute every 10s"
    frequency=10 # in seconds
fi

# Initialized values for script's arguments
enable_dump=false
enable_trace=false
if [[ "$#" -gt 0 ]]; then
    case $1 in
        enable-dump)
            enable_dump=true
            ;;
        enable-trace)
            enable_trace=true
            ;;
        enable-dump-trace)
            enable_dump=true
            enable_trace=true
            ;;
        *)
            die "Unknown argument passed: $1" 1
            ;;
    esac
fi

# Validate if curl is installed
if ! command -v curl &> /dev/null; then
    echo "###Info: curl is not installed. Installing curl...."
    apt-get update && apt-get install -y curl
fi

# Validate if bc is installed
if ! command -v bc &> /dev/null; then
    echo "###Info: bc is not installed. Installing bc...."
    apt-get update && apt-get install -y bc
fi
# Find the PID of the .NET application
pid=$(/tools/dotnet-dump ps | grep /usr/share/dotnet/dotnet | grep -v grep | tr -s " " | cut -d" " -f2)
if [ -z "$pid" ]; then
    die "There is no .NET process running" 1
fi

# Get the computer name from /proc/PID/environ, where PID is .net core process's pid
instance=$(getcomputername "$pid")
if [[ -z "$instance" ]]; then
    die "Cannot find the environment variable of COMPUTERNAME" >&2 1
fi
# Output dir is named after instance name
output_dir="resptime-logs-$instance"
# Create output directory if it doesn't exist
mkdir -p "$output_dir"
# name of the lock file for generating memdump
dump_lock_file="dump_taken.lock"
# name of the lock file for generating trace
trace_lock_file="trace_taken.lock"
# Set timeout for curl command as 5s after exceeding the threshold
timeout=$(( threshold + 5000 ))
# Extract host:port part of the monitored URL
url="${location#*://}"
host_and_port="${url%%/*}"

# Start monitoring
while true; do
    # Check if it's a new hour for rotating logs
    current_hour=$(date +"%Y-%m-%d_%H")
    if [ "$current_hour" != "$previous_hour" ]; then
        # Rotate the file
        output_file="$output_dir/resptime_stats_${current_hour}.log"
        previous_hour="$current_hour"
    fi
    # Read HTTP Response time & Status code into separated variables
    read -r respTimeInSeconds httpCode <<< $(curl -so /dev/null -w "%{time_total} %{http_code}" -m $timeout $location --resolve "$host_and_port":127.0.0.1)
    curl_code=$?
    if [[ $curl_code -eq 28 ]]; then
        respTimeinMiliSeconds=$timeout
        echo "$(date '+%Y-%m-%d %H:%M:%S'): CURL request has been timed out" >> "$output_file"
    else
        # Convert to miliseconds
        respTimeinMiliSeconds=$(echo "$respTimeInSeconds*1000/1" | bc)
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Response Time $respTimeinMiliSeconds (ms), Status Code $httpCode" >> "$output_file"
    fi   
    # Collect memory dump if HTTP response time reaches the threshold & HTTP code is in [200, 301, 302]  
    if [[ "$respTimeinMiliSeconds" -ge "$threshold" ]]; then
        if [[ "$enable_dump" == true  ]]; then
            collectdump "$output_file" "$dump_lock_file" "$instance" "$pid" &
        fi

        if [[ "$enable_trace" == true ]]; then
            collecttrace "$output_file" "$trace_lock_file" "$instance" "$pid" &
        fi  
    fi
    # Wait for the next polling
    sleep $frequency
done

