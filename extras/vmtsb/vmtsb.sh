#!/usr/bin/env bash

# This funcion allows for easy batch operations of VM machines by user, state
# and action desired.
# You can add the file to your shell sourcing and use vmtsb in a crontab to
# automatically suspend your vms at the end of the day.

vmtsb() {

  if ! command -v gcloud &> /dev/null; then
    echo "gcloud is not installed"
    return 1
  fi

  # listInstances in all zones
  # Arg1: Owner tag
  listInstances() {
    if [[ ! -z $1 ]]; then
      gcloud compute instances list --filter "(metadata.tetrate_owner=${OWNER} OR labels.tetrate_owner=${OWNER})" 2> /dev/null
      return 0
    fi
    gcloud compute instances list
  }

  # Formatting
  bold=$(tput bold)
  normal=$(tput sgr0)

  # # Clean OPTARG as it somehow keep carche from previous runs
  STATE=""
  OWNER=""
  ACTION=""
  ZONE=""
  LIST=""


  usage() {
    cat << EOF
    $bold Usage: $normal
    MTSB: Manage your VM TSB instances with ease
      -h      Help menu
      -l      Lists all the instances from the owner in all zones
      -o      (Required) Owner label. See https://github.com/tetrateio/tetrate/blob/master/cloud/docs/gcp/labels.md
      -s      Status (RUNNING|SUSPENDED|TERMINATED)
      -a      Action to perform (resume, suspend, stop, start, delete). Recommended for speed are resume and suspend.
      -z      GCP zone to work with. (Defaults to europe-west9-a)

      Example:
        Take all ric's machines which are in running state and suspend them:
        vmtsb -o ric -s RUNNING -a suspend
EOF
  }

  OPTSTRING="hlo:s:a:z:"

  while getopts ${OPTSTRING} arg; do
    case ${arg} in
      h)
        usage
        return 0
      ;;
      l)
        LIST="true"
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
      z)
        ZONE="${OPTARG}"
      ;;
      ?)
        echo "Invalid option."
        usage
        return 1
      ;;
    esac
  done

  if [[ ! -z "${LIST}" ]]; then
    echo "Listing all instances from Owner: ${OWNER:-all}"
    listInstances ${OWNER}
    return 0
  fi

  if [[ -z "${OWNER}" ]]; then
    echo "Error: Owner flag is required."
    usage
    return 1
  fi

  if [[ -z "${ACTION}" ]]; then
    echo "No action provided. Listing all instances from Owner ${OWNER}"
    listInstances ${OWNER}
    return 0
  fi

  # Default values
  # DEF_ZONE="europe-west9-a"
  # ZONE=${ZONE:-europe-west9-a}


  filter="(metadata.tetrate_owner=${OWNER} OR labels.tetrate_owner=${OWNER})"
  echo "Checking...:\n\ttetrate_owner: ${OWNER}\n\tstate: ${STATE}\n\taction: ${ACTION}\n\tzone: ${ZONE}\n"

  if [[ ! -z ${STATE} ]]; then
    filter="${filter} AND status=${STATE}"
  fi

  if [[ ! -z ${ZONE} ]]; then
    filter="${filter} AND zone=${ZONE}"
  fi

  names=$(gcloud compute instances list --filter "${filter}" | tail +2 | awk '{ print $1 }')

  if [[ -z ${names} ]]; then
    echo "There's no instances in ${STATE} state\n"
    return 0
  fi

  echo "Working on instances:\n${names}"

  while IFS= read -r instance; do
    gcloud compute instances ${ACTION} ${instance}
  done <<< "${names}"

  echo "\n${bold}This are your current instances after the operation${normal}"
  echo "Please remember to save us money by suspend or stop them with:\nvmstb -o <your-tag> -a suspend\n"
  listInstances
  return 0
}

# If the script is executed directly, run the function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    vmtsb $@
fi