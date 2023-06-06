# Helper functions to manage gitea
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

# Print info messages
#   args:
#     (1) message
function print_info {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${GREENB_COLOR}${message}${END_COLOR}" ;
}

# Print error messages
#   args:
#     (1) message
function print_error {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${REDB_COLOR}${message}${END_COLOR}" ;
}
