---
layout: post
title: >
  Hosting Telegram bots on Cloud Run for free
---


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
pyyaml==5.3.1
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