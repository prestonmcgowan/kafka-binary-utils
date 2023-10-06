#!/bin/bash

function usage {
  echo "Example:"
  echo "kafka-binary-producer.sh --bootstrap-server big-host-1.datadisorder.dev:9095 --topic binary_in_parts --filepath ~/Downloads/tso.png"}
}

# deletes the temp directory
function cleanup {      
  rm -rf "$TMPDIR"
  echo "Deleted temp working directory $TMPDIR"
}

# Do ENV check for proper base64 options
#  ubuntu uses `base64 -w`
#  mac uses `base64 -b`
DISTRO=`uname -v`
if [[ $DISTRO == *"Ubuntu"* ]]; then
  echo "Ubuntu Detected"
  B64_OPTS=" -w 0"
elif [[ $DISTRO == *"Darwin"* ]]; then
  echo "MacOS Detected"
  B64_OPTS=" -b 0 -i"
  ## TODO: Check for mac md5sum. `brew install md5sha1sum`
else
  echo "Other OS Detected"
  echo "Only MacOS & Ubuntu are supported at this time"
  exit 1
fi



POSITIONAL_ARGS=()
DRYRUN=FALSE
BYTE_COUNT="512k"

while [[ $# -gt 0 ]]; do
  case $1 in
    --bootstrap-server)
      BOOTSTRAP_SERVER="$2"
      shift # past argument
      shift # past value
      ;;
    --producer.config)
      PRODUCER_CONFIG="--producer.config $2"
      shift # past argument
      shift # past value
      ;;
    -t|--topic)
      TOPIC="$2"
      shift # past argument
      shift # past value
      ;;
    -f|--filepath)
      FILEPATH="$2"
      shift # past argument
      shift # past value
      ;;
    -b)
      BYTE_COUNT="$2"
      shift # past argument
      shift # past value
      ;;
    --dry-run)
      DRYRUN=TRUE
      shift
      ;;
    -v|--verbose)
      VERBOSE=TRUE
      shift
      ;;
    -h|--help)
      usage
      exit 1
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters



# the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# the temp directory used, within $DIR
# omit the -p parameter to create a temporal directory in the default location
TMPDIR=`mktemp -d`

# check if tmp dir was created
if [[ ! "$TMPDIR" || ! -d "$TMPDIR" ]]; then
  echo "Could not create temp dir"
  exit 1
fi


FILE=$(basename ${FILEPATH})
#TMPDIR=tmp_${FILE}
PWD=$(pwd)



echo "Bootstrap Server  = ${BOOTSTRAP_SERVER}"
echo "Producer Config   = ${PRODUCER_CONFIG}"
echo "Topic             = ${TOPIC}"
echo "Filepath          = ${FILEPATH}"
echo "Dry Run           = ${DRYRUN}"
echo " ----------= Environmental =----------"
echo "base64 options    = ${B64_OPTS}"
echo "Temp Directory    = ${TMPDIR}"


echo "Start processing: ${FILE}"
cd $TMPDIR
split -b ${BYTE_COUNT} -a 6 -d ${FILEPATH} ${FILE}_
file_md5sum=($(md5sum ${FILEPATH}))
numParts=$(ls ${FILE}_* | wc -l | xargs)
f_json=$FILE.json
for f in ${FILE}_*; do
  #f_json=${f}.json
  echo -n "{" >> ${f_json}
  echo -n "\"filename\": \"${FILE}\"," >> ${f_json}
  echo -n "\"file_md5sum\": \"${file_md5sum}\"," >> ${f_json}
  echo -n "\"file_parts\": ${numParts}," >> ${f_json}
  echo -n "\"partname\": \"${f}\"," >> ${f_json}
  echo -n "\"part_base64_contents\": \"" >> ${f_json}
  base64 $B64_OPTS ${f} | tr -d '\n' >> ${f_json}
  echo -n "\"" >> ${f_json}
  echo -n "}" >> ${f_json}
  echo >> ${f_json}
done

if [[ $DRYRUN == "TRUE" ]]; then
  echo "Built only: ${f_json}"
else
  echo "Producing: ${f_json}"
  cat ${f_json} | kafka-console-producer --bootstrap-server ${BOOTSTRAP_SERVER} ${PRODUCER_CONFIG} --property compression.type=gzip --topic ${TOPIC}
fi

cd $PWD
if [[ $DRYRUN == "TRUE" ]]; then
  echo "Directory [${TMPDIR}] not deleted"
else
  cleanup
fi
