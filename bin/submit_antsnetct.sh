#!/bin/bash

module load singularity/3.8.3

scriptPath=$(readlink -f "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

function usage() {
  echo "Usage:
  $0 -B bind_list -i input_bids -m mem_mb -n nslots -o output_bids -v antsnetct_version -- [antsnetct options]

  $0 [-h] for help
  "
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

numSlots=2
memMb=8192

bsubCmd="bsub -cwd . " # Default bsub command

function help() {
cat << HELP
  `usage`

  This is a wrapper script to submit images for processing.

  Required args:

    -B bind_list
      Comma separated list of additional bind points for the container.

    -i input_bids
      Path to the input BIDS directory on the local file system. For longitudinal processing,
      this should be the path to the cross-sectional processing for the subject. This will be bound
      to the same path in the container.

    -o output_bids
      Path to the output BIDS directory on the local file system. This will be bound to the same
      path in the container.

    -v antsnetct_version
      Version of the antsnetct container to use.

  Optional args:

    -l log_prefix
      Prefix to the log file name under the output_bids/code/logs directory.

    -m mem_mb
      Memory in MB to request for the job (default=$memMB).

    -n nslots
      Number of slots to request for the job (default=$numSlots).

    -b bsub_cmd
      Command to use for submitting the job (default=$bsubCmd).
      Values must be quoted if including options, eg -b "bsub -q ftdc_normal"

    -u cx|longitudinal
      Print *antsnetct* usage (rather than this script) for the specified mode and exit.

    Additional args after -- are passed to the antsnetct container.

HELP

}

antsnetctVersion=""
bindList=""
logPrefix="antsnetct"
inputBIDS=""
outputBIDS=""
whichUsage=""

while getopts "B:b:i:l:m:n:o:u:v:h" opt; do
  case $opt in
    B) bindList=$OPTARG;;
    b) bsubCmd=$OPTARG;;
    h) help; exit 1;;
    i) inputBIDS=$OPTARG;;
    l) logPrefix=$OPTARG;;
    m) memMb=$OPTARG;;
    n) numSlots=$OPTARG;;
    o) outputBIDS=$OPTARG;;
    u) whichUsage=$OPTARG;;
    v) antsnetctVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done


# Makes python output unbuffered
export SINGULARITYENV_PYTHONUNBUFFERED=1
export SINGULARITYENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$numSlots
export SINGULARITYENV_TMPDIR="/tmp"
export SINGULARITYENV_TEMPLATEFLOW_HOME=/opt/templateflow

if [[ -n $whichUsage ]]; then
  if [[ $whichUsage == "cx" ]]; then
    singularity run --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif --help
    exit 1
  elif [[ $whichUsage == "longitudinal" ]]; then
    singularity run --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif --longitudinal --help
    exit 1
  else
    echo "Unknown usage $whichUsage"
    exit 1
  fi
fi

shift $((OPTIND-1))

echo "Checking bind list"

# Split the string by commas into an array
IFS=',' read -r -a bindPaths <<< "$bindList"

for item in "${bindPaths[@]}"
do
  # Split the item by colon to get pathA and pathB
  IFS=':' read -r -a paths <<< "$item"
  pathLocal="${paths[0]}"

  if [[ ! -d "$pathLocal" ]] && [[ ! -f "$pathLocal" ]]; then
    echo "Path $pathLocal does not exist"
    exit 1
  fi
  echo "Mount: ${paths[0]}  to  ${paths[1]}"
done

if [[ ! -d  "$inputBIDS" ]]; then
  echo "Input BIDS directory $inputBids does not exist"
  exit 1
else
    bindList="${bindList},${inputBIDS}:${inputBIDS}:ro"
    echo "Mount: ${inputBids}  to  ${inputBids}"
fi

if [[ ! -d  "$outputBIDS" ]]; then
  echo "Creating output BIDS directory $outputBIDS"
  mkdir -p $outputBIDS
fi

bindList="${bindList},${outputBIDS}:${outputBIDS}"
# Create logs directory
mkdir -p ${outputBIDS}/code/logs

echo "Mount: ${outputBIDS}  to  ${outputBIDS}"

date=`date +%Y%m%d`

if [[ ! -f $repoDir/containers/antsnetct-${antsnetctVersion}.sif ]]; then
  echo "Container antsnetct-${antsnetctVersion}.sif not found in $repoDir/containers"
  exit 1
fi

$bsubCmd -o "${outputBIDS}/code/logs/${logPrefix}_${date}_%J.txt" -J antsnetct -n $numSlots \
  -R "rusage[mem=${memMb}MB]" \
  singularity run \
    --cleanenv --no-home --home /home/antspyuser \
    --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp,$bindList \
    $repoDir/containers/antsnetct-${antsnetctVersion}.sif \
    --input-dataset ${inputBIDS} \
    --output-dataset ${outputBIDS} \
    "$@"

