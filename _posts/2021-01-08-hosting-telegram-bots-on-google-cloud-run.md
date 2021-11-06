---
layout: post
title: >
  Hosting Telegram bots on Cloud Run for free
---

I write a lot of [Telegram bots](https://core.telegram.org/bots) using the library [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot). Writing Telegram bots is fun, but you will also need someplace to host them.

I personally like the new [Google Cloud Run](https://cloud.google.com/run); or run, for short, is perfect because it has a *"gorgeous"* [free quota](https://cloud.google.com/run/pricing) that should be mostly sufficient to host your bots, also, and is it super simple to deploy and get running.

To create Telegram bots, first, you need to talk to [BotFather](https://t.me/botfather) and get a *TOKEN*.

Secondly, you need some coding. As I mentioned before, you can use *python-telegram-bot* to do your bots. Here is the [documentation](https://python-telegram-bot.org/).

### Code

Here is the base code that you will need to run on Cloud Run.

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

dispatcher = Dispatcher(bot=bot, update_queue=None)
dispatcher.add_handler(MessageHandler(Filters.text & ~Filters.command, echo))

@app.post("/")
def index() -> Response:
    dispatcher.process_update(
        Update.de_json(request.get_json(force=True), bot))

    return "", http.HTTPStatus.NO_CONTENT
```

`requirements.txt`

``` text
flask==2.0.2
gunicorn==20.1.0
python-telegram-bot==13.7
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

Finally, you need to deploy. You can do it in a single step, but first, let's run the command below to set the default region (optionally).

``` bash
gcloud config set run/region us-central1
```

Export some variables

```bash
export PROJECT_ID=your-google-s-project-id
export TOKEN=your-telegram-bot-token
```

Then deploy to Cloud Run

``` bash
gcloud beta run deploy bot \
    --source . \
    --set-env-vars TOKEN=${TOKEN} \
    --platform managed \
    --allow-unauthenticated \
    --project ${PROJECT_ID}
```

After this, you will receive a public *URL* of your run, and you will need to set the Telegram bot `webHook` using *cURL* (only need to be done once)

``` bash
curl "https://api.telegram.org/bot${TOKEN}/setWebhook?url=$(gcloud run services describe bot --format 'value(status.url)' --project ${PROJECT_ID})"
```

This should be enough.

If you want to see the source-code of one of mine [github.com/skhaz/telegram-delduca-bot](https://github.com/skhaz/telegram-delduca-bot).
