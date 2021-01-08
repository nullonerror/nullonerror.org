---
layout: post
title: >
  Hosting Telegram bots on Cloud Run for free
---

I write a lot of [Telegram bots](https://core.telegram.org/bots) using the library [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot). Writing Telegram bots is funny, but you will also need some place to host them, I personally like the new [Google Cloud Run](https://cloud.google.com/run); *run*, the short-form, is perfect because has a *"gorgeous"* [free quota](https://cloud.google.com/run/pricing) and is it super simply to deploy and get running.

Here is the source:

`main.py`

``` python
import os
import http

from flask import Flask, request
from werkzeug.wrappers import Response

from telegram import Bot, Update
from telegram.ext import Dispatcher, Filters, MessageHandler, CallbackContext

app = Flask(__name__)


def echo(update: Update, context: CallbackContext) -> None:
    update.message.reply_text(update.message.text)

bot = Bot(token=os.environ["TOKEN"])

dispatcher = Dispatcher(bot=bot, update_queue=None, workers=0)
dispatcher.add_handler(MessageHandler(Filters.text & ~Filters.command, echo))

@app.route("/", methods=["POST"])
def index() -> Response:
    dispatcher.process_update(
        Update.de_json(request.get_json(force=True), bot))

    return "", http.HTTPStatus.NO_CONTENT
```

`requirements.txt`

``` text
flask==1.1.2
gunicorn==20.0.4
python-telegram-bot==13.1
```

`Dockerfile`

``` dockerfile
FROM python:3.8-slim
ENV PYTHONUNBUFFERED True
WORKDIR /app
COPY *.txt .
RUN pip install --no-cache-dir --upgrade pip -r requirements.txt
COPY . ./

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
```


### Deployment

First run the command bellow to set the default region (optionally).

``` bash
gcloud config set run/region us-central1
```

Then deploy to Cloud Run:

``` bash
gcloud beta run deploy your-bot-name \
    --source . \
    --set-env-vars TOKEN=your-telegram-bot-token \
    --platform managed \
    --allow-unauthenticated \
    --project your-project-name
```

After this set the Telegram bot `webHook` using *cURL*

``` bash
curl "https://api.telegram.org/botYOUR-BOT:TOKEN/setWebhook?url=https://your-bot-name-uuid-uc.a.run.app"
```

You should replace the `YOUR-BOT:TOKEN` by the bot's token and the public URL of your Cloud Run.

This should be enough.