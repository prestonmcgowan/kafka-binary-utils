#!/bin/bash

function usage {
  echo "Example:"
  echo "kafka-binary-consumer.sh --bootstrap-server big-host-1.datadisorder.dev:9095 --topic binary_in_parts --group binary-consumer --max-messages 5 --timeout-ms 30000 -d tmp/binaries -w tmp/binary-in-progress"
  echo "kafka-binary-consumer.sh --bootstrap-server big-host-1.datadisorder.dev:9095 --topic binary_in_parts --group binary-consumer --max-messages 100 --timeout-ms 10000 -d tmp/binaries -w tmp/binary-in-progress --skip-consumer"
  echo "kafka-binary-consumer.sh --bootstrap-server big-host-1.datadisorder.dev:9095 --topic binary_in_parts --group binary-consumer --max-messages 100 --timeout-ms 10000 -d tmp/binaries -w tmp/binary-in-progress --skip-processing"
}

function loadPartFile {
  fileToProcess=${1}
  unset filename
  unset file_md5sum
  unset numParts
  unset partFilename
  unset part_base64_contents

  while read -r line
  do
    csv=$(echo $line | sed -e 's/{//;s/\}//;s/\"//g')
    IFS=',' read -r -a array <<< "$csv"

    for index in "${!array[@]}"
    do
      kvp="${array[index]}"
      key=$(echo $kvp | cut -f1 -d:)
      value=$(echo $kvp | cut -f2 -d: | xargs)
      case $key in 
          filename)
              filename=$value
              ;;
          file_md5sum)
              file_md5sum=$value
              ;;
          file_parts)
              numParts=$value
              ;;
          partname)
              partFilename=$value
              ;;
          part_base64_contents)
              part_base64_contents=$value
              ;;
      esac
    done
    
    echo "------------------------------------"
    echo "Processing : ${fileToProcess}"
    echo "filename   : ${filename}" 
    echo "file_md5sum: ${file_md5sum}"
    echo "file_parts : ${numParts}"
    echo "partname   : ${partFilename}"
    echo "part_base64_contents Length: ${#part_base64_contents}"
    echo "------------------------------------"

    # Write Metadata doc so we can check for file parts over multiple executions
    metadataFilename="${WORKINGDIR}/metadata_${file_md5sum}"
    echo "MetadataFilename: ${metadataFilename}"
    if [[ ! -f "${metadataFilename}" ]]; then
      echo "$filename,$file_md5sum,$numParts" > ${metadataFilename}
    fi

    # Write out this parts data
    echo "${part_base64_contents}" > ${WORKINGDIR}/${partFilename}

  done < ${fileToProcess}
}

# Do ENV check for proper base64 options
#  ubuntu uses `base64 -w`
#  mac uses `base64 -b`
DISTRO=`uname -v`
if [[ $DISTRO == *"Ubuntu"* ]]; then
  echo "Ubuntu Detected"
  B64_OPTS="-d"
elif [[ $DISTRO == *"Darwin"* ]]; then
  echo "MacOS Detected"
  B64_OPTS="-d -i"
  ## TODO: Check for mac md5sum. `brew install md5sha1sum`
else
  echo "Other OS Detected"
  echo "Only MacOS & Ubuntu are supported at this time"
  exit 1
fi



POSITIONAL_ARGS=()
SKIP_CONSUMER="FALSE"
SKIP_PROCESSING="FALSE"

while [[ $# -gt 0 ]]; do
  case $1 in
    --bootstrap-server)
      BOOTSTRAP_SERVER="$2"
      shift # past argument
      shift # past value
      ;;
    --consumer.config)
      CONSUMER_CONFIG="--consumer.config $2"
      shift # past argument
      shift # past value
      ;;
    -t|--topic)
      TOPIC="$2"
      shift # past argument
      shift # past value
      ;;
    --group)
      GROUP="$2"
      shift # past argument
      shift # past value
      ;;
    --max-messages)
      MAX_MESSAGES="$2"
      shift # past argument
      shift # past value
      ;;
    --timeout-ms)
      TIMEOUT_MS="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--binary-directory)
      BINDIR="$2"
      shift # past argument
      shift # past value
      ;;
    -w|--working-directory)
      WORKINGDIR="$2"
      shift # past argument
      shift # past value
      ;;
    --from-beginning)
      FROM_BEGINNING="--from-beginning"
      shift # past argument
      ;;
    --skip-consumer)
      SKIP_CONSUMER=TRUE
      shift
      ;;
    --skip-processing)
      SKIP_PROCESSING=TRUE
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


if [[ ! "$WORKINGDIR" || ! -d "$WORKINGDIR" ]]; then
  mkdir ${WORKINGDIR}
fi
if [[ ! "$BINDIR" || ! -d "$BINDIR" ]]; then
  mkdir ${BINDIR}
fi

# check if tmp dir was created
if [[ ! "$WORKINGDIR" || ! -d "$WORKINGDIR" ]]; then
  echo "Could not create working dir"
  exit 1
fi
if [[ ! "$BINDIR" || ! -d "$BINDIR" ]]; then
  echo "Could not create binary dir"
  exit 1
fi


echo "Bootstrap Server  = ${BOOTSTRAP_SERVER}"
echo "Consumer Config   = ${CONSUMER_CONFIG}"
echo "Topic             = ${TOPIC}"
echo "Binary Directory  = ${BINDIR}"
echo "Working Directory = ${WORKINGDIR}"
echo "Max Messages      = ${MAX_MESSAGES}"
echo "Message Timeout   = ${TIMEOUT_MS}"
echo "Skip Consumer     = ${SKIP_CONSUMER}"
echo "Skip Processing   = ${SKIP_PROCESSING}"
echo " ----------= Environmental =----------"
echo "base64 options    = ${B64_OPTS}"


if [[ $SKIP_CONSUMER != "TRUE" ]]; then
  WORKINGFILENAME="binary-consumer.data"
  WORKINGFILE=${WORKINGDIR}/${WORKINGFILENAME}

  rm ${WORKINGFILE}
  echo "Starting Consumer"
  kafka-console-consumer --bootstrap-server ${BOOTSTRAP_SERVER} --topic ${TOPIC} --timeout-ms ${TIMEOUT_MS} --group ${GROUP} --max-messages ${MAX_MESSAGES} ${FROM_BEGINNING} > ${WORKINGFILE}
  echo "Finished Consuming"
  NUMBIN=$(cat ${WORKINGFILE} | wc -l | xargs)

  if [[ $NUMBIN -le 0 ]]; then
    echo "No binary files to process"
  else 
    echo "Start Processing ${NUMBIN} parts..."
    loadPartFile $WORKINGFILE
    echo "Finished processing parts"
  fi
else
  echo "Skipped Kafka Consumer"
fi

if [[ $SKIP_PROCESSING != "TRUE" ]]; then
  echo "Build completed binary from parts"
  for md in ${WORKINGDIR}/metadata_*; 
  do
    echo "Metadata: $md"
    metadata=$(cat $md)
    filename=$(echo $metadata | cut -f1 -d,)
    file_md5sum=$(echo $metadata | cut -f2 -d,)
    numParts=$(echo $metadata | cut -f3 -d,)
    echo "filename: ${filename}" 
    echo "file_md5sum: ${file_md5sum}"
    echo "file_parts:  ${numParts}"

    partsFound=$(ls ${WORKINGDIR}/${filename}_* | wc -l)
    echo "Found ${partsFound} of ${numParts} for ${filename}"
    if [[ $partsFound -eq $numParts ]]; then
      echo "Found all parts for ${filename}, rebuild binary"
      
      DECODED=${WORKINGDIR}/${filename}.decoded
      if [[ -f ${DECODED} ]]; then 
        rm ${DECODED}
      fi

      for encoded in ${WORKINGDIR}/${filename}_*; do
        echo "Processing: ${encoded}"
        base64 $B64_OPTS ${encoded} >> ${DECODED}
      done
      
      binSum=($(md5sum ${DECODED}))
      if [[ ${binSum} == ${file_md5sum} ]]; then
        echo "MD5Sum match for ${filename}"
        mv ${DECODED} ${BINDIR}/${filename}
        echo "Rebuilt ${BINDIR}/${filename}"
        rm ${WORKINGDIR}/$filename* ${md}
      else
        echo "MD5Sum does not match match for ${filename}"
      fi
    fi
  done
else
  echo "Skipped post processing"
fi