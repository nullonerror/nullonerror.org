---
layout: post
title: >
  Working with compressed binary data on AWS IoT Core
---

### Objective

Today we will see how to send compressed CBOR with ZSTD from an ESP32 microcontroller through an MQTT topic, passing through AWS IoT Core, and finally being decoded in a TypeScript-written Lambda function.

### Intro

Firstly, what is a microcontroller (MCU)? In this article, we will be using the ESP32 microcontroller from Espressif. It is a highly affordable and inexpensive microcontroller that comes with built-in WiFi and Bluetooth, making it ideal for IoT projects as we will see today. It also boasts a generous amount of flash memory and RAM, as well as a powerful dual-core 32-bit CPU.

Another tool we will be using is PlatformIO, a development framework that functions as a series of plugins and command-line tools for VSCode. With PlatformIO, we have everything we need, from project setup, board selection, serial port speed, compilation flags (yes, we'll be compiling code in C and C++), and more. Installing it is quite simple; just visit https://platformio.org/ and follow the instructions.

Lastly, to streamline our project and infrastructure, we will be using the Serverless Framework, a framework designed for developing serverless solutions. In our case, we will be using a Lambda function to receive messages sent to the topic. The Serverless Framework is a perfect fit for this scenario and works seamlessly with AWS Amazon.

### Compressed Binary Data

We could certainly use JSON. In fact, with JSON, it is possible to perform queries using the WHERE clause (Yes, IoT Core supports SQL, and we will delve into that later). However, our objective here is to save as many bytes as possible. Imagine that our application will send and receive data via a costly and unreliable telephone connection. Therefore, we need to compress the data as much as possible.

Firstly, let's construct the raw payload in CBOR. CBOR is an interchangeable binary format specified in an RFC and supported by various programming languages (it is derived from MsgPack, in case you've heard of it before).

Since this part will be done on the microcontroller side, we will be using the C++ language with the `ssilverman/libCBOR` library. To do this, we open the `platformio.ini` file and add the dependency under `lib_deps`.

```cpp
#include <CBOR.h>
#include <CBOR_parsing.h>
#include <CBOR_streams.h>

namespace cbor = ::qindesign::cbor;
```

Since we are developing for a microcontroller, memory allocation is a critical concern as it can lead to fragmentation and other issues. Therefore, we will define a buffer of 256 bytes for reading and writing CBOR messages, which is more than sufficient for our current application.

```cpp
constexpr size_t kBytesSize = 256;
uint8_t bytes[kBytesSize]{0};
cbor::BytesStream bs{bytes, sizeof(bytes)};
cbor::BytesPrint bp{bytes, sizeof(bytes)};
```

Next, let's prepare to use ZSTD. The steps are the same as with CBOR.

```cpp
#include <zstd.h>

constexpr size_t kZBytesSize = 256;
uint8_t zbytes[kZBytesSize]{0};
```

Finally, and not least importantly, let's prepare to send messages to a topic on IoT Core. The setup is a bit complex and requires attention. Firstly, we need to add the `knolleary/PubSubClient` library.

We will need three things from AWS IoT Core: the Certificate Authority (CA) certificate, the Thing certificate, and the private key certificate of the Thing. We will see how to create rules in IoT Core to allow things to subscribe and publish only to specific topics for security reasons. One more thing, in our project, we will hardcode these values in the flash memory of the ESP32 using the _PROGMEM_ directive.

```cpp
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

static const char AWS_IOT_ENDPOINT[] = "....amazonaws.com";
static const uint16_t AWS_IOT_PORT = 8883;
static const char THINGNAME[] = "My ESP32";

static const char AWS_CERT_CA[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
... AWS Amazon Certificate Authority (CA)
-----END CERTIFICATE-----
)EOF";

static const char AWS_CERT_CRT[] PROGMEM = R"KEY(
-----BEGIN CERTIFICATE-----
... Thing's certificate
-----END CERTIFICATE-----
)KEY";

static const char AWS_CERT_PRIVATE[] PROGMEM = R"KEY(
-----BEGIN RSA PRIVATE KEY-----
... Thing's private certificate
-----END RSA PRIVATE KEY-----
)KEY";
```

We need an instance of PubSub to publish and subscribe to topics, as well as a WiFi client to configure the aforementioned keys.

```cpp
WiFiClientSecure net;
PubSubClient pubsub(AWS_IOT_ENDPOINT, AWS_IOT_PORT, net);
```

Now let's proceed with a typical Arduino program structure, with the setup and loop functions. In the setup function, we will connect to the WiFi network, and then we will configure the keys in the WiFiClientSecure object so that the PubSubClient can use them to connect to IoT Core. Without these keys, the connection will be rejected by the AWS Amazon servers.

```cpp
void setup()
{
	// For debugging.
  Serial.begin(115200);

	// Connect to WiFi.
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

	// Wait for the connection.
  while (WiFi.status() != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }

	// Show WiFi information.
  Serial.println();
  Serial.print("Connected to ");
  Serial.println(WIFI_SSID);
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());

  // Setup the certificates.
  net.setCACert(AWS_CERT_CA);
  net.setCertificate(AWS_CERT_CRT);
  net.setPrivateKey(AWS_CERT_PRIVATE);

  // Connect to IoT Core.
  pubsub.connect(THINGNAME);
}
```

If everything goes well, the `connect` method of PubSubClient will return _true_. We won't perform that check; instead, we'll attempt to publish directly and monitor the results on the IoT Core dashboard.

Now comes the interesting part. We will assemble our payload in CBOR format, compress it using ZSTD, and publish it to a topic.

```cpp
void on_sensor(const uint64_t *sensor_data, size_t sensor_data_size) {
  // Create a new instance of the CBOR writer.
  cbor::Writer cbor{bp};

	// Reset BytesPrint instance.
  bp.reset();

	// Indicates that what follows is an array of a certain size.
  cbor.beginArray(sensor_data_size);
  for (size_t i = 0; i < sensor_data_size; i++)
  {
	  // For each item in the array, write it to CBOR.
    cbor.writeUnsignedInt(sensor_data[i]);
  }

	// Get the final CBOR size.
  const size_t lenght = cbor.getWriteSize();

	// Compress the CBOR buffer using ZSTD.
  size_t compressedSize = ZSTD_compress(zbytes, kZBytesSize, bytes, lenght, ZSTD_CLEVEL_DEFAULT);

	// Publish the binary compressed data onto the topic.
	char topic[128];
	sprintf(topic, "sensors/%s/v1", THINGNAME);
  pubsub.publish(topic, zbytes, compressedSize, false);
}
```

### On the cloud side

As I mentioned before, we will be using the Serverless Framework, which follows the Infrastructure as Code (IaC) approach. So what we’ll do is create the rules for the Things, create a lambda function, and define the trigger for that lambda as IoT Core. Since the data is in binary format, we will encode it in Base64 in the IoT Core SQL.

```yaml
service: myiot

configValidationMode: error

frameworkVersion: "3"

provider:
  name: aws
  runtime: nodejs18.x
  architecture: arm64
  stage: development

resources:
  Resources:
    IoTPolicy:
      Type: AWS::IoT::Policy
      Properties:
        PolicyName: IoTPolicy
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action:
                - iot:Connect
              Resource: arn:aws:iot:*:*:client/\${iot:Connection.Thing.ThingName}
            - Effect: Allow
              Action:
                - iot:Publish
                - iot:Receive
              Resource: arn:aws:iot:*:*:topic/*/\${iot:Connection.Thing.ThingName}/*
            - Effect: Allow
              Action:
                - iot:Subscribe
              Resource: arn:aws:iot:*:*:topicfilter/*/\${iot:Connection.Thing.ThingName}/*

functions:
  tracker:
    handler: app/mylambda.handler
    events:
      - iot:
          sql: "SELECT timestamp() AS timestamp, topic() AS topic, encode(*, 'base64') AS data FROM 'sensors/+/v1'"
          sqlVersion: "2016-03-23"

plugins:
  - serverless-plugin-typescript
```

The YAML file for serverless may seem a bit intimidating at first, but it's simple. It essentially does two things. Firstly, it creates an IoTPolicy for the things. A Thing can only publish or subscribe to its own topic with IoTPolicies, allowing for a granular level of security.

Also, it's worth noting that we are using ARM64 architecture. Lambdas running on the ARM architecture are not only more cost-effective but also more efficient compared to x86_64.

The second part is the definition of the lambda function and its trigger. It uses a query in IoT Core, which is the key to working with binary data in IoT Core. You need to encode the data in **base64** before sending it to the lambda function; otherwise, it won't work. This lambda function is "listening" to the sensors topic from any Thing, hence the plus symbol in the topic. By default, I prefer to version APIs, and a topic shouldn't be an exception. Therefore, this is version 1 of my project.

Now let's take a look at the lambda function itself. For this project, I chose to use TypeScript, but AWS Lambda and the Serverless Framework support various programming languages.

The code is quite straightforward. It receives the binary payload in the `data` parameter (as defined in the SQL statement above). First, it decodes the payload from base64 to binary. Then, it decompresses it using ZSTD and, finally, utilizes the CBOR library to parse it into a JavaScript object, ready to be used.

```typescript
import { decompressSync } from "@skhaz/zstd";
import { decodeFirstSync } from "cbor";

export async function handler(event: { timestamp: number; topic: string; data: string }) {
  // Extract from event some variables.
  const { timestamp, topic, data } = event;

  // Decode from base64 to binary.
  const buffer = Buffer.from(data, "base64");
  // Decompress using ZSTD algorithm.
  const cbor = decompressSync(buffer);
  // Parse the binary CBOR to JavaScript object.
  const payload = decodeFirstSync(cbor);

  // Print the sensor array data.
  console.log(payload);
}
```

### Conclusion

In conclusion, it is possible to save a few bytes or even more with these techniques while utilizing cloud solutions like IoT Core in your projects. It allows for efficient data handling and enables the integration of cloud services into your applications.

The compression ratio can vary dramatically, depending solely on the input. In my experiments with numerical data, it ranged from around 30% to 40%. However, the tradeoff is an increase of approximately 180KB in the final firmware size, which can be impractical in some cases.
