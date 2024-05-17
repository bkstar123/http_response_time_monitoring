#!/bin/bash
#
# author: Tuan Hoang
#
script_name=${0##*/}
function usage()
{
    echo "###Syntax: $script_name -t <threshold> -i <instance name> -l <URL> -f <interval>"
    echo "- You must specify instance name so that logs are written to separated folders for each instance"
    echo "- You must specify -l <URL> option to tell which URL to monitor http response time"
    echo "- Without specifying -f <interval>, the script will execute every 10s"
    echo "- Without specifying -t <threshold>, the default will be 1000ms"
    echo "###Threshold: when the HTTP Response time reaches the threshold from the working instance, the script will automatically take memory dump for that instance"
    echo "-a  is used to append curl options, e.g -a '--resolve hostname:80:127.0.0.1'"
}
function die()
{
    echo "$1" && exit $2
}
while getopts ":t:i:l:f:a:h" opt; do
    case $opt in
        t) 
           threshold=$OPTARG
           ;;
        i) 
           instance=$OPTARG
           ;;
        l)
           location=$OPTARG
           ;;
        f)
           frequency=$OPTARG
           ;;
        a)
           append="$OPTARG"
           ;;
        h)
           usage
           exit 0
           ;;
        *) 
           die "Invalid option: -$OPTARG" 1 >&2
           ;;
    esac
done
shift $(( OPTIND - 1 ))

if [[ -z "$instance" ]]; then
    die "###Critical: You must specify instance name using the option -i, e.g: -i <instance name>" >&2 1
fi

if [[ -z "$location" ]]; then
    die "###Critical: You must specify URL to monitor HTTP Response for using the option -l, e.g: -l http://localhost:80" >&2 1
fi

if [[ -z "$threshold" ]]; then
    echo "###Info: without specifying option -t <threshold>, the script will set the default threashold of http response time to 1000ms before triggering memory dump taking"
    threshold=1000
fi

if [[ -z "$frequency" ]]; then
    echo "###Info: without specifying option -f <interval>, the script will execute every 10s"
    frequency=10
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

# Output dir is named after instance name
output_dir="responsetime-logs-${instance}" 

# Create output directory if it doesn't exist
mkdir -p "$output_dir"

while true; do
    # Check if it's a new hour
    current_hour=$(date +"%Y-%m-%d_%H")
    if [ "$current_hour" != "$previous_hour" ]; then
        # Rotate the file
        output_file="$output_dir/responsetime_stats_${current_hour}.log"
        previous_hour="$current_hour"
    fi
    
    # Your command to output to the file (example: echo "Some output" >> "$output_file")
  echo "Poll complete. Waiting for $frequency seconds..."
    ./get_http_response_time.sh $threshold $instance $location "$append" >> "$output_file"

    # Wait for 10 seconds before the next run
    sleep $frequency
done

