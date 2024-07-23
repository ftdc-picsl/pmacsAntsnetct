#!/bin/bash

module load singularity/3.8.3

scriptPath=$(readlink -f "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

function usage() {
  echo "Usage:
  $0 -B bind_list -l log_prefix -m mem_mb -n nslots -v antsnetct_version -- [antsnetct options]

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
      Comma separated list of bind points for the container.

    -l log_prefix
      Prefix to the log file for the submitted job, on the host file system. The script
      will append _{date}_{jobid}.txt.

    -v antsnetct_version
      Version of the antsnetct container to use.

  Optional args:

    -m mem_mb
      Memory in MB to request for the job (default=$memMB).

    -n nslots
      Number of slots to request for the job (default=$numSlots).

    -b bsub_cmd
      Command to use for submitting the job (default=$bsubCmd).
      Values must be quoted if including options, eg -b "bsub -q ftdc_normal"

HELP

}

antsnetctVersion=""
bindList=""
logPrefix=""

while getopts "B:b:l:m:n:v:h" opt; do
  case $opt in
    B) bindList=$OPTARG;;
    b) bsubCmd=$OPTARG;;
    h) help; exit 1;;
    l) logPrefix=$OPTARG;;
    m) memMb=$OPTARG;;
    n) numSlots=$OPTARG;;
    v) antsnetctVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

shift $((OPTIND-1))

date=`date +%Y%m%d`

# Makes python output unbuffered
export SINGULARITYENV_PYTHONUNBUFFERED=1

export SINGULARITYENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$numSlots
export SINGULARITYENV_TF_NUM_INTEROP_THREADS=$numSlots
export SINGULARITYENV_TF_NUM_INTRAOP_THREADS=$numSlots
export SINGULARITYENV_TMPDIR="/tmp"

export SINGULARITYENV_TEMPLATEFLOW_HOME=/opt/templateflow

if [[ ! -f $repoDir/containers/antsnetct-${antsnetctVersion}.sif ]]; then
  echo "Container antsnetct-${antsnetctVersion}.sif not found in $repoDir/containers"
  exit 1
fi

$bsubCmd -o "${logPrefix}_${date}_%J.txt" -J antsnetct -n $numSlots \
  -R "rusage[mem=${memMb}MB]" \
  singularity run \
    --cleanenv --no-home --home /home/antspyuser \
    --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp,$bindList \
    $repoDir/containers/antsnetct-${antsnetctVersion}.sif \
    "$@"

