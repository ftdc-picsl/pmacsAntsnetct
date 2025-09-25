#!/bin/bash

module load apptainer

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
memMb=16384

bsubCmd="bsub -cwd . " # Default bsub command

function help() {
cat << HELP
  `usage`

  This is a wrapper script to submit images for processing.

  Required args:

    -B bind_list
      Comma separated list of additional bind points for the container.

    -i input_antsnetct_dir
      Path to an antsnetct cross-sectional or longitudinal dataset. Parcellation output will be written to the same dataset.

    -v antsnetct_version
      Version of the antsnetct container to use.

  Optional args:

    -l log_prefix
      Prefix to the log file name under the input_antsnetct_dir/code/logs directory.

    -m mem_mb
      Memory in MB to request for the job (default=$memMB).

    -n nslots
      Number of slots to request for the job (default=$numSlots).

    -b bsub_cmd
      Command to use for submitting the job (default=$bsubCmd).
      Values must be quoted if including options, eg -b "bsub -q ftdc_normal"

    -u
      Print *antsnetct_parcellate* usage (rather than this script) and exit (only works in ibash session).

    Additional args after -- are passed to the antsnetct container.

HELP

}

antsnetctVersion=""
bindList=""
logPrefix="antsnetct"
inputBIDS=""
printUsage=0

while getopts "B:b:i:l:m:n:uv:h" opt; do
  case $opt in
    B) bindList=$OPTARG;;
    b) bsubCmd=$OPTARG;;
    h) help; exit 1;;
    i) inputBIDS=$OPTARG;;
    l) logPrefix=$OPTARG;;
    m) memMb=$OPTARG;;
    n) numSlots=$OPTARG;;
    u) printUsage=1;;
    v) antsnetctVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

templateflow_home="/project/ftdc_pipeline/templateflow-d259ce39a"

# Makes python output unbuffered
export APPTAINERENV_PYTHONUNBUFFERED=1
export APPTAINERENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$numSlots
export APPTAINERENV_TMPDIR="/tmp"
export APPTAINERENV_TEMPLATEFLOW_HOME=${templateflow_home}

shift $((OPTIND-1))

if [[ $printUsage -gt 0 ]]; then
    apptainer exec --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif antsnetct_parcellate --help
    exit 1
fi

echo "Checking bind list"

# Split the string by commas into an array
IFS=',' read -r -a bindPaths <<< "$bindList"

for item in "${bindPaths[@]}"
do
  # Split the item by colon to get pathA and pathB
  IFS=':' read -r -a paths <<< "$item"
  pathLocal="${paths[0]}"
  # if paths has length 1, then pathB is the same as pathA
  if [[ ${#paths[@]} -eq 1 ]]; then
    paths[1]="${paths[0]}"
  fi

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
    bindList="${bindList},${inputBIDS}:${inputBIDS}"
    echo "Mount: ${inputBIDS}  to  ${inputBIDS}"
fi

# templateflow is required
bindList="${bindList},${templateflow_home}:${templateflow_home}"
echo "Mount: ${templateflow_home}  to  ${templateflow_home}"

# Create logs directory if needed (should not be)
mkdir -p ${inputBIDS}/code/logs

date=`date +%Y%m%d`

if [[ ! -f $repoDir/containers/antsnetct-${antsnetctVersion}.sif ]]; then
  echo "Container antsnetct-${antsnetctVersion}.sif not found in $repoDir/containers"
  exit 1
fi

$bsubCmd -o "${inputBIDS}/code/logs/${logPrefix}_${date}_%J.txt" -J antsnetct -n $numSlots \
  -R "rusage[mem=${memMb}MB]" \
  apptainer exec \
    --cleanenv --no-home --home /home/antspyuser \
    --bind /scratch:/tmp,$bindList \
    $repoDir/containers/antsnetct-${antsnetctVersion}.sif \
    antsnetct_parcellate \
    --input-dataset ${inputBIDS} \
    "$@"

