---
layout: post
title: >
  Accessing Google Firestore on Vercel
---

Or on any other cloud service, or language.

> TL;DR: Use GOOGLE_APPLICATION_CREDENTIALS with a valid JSON credential to use any Google APIs anywhere.

[Firebase Hosting](https://firebase.google.com/docs/hosting) is great, but the new [Vercel](https://vercel.com/) is awesome for NextJS apps. On Vercel your code runs on [Lambda@Edge](https://aws.amazon.com/lambda/edge/) and it is cached on [CloudFront](https://aws.amazon.com/cloudfront/); in the same way, Firebase uses [Fastly](https://www.fastly.com/), another great CDN.

You can not take full advantage of running a NextJS app on Firebase Hosting, only on Vercel, or by deploying manually.

I like to use [Firestore](https://firebase.google.com/docs/firestore) on some projects, and unfortunately it is "restricted" to the internal network of Google Cloud, although there is a trick; you can download the service account and export an environment variable named `GOOGLE_APPLICATION_CREDENTIALS` with the path of the downloaded credential.


First, download the JSON file following [this steps](https://firebase.google.com/docs/admin/setup#initialize-sdk).

Then, convert the credentials JSON file to _base64_:

``` shell
cat ~/Downloads/project-name-adminsdk-owd8n-43fca28a2a.json | base64
```

Now copy the result and create an [environment variable on Vercel](https://vercel.com/docs/environment-variables) named `GOOGLE_CREDENTIALS` and paste the contents.

On your NextJS project, create a `pages/api/function.js` and add the following code:

``` javascript
import os from "os"
import { promises as fsp } from "fs"
import path from "path"

import { Firestore, FieldValue } from "@google-cloud/firestore"

let _firestore = null

const lazyFirestore = () => {
  if (!_firestore) {
    const baseDir = await fsp.mkdtemp((await fsp.realpath(os.tmpdir())) + path.sep)
    const fileName = path.join(baseDir, "credentials.json")
    const buffer = Buffer.from(process.env.GOOGLE_CREDENTIALS, "base64")
    await fsp.writeFile(fileName, buffer)

    process.env["GOOGLE_APPLICATION_CREDENTIALS"] = fileName

    _firestore = new Firestore()
  }

  return _firestore
}

export default async (req, res) => {
  const firestore = await lazyFirestore()

  const increment = FieldValue.increment(1)
  const documentRef = firestore.collection("v1").doc("default")

  await documentRef.update({ counter: increment })

  res.status(200).json({})
}
```

Done! Now it is possible to use Firestore on Vercel or anywhere.

[Project of example](https://github.com/skhaz/firestore-on-vercel).