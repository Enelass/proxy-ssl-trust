#!/bin/zsh
# This script is used to set some colored syntaxt for the user stdout, or stderr.
# It also add function to hide stdout if needed (quiet function), or restore it (unqiet function)

# Some due credits, lest we forget: https://www.zdnet.com/article/without-dennis-ritchie-there-would-be-no-jobs/
if [[ -z ${teefile-} ]]; then teefile="/tmp/tmp.logfile.log"; fi


# Trap the script termination signals
# trap 'stop_spinner_sigint; play_signint > /dev/null 2>&1' SIGINT
# trap 'stop_spinner; play_exit > /dev/null 2>&1' EXIT

# ANSI color codes for stdout status code
RED='\033[1;31m'
GREEN='\033[1;32m'
ORANGE='\033[38;5;214m'
GREENW='\033[38;5;22;48;5;15m'
BLUEW='\033[0;34;47m'
PINK='\033[38;5;206m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color



#___________________________________________________ Output Verbosity ________________________________________________________

# Function to remove stdout and stderr for every cert but the summary of it
quiet() {
    quiet=1
    exec 3>&1 4>&2
    exec 1>/dev/null 2>&1
}

# Function to add back stdout and stderr
unquiet() {
    unset quiet
    unset silent
    exec 1>&3 2>&4
    exec 3>&- 4>&-
}

# Function to remove stdout and stderr for everything...
silent() {
    quiet; silent=1
}


#_________________________________________________ LOGGING & Colored Syntax ________________________________________________

# Functions to add colored syntax to stdout...
timestamp() { 
    date "+%Y-%m-%d %H:%M:%S" 
}

logonly() { 
    local message="$1"
    echo "$(timestamp) $message" >> "$teefile" 
}

log() { 
	local message="$1"
    echo "$(timestamp) $message" | sed "s/\x1b\[[0-9;]*m//g" >> "$teefile"
    echo "$(timestamp) $message"
}

logI() { 
    local message="$1"
    echo "$(timestamp) Info    - $message" | sed "s/\x1b\[[0-9;]*m//g" >> "$teefile"
    echo "$(timestamp) Info    - $message"
}

logW() { 
    local message="$1"
    echo "$(timestamp) ${ORANGE}Warning${NC} - $message" | sed "s/\x1b\[[0-9;]*m//g" >> "$teefile"
    echo "$(timestamp) ${ORANGE}Warning${NC} - $message"
}

logS() { 
    local message="$1"
    echo "$(timestamp) ${GREEN}Success${NC} - $message" | sed "s/\x1b\[[0-9;]*m//g" >> "$teefile"
    echo "$(timestamp) ${GREEN}Success${NC} - $message"
}

logE() { 
    local message="$1"
    echo "$(timestamp) ${RED}Error${NC}   - $message" | sed "s/\x1b\[[0-9;]*m//g" >> "$teefile"
    echo "$(timestamp) ${RED}Error${NC}   - $message"
    exit 1
}

# Example usage:    
# log "( ｡ •̀ ᴖ •́ ｡)💢  I am free..."
# log "Custom  - This is my color coded ${BLUEW}variable${NC} and here's ${GREENW}another one${NC}..."
# logI "Nothing too exciting..."
# logW "Hum, that's precarious!"
# logS "Success... at last!"
# logE "Ohhhhhhh darn!"


#______________________________________________________________ Waiting Pattern _________________________________________________________
# Global variable to store the spinner process ID
# SPINNER_PID=""
# Function to start the basic spinner
# function start_spinner() {
#     local delay=0.1
#     local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
#     [[ -n $SPINNER_PID ]] && return
#     (
#         while :; do
#             for i in $(seq 0 ${#spinstr}); do
#                 printf "\r${1-} %s " "${spinstr:$i:1}"
#                 sleep $delay
#             done
#         done
#     ) &
#     SPINNER_PID=$!
# }

# Function to start the complex spinner
function start_spinner() {
    local delay=0.1
    local spinstr='[    ████    ]|[   ████     ]|[  ████      ]|[ ████       ]|[████        ]|[███        █]|[██        ██]|[█        ███]|[        ████]|[       ████ ]|[      ████  ]|[     ████   ]'
    [[ -n $SPINNER_PID ]] && return
    (
        while :; do
            for frame in ${(s:|:)spinstr}; do
                printf "\r${1-} %s " "${frame}"
                sleep $delay
            done
        done
    ) &
    SPINNER_PID=$!
}

# Function to stop the spinner
function stop_spinner_sigint() {
    # If spinner is running, kill it and clear the line
    if [[ -n $SPINNER_PID ]]; then
        kill $SPINNER_PID
        unset SPINNER_PID
        printf "\r%s\n" "$(printf ' %.0s' {1..50})"
        echo -en "\r\033[2K\033[F\033[2K"
        logE "User terminated the script. Cleaning up and exiting..."
        exit 1
    fi
}

function stop_spinner() {
    # If spinner is running, kill it and clear the line
    if [[ -n $SPINNER_PID ]]; then
        kill $SPINNER_PID
        unset SPINNER_PID
        printf "\r%s\n" "$(printf ' %.0s' {1..50})"
        echo -en "\r\033[2K\033[F\033[2K"
    fi
}


# Example with actual work
# function do_long_task() {
#     start_spinner "Please wait..."
#     # Your long running task here
#     sleep 5  # Simulate work
#     stop_spinner
#     echo -en "\r\033[2K\033[F\033[2K"
# }
# do_long_task
