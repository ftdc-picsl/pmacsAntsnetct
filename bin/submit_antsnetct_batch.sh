#!/bin/bash

module load apptainer

scriptPath=$(readlink -f "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

function usage() {
  echo "Usage:
  $0 \\
    -B bind_list \\
    -i input_bids \\
    -o output_bids \\
    -v antsnetct_version \\
    [options] \\
    antsnetct_executable \\
    batch_input_file \\
    -- [antsnetct options]

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

templateflowHome="/project/ftdc_pipeline/templateflow-d259ce39a"


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
      path in the container. Required for antsnetct, but not used for antsnetct_parcellate, which
      outputs to the input dataset.

    -v antsnetct_version
      Version of the antsnetct container to use.

    antsnetct_executable
      Specify which antsnetct command to run. Valid values are:
        antsnetct
        antsnetct_parcellate

    batch_input_file
      Text file with one participant or participant,session per line. Do not include the sub- or ses- prefixes.


  Optional args:

    -l log_prefix
      Prefix to the log file name under the output_bids/code/logs directory.

    -m mem_mb
      Memory in MB to request for each job (default=$memMb).

    -n nslots
      Number of slots to request for each job (default=$numSlots).

    -N concurrency
      Number of concurrent jobs to run (default=unlimited). This allows you to limit the number of concurrent jobs.
      Note that the total number of slots required is nslots * concurrency.

    -b bsub_cmd
      Command to use for submitting the job (default=$bsubCmd).
      Values must be quoted, eg -b "bsub -q ftdc_normal"

    -u cx|longitudinal|parcellate
      Print *antsnetct* usage (rather than this script) for the specified mode and exit (only works in ibash session).


    Additional args after -- are passed to the antsnetct container. It is not necessary to specify
      --participant
      --session
      --input-dataset
      --output-dataset
    as these are read from the batch input file or the input/output BIDS paths passed to this script.

    TEMPLATEFLOW_HOME is set to

        $templateflowHome

    and will be added to the bind list for the container.



HELP

}

antsnetctVersion=""
bindList=""
concurrency=0 # 0 means unlimited
logPrefix=""
inputBIDS=""
outputBIDS=""
whichUsage=""

while getopts "B:N:b:i:l:m:n:o:u:v:h" opt; do
  case $opt in
    B) bindList=$OPTARG;;
    b) bsubCmd=$OPTARG;;
    h) help; exit 1;;
    i) inputBIDS=$OPTARG;;
    l) logPrefix=$OPTARG;;
    m) memMb=$OPTARG;;
    n) numSlots=$OPTARG;;
    N) concurrency=$OPTARG;;
    o) outputBIDS=$OPTARG;;
    u) whichUsage=$OPTARG;;
    v) antsnetctVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

shift $((OPTIND-1))
antsnetctExecutable=$1
batchInputFile=$2
shift 2
# shift away the  '--', but check user provided it
if [[ "$1" == "--" ]]; then
  shift
fi

if [[ -z "$logPrefix" ]]; then
  logPrefix="${antsnetctExecutable}"
fi

if [[ ${antsnetctExecutable} != "antsnetct" && ${antsnetctExecutable} != "antsnetct_parcellate" ]]; then
  echo "Invalid antsnetct executable: $antsnetctExecutable"
  echo "Valid values are: antsnetct, antsnetct_parcellate"
  exit 1
fi

# Set environment variables for apptainer
export APPTAINERENV_PYTHONUNBUFFERED=1
export APPTAINERENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$numSlots
export APPTAINERENV_TMPDIR="/tmp"
export APPTAINERENV_TEMPLATEFLOW_HOME=${templateflowHome}

if [[ -n $whichUsage ]]; then
  if [[ $whichUsage == "cx" ]]; then
    apptainer run --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif --help
    exit 1
  elif [[ $whichUsage == "longitudinal" ]]; then
    apptainer run --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif --longitudinal --help
    exit 1
  elif [[ $whichUsage == "parcellate" ]]; then
    apptainer exec --cleanenv --no-home --home /home/antspyuser \
        --bind /project/ftdc_pipeline/templateflow-d259ce39a:/opt/templateflow,/scratch:/tmp \
        $repoDir/containers/antsnetct-${antsnetctVersion}.sif antsnetct_parcellate --help
  else
    echo "Unknown usage $whichUsage"
    exit 1
  fi
fi


if [[ ! -f $batchInputFile ]]; then
  echo "Batch input file $batchInputFile not found"
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
fi

date=`date +%Y%m%d`
ioArgs=""
logOption=""

if [[ ${antsnetctExecutable} == "antsnetct" ]]; then

  if [[ -z "$bindList" ]]; then
    bindList="${inputBIDS}:${inputBIDS}:ro"
  else
    bindList="${bindList},${inputBIDS}:${inputBIDS}:ro"
  fi

  echo "Mount: ${inputBIDS}  to  ${inputBIDS}"

  ioArgs="--input-dataset ${inputBIDS} --output-dataset ${outputBIDS}"
  logOption="${outputBIDS}/code/logs/${logPrefix}_${date}_%J_%I.txt"

  # Create output and logs directory as needed
  if [[ ! -d  "$outputBIDS" ]]; then
    echo "Creating output BIDS directory $outputBIDS"
    mkdir -p $outputBIDS
  fi

  mkdir -p ${outputBIDS}/code/logs

  bindList="${bindList},${outputBIDS}:${outputBIDS}"
  echo "Mount: ${outputBIDS}  to  ${outputBIDS}"

elif [[ ${antsnetctExecutable} == "antsnetct_parcellate" ]]; then
  # Parcellate outputs to input dataset - mount read-write
  if [[ -z "$bindList" ]]; then
    bindList="${inputBIDS}:${inputBIDS}"
  else
    bindList="${bindList},${inputBIDS}:${inputBIDS}"
  fi
  echo "Mount: ${inputBIDS}  to  ${inputBIDS}"
  ioArgs="--input-dataset ${inputBIDS}"
  logOption="${inputBIDS}/code/logs/${logPrefix}_${date}_%J_%I.txt"
else
  echo "Unknown antsnetct executable: ${antsnetctExecutable}"
  exit 1
fi

# templateflow is required
bindList="${bindList},${templateflowHome}:${templateflowHome}"
echo "Mount: ${templateflowHome}  to  ${templateflowHome}"

if [[ ! -f $repoDir/containers/antsnetct-${antsnetctVersion}.sif ]]; then
  echo "Container antsnetct-${antsnetctVersion}.sif not found in $repoDir/containers"
  exit 1
fi

numArrayElements=$(wc -l < $batchInputFile)
arrayOption="${antsnetctExecutable}[1-$numArrayElements]"
if [[ $concurrency -gt 0 ]]; then
  arrayOption="${antsnetctExecutable}[1-$numArrayElements]%$concurrency"
fi

$bsubCmd \
  -o "${logOption}" \
  -J "${arrayOption}" \
  -n $numSlots \
  -R "rusage[mem=${memMb}MB]" \
  ${scriptDir}/run_antsnetct_array_element.sh \
  -B "$bindList" \
  -v "$antsnetctVersion" \
  ${antsnetctExecutable} \
  "${batchInputFile}" \
    -- \
    ${ioArgs} \
    "$@"

