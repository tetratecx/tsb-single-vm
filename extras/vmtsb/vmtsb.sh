# This funcion allows for easy batch operations of VM machines by user, state 
# and action desired.
# You can add the file to your shell sourcing and use vmtsb in a crontab to
# automatically suspend your vms at the end of the day.

vmtsb() {
  
  if ! command -v gcloud &> /dev/null; then
    echo "gcloud is not installed"
    return 1
  fi

  # Formatting
  bold=$(tput bold)
  normal=$(tput sgr0)

  # Clean OPTARG 
  STATE=""
  OWNER=""
  ACTION=""

  OPTSTRING="ho:s:a:"
 
  while getopts ${OPTSTRING} arg; do
    case ${arg} in
      h)
        echo "$bold Usage: $normal"
        cat << EOF

$bold---VMTSB ---$normal

Manage your VM TSB instances with ease
  -h      Help menu
  -o      Owner tag. See https://github.com/tetrateio/tetrate/blob/master/cloud/docs/gcp/labels.md
  -s      Status (RUNNING|SUSPENDED|TERMINATED)
  -a      Action to perform (resume, suspend, stop, start, delete). Recommended for speed are resume and suspend.

  E.g.:
    Take all ric's machines which are in running state and suspend them
    vmtsb -o ric -s RUNNING -a SUSPEND
EOF
      return 0
      ;;
      o)
        OWNER="${OPTARG}"
      ;;
      s)
        STATE="${OPTARG}"
      ;;
      a)
        ACTION="${OPTARG}"
      ;;
      ?)
        echo "Invalid options. Please run -h flag for help"
        return 1
      ;;
    esac
  done
  
  # Default values
  OWNER=${OWNER:-ric}
  STATE=${STATE:-}
  ACTION=${ACTION:-suspend}

  
  echo "Checking\ntetrate_owner: ${OWNER}\nstate: ${STATE}\naction: ${ACTION}"
  if [[ -z ${STATE} ]]; then
    names=$(gcloud compute instances list --filter "metadata.tetrate_owner=${OWNER}" | tail +2 | awk '{ print $1 }')
  else
    names=$(gcloud compute instances list --filter "metadata.tetrate_owner=${OWNER} AND status=${STATE}" | tail +2 | awk '{ print $1 }')
  fi 

  if [[ -z ${names} ]]; then
    echo "There's no instances in ${STATE} state"
    return 0
  fi
  
  echo "Working on instances:\n${names}"
 
  for instance in ${names}; do
    gcloud compute instances ${ACTION} ${instance}
  done
  
  echo "\n${bold}This are your current instances after the operation${normal}"
  echo "Please remember to save us money by suspend or stop them with:\nvmstb -o <your-tag> -a suspend\n"
  gcloud compute instances list --filter "metadata.tetrate_owner=${OWNER}"

}
