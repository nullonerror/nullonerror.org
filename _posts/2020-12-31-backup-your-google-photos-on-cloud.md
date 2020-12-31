---
layout: post
title: >
  Backup your Google Photos to Google Cloud Storage
---

### Why?
Google Cloud Storage is cheaper, and you pay only what you use than [Google One](https://one.google.com/). Also, you can erase any photo, and you still have a copy of that.

### Installation

Create a Compute Engine (a VM).

If you choosed Ubuntu, first of all, remove `snap`

``` bash
sudo apt autoremove --purge snapd
sudo rm -rf /var/cache/snapd/
rm -rf ~/snap
```

Install `gcsfuse` or follow [the official instructions](https://github.com/GoogleCloudPlatform/gcsfuse/blob/master/docs/installing.md).

``` bash
export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb http://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo apt-get update
sudo apt-get install gcsfuse
```

On Google Cloud console create a bucket of the type `Nearline`, in my case the name of the bucket is `tank1`, then back to your VM and create a dir with the same name of the bucket.

``` bash
mkdir name-of-your-bucket
```

Now install `gphotos-sync`.

``` bash
sudo apt install -y python3-pip
pip3 install gphotos-sync
```

I created a small Python script to deal with multiple Google's accounts. I'll explain later how it works.

``` python
cat <<EOF > /home/ubuntu/synchronize.py
#!/usr/bin/env python3

import os
import sys
import subprocess
from pathlib import Path

import requests


home = Path(os.path.expanduser("~")) / "tank1/photos"

args = [
  "--ntfs",
  "--retry-download",
  "--skip-albums",
  "--photos-path", ".",
  "--log-level", "DEBUG",
]

env = os.environ.copy()
env["LC_ALL"] = "en_US.UTF-8"

for p in home.glob("*/*"):
  subprocess.run(["/home/ubuntu/.local/bin/gphotos-sync", *args, str(p.relative_to(home))], check=True, cwd=home, env=env, stdout=sys.stdout, stderr=subprocess.STDOUT)

# I use healthchecks.io to alert me if the script has stopped work
url = "https://hc-ping.com/uuid4"
response = requests.get(url, timeout=60)
response.raise_for_status()
EOF
```

Give *execute* permission.

```
chmod u+x synchronize.py
```

Now let's create some __systemd__ scripts.

```
sudo su
```

Let's create a service to gcsfuse, responsible to mount the bucket locally using the FUSE.

``` bash
cat <<EOF > /etc/systemd/system/gcsfuse.service 
# Script stolen from https://gist.github.com/craigafinch/292f98618f8eadc33e9633e6e3b54c05
[Unit]
Description=Google Cloud Storage FUSE mounter
After=local-fs.target network-online.target google.service sys-fs-fuse-connections.mount
Before=shutdown.target

[Service]
Type=forking
User=ubuntu
ExecStart=/bin/gcsfuse tank1 /home/ubuntu/tank1
ExecStop=/bin/fusermount -u /home/ubuntu/tank1
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start the service:

``` bash
systemctl enable gcsfuse.service
systemctl start gcsfuse.service
```

``` bash
cat <<EOF > /etc/systemd/system/gphotos-sync.service 
[Unit]
Description=Run gphotos-sync for each account

[Service]
User=ubuntu
ExecStart=/home/ubuntu/synchronize.py
EOF
```

And enable the service.

``` bash
systemctl enable gphotos-sync.service
```

Now let's create a *timer* to run 1 minute after the boot the `gphotos-sync.service` with `gcsfuse.service` as dependecy.

``` bash
cat <<EOF >/etc/systemd/system/gphotos-sync.timer 
[Unit]
Description=Run gphotos sync service weekly
Requires=gcsfuse.service

[Timer]
OnBootSec=1min
Unit=gphotos-sync.service

[Install]
WantedBy=timers.target
EOF
```

``` bash
systemctl enable gphotos-sync.timer
systemctl start gphotos-sync.timer
```

`exit` (back to ubuntu user)

Now follow [https://docs.google.com/document/d/1ck1679H8ifmZ_4eVbDeD_-jezIcZ-j6MlaNaeQiz7y0/edit](this instructions) to get a `client_secret.json` to use with `gphotos-sync`.

``` bash
mkdir -p /home/ubuntu/.config/gphotos-sync/
# Copy the contents of the json to the file bellow
vim /home/ubuntu/.config/gphotos-sync/client_secret.json 
```

### Schedule startup and shutdown of the VM

The content bellow is based and simplified version of [Scheduling compute instances with Cloud Scheduler by Google](https://cloud.google.com/scheduler/docs/start-and-stop-compute-engine-instances-on-a-schedule#gcloud_3)

gcloud pubsub topics create start-instance-event

gcloud functions deploy startInstancePubSub \
    --trigger-topic start-instance-event \
    --runtime nodejs12 \
    --allow-unauthenticated

gcloud pubsub topics create stop-instance-event

gcloud functions deploy stopInstancePubSub \
    --trigger-topic stop-instance-event \
    --runtime nodejs12 \
    --allow-unauthenticated

gcloud beta scheduler jobs create pubsub startup-weekly-instances \
    --schedule '0 0 * * SUN' \
    --topic start-instance-event \
    --message-body '{"zone":"us-central1-a", "label":"runtime=weekly"}' \
    --time-zone 'America/Sao_Paulo'

gcloud beta scheduler jobs create pubsub shutdown-dev-instances \
    --schedule '0 0 * * MON' \
    --topic stop-instance-event \
    --message-body '{"zone":"us-central1-a", "label":"runtime=weekly"}' \
    --time-zone 'America/Sao_Paulo'


`index.js`

``` javascript
const Compute = require('@google-cloud/compute');
const compute = new Compute();

exports.startInstancePubSub = async (event, context, callback) => {
  try {
    const payload = JSON.parse(Buffer.from(event.data, 'base64').toString());
    const options = {filter: `labels.${payload.label}`};
    const [vms] = await compute.getVMs(options);
    await Promise.all(
      vms.map(async instance => {
        if (payload.zone === instance.zone.id) {
          const [operation] = await compute
            .zone(payload.zone)
            .vm(instance.name)
            .start();

          return operation.promise();
        }
      })
    );

    const message = 'Successfully started instance(s)';
    console.log(message);
    callback(null, message);
  } catch (err) {
    console.log(err);
    callback(err);
  }
};

exports.stopInstancePubSub = async (event, context, callback) => {
  try {
    const payload = JSON.parse(Buffer.from(event.data, 'base64').toString());
    const options = {filter: `labels.${payload.label}`};
    const [vms] = await compute.getVMs(options);
    await Promise.all(
      vms.map(async instance => {
        if (payload.zone === instance.zone.id) {
          const [operation] = await compute
            .zone(payload.zone)
            .vm(instance.name)
            .stop();

          return operation.promise();
        } else {
          return Promise.resolve();
        }
      })
    );

    const message = 'Successfully stopped instance(s)';
    console.log(message);
    callback(null, message);
  } catch (err) {
    console.log(err);
    callback(err);
  }
};
```

`package.json`

``` json
{
  "main": "index.js",
  "private": true,
  "dependencies": {
    "@google-cloud/compute": "^2.4.1"
  }
}
```