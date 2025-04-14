#!/bin/zsh

# # Function to print the table header
# print_header() {
#   echo "+--------+-----------------------------------------+"
#   echo "| Proxy SSL Trust, Step by Step visualiser         |"
#   echo "| This software is intended to resolve all proxy   |"
#   echo "| and HTTPS certificates trust issues for all CLI  |"
#   echo "+--------+-----------------------------------------+"
#   echo "| Status | Description                             |"
#   echo "+--------+-----------------------------------------+"
# }

# # Function to print a row with green ticket or red cross and a description
# print_row() {
#   local _status=$1
#   local _description=$2
#   local _status_icon

#   if [[ $_status == "success" ]]; then
#     _status_icon="\033[32m✔\033[0m"  # Green check
#   else
#     _status_icon="\033[31m✘\033[0m"  # Red cross
#   fi

#   printf "|   %b    | %-37s |\n" "$_status_icon" "$_description"
#   echo "+--------+-----------------------------------------+"
# }

# # Main function to print the table
# print_table() {
#   print_header
#   print_row "success" "Action 1 completed successfully"
#   print_row "failure" "Action 2 failed to execute"
#   print_row "success" "Action 3 completed successfully"
#   print_row "failure" "Action 4 failed to execute"
#   print_row "success" "Login attempt successful"
#   print_row "failure" "File not found"
#   print_row "success" "Server started"
#   print_row "failure" "Permission denied"
# }

# # Call the main function
# print_table


# ________________________________________________________________________________________________________________________________________________



# Function to print the table header
print_header() {
  echo "+--------+-----------------------------------------+"
  echo "| Proxy SSL Trust, Step by Step visualiser         |"
  echo "| This software is intended to resolve all proxy   |"
  echo "| and HTTPS certificates trust issues for all CLI  |"
  echo "+--------+-----------------------------------------+"
  echo "| Status | Description                             |"
  echo "+--------+-----------------------------------------+"
}

# Function to print a row with green ticket or red cross and a description
print_row() {
  local _stat=$1
  local _desc=$2
  local _stat_icon

  if [[ $_stat == "success" ]]; then
    _stat_icon="\033[32m✔\033[0m"  # Green check
  else
    _stat_icon="\033[31m✘\033[0m"  # Red cross
  fi

  printf "|   %b    | %-37s |\n" "$_stat_icon" "$_desc"
  echo "+--------+-----------------------------------------+"
}

# Function to print a pending row with a spinner or dots
print_pending_row() {
  local _desc=$1
  local _spinner=('|' '/' '-' '\\')
  local _spinner_length=${#_spinner[@]}
  local _i=0

  while true; do
    printf "\r|   %s    | %-37s |" "${_spinner[_i]}" "$_desc"
    _i=$((_i + 1))
    if [[ $_i -ge $_spinner_length ]]; then
      _i=0
    fi
    sleep 0.05
  done
}

# Function to stop the spinner and clear the line
stop_spinner() {
  kill $1
  wait $1 2>/dev/null
  printf "\r|        | %-37s |\n" ""
  echo "+--------+-----------------------------------------+"
}

# Main function to manage the table rows
manage_table() {
  print_header
  while true; do
    # Begining of each script of function:
    echo -n "Enter description: "
    read _desc

    # Pending until it succeed or errors out...
    echo -n "Enter status (success/failure/pending): "
    read _stat
    if [[ $_stat == "pending" ]]; then
      print_pending_row "$_desc" &
      spinner_pid=$!
      echo "Press Enter to stop the pending spinner..."
      read
      stop_spinner $spinner_pid
    else
      print_row "$_stat" "$_desc"
    fi
  done
}

# Call the main function to manage the table
manage_table