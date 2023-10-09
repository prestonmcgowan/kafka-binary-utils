# kafka-binary-utils
Support moving large binary files with Kafka as the delivery mechanism

## Why build this?

I work on several secured systems and require FIPS controls and many internet available tools are not allowed on the network.
I have the need to move binary files from one network to another and maybe across other disconnected environments where a SFTP or TCP session would fail.
Utilizing Kafka as a transmission and dissemination mechanism allows for a greater delivery, routing, and recovery than SFTP or S3 where the network access are not approved.

If you have S3 access, I recommend you take a look at the Claim Check Pattern.
* [Claim Check pattern example in Scala](https://github.com/ksilin/claimcheck)
* [Handling Large Messages with Apache Kafka (CSV, XML, Image, Video, Audio, Files](https://www.kai-waehner.de/blog/2020/08/07/apache-kafka-handling-large-messages-and-files-for-image-video-audio-processing/)

## How does this work?

### kafka-binary-producer

The `kafka-binary-producer` makes use of several well known scripting tricks to make large files smaller for lossy network connections. Once we break up the file using the Linux standard `split` command we build a JSON file with the file's details and a Base64 encoded content for each piece. Now that we have all the pieces with original file metadata and piece metadata, we can send it to Kafka for dissemination. We utilize `kafka-console-producer` to send the JSON documents. The data is not consumable on the Kafka Topic.

#### Options

| Option | Description |
| ------ | ----------- |
| --bootstrap-server  <String: server to connect to> | **REQUIRED**: The server(s) to connect to. The broker liststring in the form HOST1:PORT1,HOST2:PORT2. |
| -t or --topic <String: topic> | **REQUIRED**: The topic id to produce messages to. |
| -f or --filepath <String: filepath > | **REQUIRED**: The file to operate on. |
| -b <String: byte_count[K,k]> | Create split files byte_count bytes in length.  If k or K is appended to the number, the file is split into byte_count kilobyte pieces. This is the amount of binary bytes that will be sent to Base64 encoding. This setting is not the size of the resulting Kafka message. Default: 512k |
| --producer.config <String: config file> | Producer config properties file. Note: `compression.type=gzip` is automatically included |
| --dry-run | Just break up the document, but don't send to Kafka. |
| -v or --verbose | More logging is printed. |
| -h or --help | Print options. |

#### Examples

Upload the identified file to Kafka. (default 512k split pieces)
 ```shell
 kafka-binary-producer.sh --bootstrap-server fqdn:9095 \
  or --topic binary_in_parts --filepath /data/isos/centos.iso
 ```

Upload the identified file to Kafka and use 100k split pieces.
 ```shell
 ./kafka-binary-producer.sh --bootstrap-server fqdn:9095 \
  or --topic binary_in_parts --filepath ~/Downloads/something.png \
   -b 100k
 ```

## kafka-binary-consumer

The `kafka-binary-consumer` pulls all the batches of documents off the Kafka Topic and attempts to rebuild the binary. The script pulls the configured batch size of messages and writes each message to a configured holding directory. Once all pieces have been collected, we can try to recreate the original binary. The reconstructed binary's md5sum will be verified with the original file's md5sum. If their are pieces missing to rebuild the document, we do not process the binary and we do not delete the pieces out of the holding directory. Running the script again will grab more messages and the file rebuild will be processed on next execution.

#### Options

| Option | Description |
| ------ | ----------- |
| --bootstrap-server <String: server to connect to> | **REQUIRED**: The server(s) to connect to. |
| -t or --topic <String: topic>| **REQUIRED**: The topic id to consume messages from. |
| --group <String: consumer group id> | **REQUIRED**: The consumer group id of the consumer. |
| --max-messages <Integer: num_messages> | **REQUIRED**: The maximum number of messages to consume before processing the pieces. Recommend numbers in the range of 50-200 depending on the size of the pieces. |
| --timeout-ms <Integer: timeout_ms> | **REQUIRED**: Wait for this amount of time to receive the messages, exit if no message is available for consumption for the specified interval. Recommendation: 10000 |
| -d or --binary-directory | **REQUIRED**: The directory to save fully consumed and validated binaries. |
| -w or --working-directory | **REQUIRED**: The directory to save pieces to while attempting to rebuild the binaries. |
| --consumer.config <String: config file> | Consumer config properties file. Note that [consumer-property] takes precedence over this config. |
| --from-beginning | If the consumer does not already have an established offset to consume from, start with the earliest message present in the log rather than the latest message. |
| --skip-consumer | Do not start the Kafka Consumer. |
| --skip-processing | Do not attempt to process the pieces. |
| -v or --verbose | More logging is printed. |
| -h or --help | Print options. |

#### Examples


Consume from Kafka Topic `binary_in_parts` in batches of 50 and only way for 10 seconds to start processing.
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 50 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress 
```


Consume from Kafka Topic `binary_in_parts` in batches of 200 and only way for 10 seconds to start processing.
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 200 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress 
```


Consume from Kafka Topic `binary_in_parts` in batches of 500 and only way for 10 seconds to start processing.
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 500 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress 
```


Consume from Kafka Topic `binary_in_parts` in batches of 100 and only way for 30 seconds to start processing.
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 100 --timeout-ms 30000 \
  -d tmp/binaries -w tmp/binary-in-progress 
```


Skip consuming from Kafka Topic and just start processing.
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 100 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress \
 or --skip-consumer
```

Consume from Kafka Topic and just skip processing.


```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 100 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress \
 or --skip-processing
```


Skip consumption and processing. Not sure why, but you could  ¯\_(ツ)_/¯
```shell
kafka-binary-consumer.sh --bootstrap-server fqdn:9095 --topic binary_in_parts \
 or --group binary-consumer --max-messages 100 --timeout-ms 10000 \
  -d tmp/binaries -w tmp/binary-in-progress \
 or --skip-processing --skip-consumer
```

## Sample Message on Kafka

```json
{
    "filename": "blah.png",
    "file_md5sum": "371d1274f057b8870efcb68ff3875a3f",
    "file_parts": 5,
    "partname": "blah.png_02",
    "part_base64_contents": "+1CPUiHRFUnM+M="
}
```

* **NOTE:** `part_base64_contents` will be much larger than the above sample

## Assumptions and Decisions

* Why not use kcat and jq? These are better utilities than string hacking with `bash`?
  * Agree, but I can't on my deployments.
  * Environments do not have access to kcat or jq and system security owners will not allow them to be installed.
  * For known filetypes, string marshalling and unmarshalling is easy enough.
* Why not use python, Java, Scala, etc.?
  * Bash scripts are not compilied and most of this script's dependencies come along with a standard Linux installation.
  * Python is not installed and pip does not work on all systems.

## Dependencies
* `kafka-console-consumer` and `kafka-console-producer`
* `md5sum`
* `split`
* `base64`
* `bash`
* Basic Linux commands
