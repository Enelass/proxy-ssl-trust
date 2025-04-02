#!/bin/zsh
# Some due credits, lest we forget: https://www.zdnet.com/article/without-dennis-ritchie-there-would-be-no-jobs/
if [[ -z ${teefile-} ]]; then teefile="/tmp/tmp.logfile.log"; fi

# ANSI color codes for stdout status code
RED='\033[1;31m'
GREEN='\033[1;32m'
ORANGE='\033[38;5;214m'
GREENW='\033[38;5;22;48;5;15m'
BLUEW='\033[0;34;47m'
NC='\033[0m' # No Color


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
