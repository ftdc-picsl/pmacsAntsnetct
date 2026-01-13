#!/bin/bash

scriptPath=$(readlink -f "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

function usage() {
  echo "Usage:
  $0 -B bind_list -v antsnetct_version antsnetct_executable input_array_file -- [antsnetct options]

  This is a helper script to run antsnetct array jobs. It should not be executed directly.

  The script requires that the environment variable LSB_JOBINDEX is set (this is done automatically
  when submitting an array job with bsub). Either a participant label or participant,session is read
  from the corresponding line of the input_array_file.

  $0 [-h] for help
  "
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

function help() {
cat << HELP
  `usage`

  This is a wrapper script to submit images for processing.

  Required args:

    -B bind_list
      Comma separated list of additional bind points for the container.

    -v antsnetct_version
      Version of the antsnetct container to use.

    antsnetct_executable
      antsnetct command to run (e.g., antsnetct, antsnetct_parcellate).

    input_array_file:
      Text file of participant labels or participant,session pairs (comma separated) to be processed.


  Additional args after -- are passed to the antsnetct container. All antsnetct args except for --participant and
  --session must be specified by the calling script.

HELP

}

antsnetctVersion=""
bindList=""
inputArrayFile=""
templateflowHome="/project/ftdc_pipeline/templateflow-d259ce39a"

while getopts "B:v:h" opt; do
  case $opt in
    B) bindList=$OPTARG;;
    h) help; exit 1;;
    v) antsnetctVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

shift $((OPTIND-1))
antsnetctExecutable=$1
inputArrayFile=$2
shift 2
# shift away the  '--', but check user provided it
if [[ "$1" == "--" ]]; then
  shift
fi

if [[ ! -f $repoDir/containers/antsnetct-${antsnetctVersion}.sif ]]; then
  echo "Container antsnetct-${antsnetctVersion}.sif not found in $repoDir/containers"
  exit 1
fi

if [[ -z "$inputArrayFile" || ! -f "$inputArrayFile" ]]; then
  echo "Input array file $inputArrayFile not found"
  exit 1
fi

lineNum=$LSB_JOBINDEX
lineContent=$(sed -n "${lineNum}p" "$inputArrayFile")

if [[ -z "$lineContent" ]]; then
  echo "No content found in line $lineNum of $inputArrayFile"
  exit 1
fi

# split lineContent by comma
IFS=',' read -r -a subjSess <<< "$lineContent"

participantArgs=""

# determine if we have participant only or participant,session
participantArgs=(--participant "${subjSess[0]}")
if [[ ${#subjSess[@]} -eq 2 ]]; then
  participantArgs+=(--session "${subjSess[1]}")
fi

apptainer exec \
  --cleanenv --no-home --home /home/antspyuser \
  --bind $bindList \
  $repoDir/containers/antsnetct-${antsnetctVersion}.sif \
  ${antsnetctExecutable} \
  "${participantArgs[@]}" \
  "$@"

