#!/bin/zsh

# ANSI color codes for stdout status code
RED='\033[1;31m'
GREEN='\033[1;32m'
ORANGE='\033[38;5;214m'
GREENW='\033[38;5;22;48;5;15m'
BLUEW='\033[0;34;47m'
NC='\033[0m' # No Color

timestamp() { date "+%Y-%m-%d %H:%M:%S" }
logonly() { local message="$1"; echo "$(timestamp) Info - $message" >> $teefile }
log() { local message="$1"; echo "$(timestamp) $message" | tee -a $teefile }
logI() { local message="$1";               echo "$(timestamp) Info    - $message" | tee -a $teefile }
logW() { local message="$1"; echo "$(timestamp) ${ORANGE}Warning${NC} - $message" | tee -a $teefile }
logS() { local message="$1";  echo "$(timestamp) ${GREEN}Success${NC} - $message" | tee -a $teefile }
logE() { local message="$1";    echo "$(timestamp) ${RED}Error${NC}   - $message" | tee -a $teefile; exit 1 } # Error handling function

# Example:
# logI  "She'll be right..."
# logW "Hum, that's precarious"
# logS "That's awesome!"
# logE "Ohhhhhhh darn!"