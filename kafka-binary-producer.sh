#!/bin/bash

FILE=$1

echo $FILE

split -b 512k -d ../${FILE} ${FILE}_
file_md5sum=($(md5sum ../${FILE}))
numParts=`ls ${FILE}_* | wc -l`
for f in ${FILE}_*; do
  mv ${f} ${f}.decoded
  echo -n "{" > ${f}.json
  echo -n "\"filename\": \"${FILE}\"," >> ${f}.json
  echo -n "\"file_md5sum\": \"${file_md5sum}\"," >> ${f}.json
  echo -n "\"file_parts\": ${numParts}," >> ${f}.json
  echo -n "\"partname\": \"${f}\"," >> ${f}.json
  echo -n "\"part_base64_contents\": \"" >> ${f}.json
  base64 -w 0 ${f}.decoded >> ${f}.json
  echo -n "\"" >> ${f}.json
  echo -n "}" >> ${f}.json


  cat ${f}.json | kafka-console-producer --bootstrap-server localhost:9095 --topic binary_in_parts
done
