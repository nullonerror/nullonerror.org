---
layout: post
title: >
  Taking advantage of Python's concurrent futures to full saturate your bandwidth
---

> I am starting a new series of small snippets of code which I think that maybe useful or inspiring for others.

Let's suppose you have a pandas' `dataframe` with a column named *URL* which one do you want to download.

The code below takes the advantage of the multi-core processing using the [ThreadPoolExecutor](https://docs.python.org/3/library/concurrent.futures.html#concurrent.futures.ThreadPoolExecutor) with [requests](https://requests.readthedocs.io/en/master/).

``` python
import multiprocessing
import concurrent.futures

from requests import Session
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

session = Session()

retry = Retry(connect=8, backoff_factor=0.5)
adapter = HTTPAdapter(max_retries=retry)
session.mount("http://", adapter)
session.mount("https://", adapter)


def download(url):
    filename = "/".join(["subdir", url.split("/")[-1]])

    with session.get(url, stream=True) as r:
        if not r.ok:
            return

        with open(filename, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)


def run(df, processes=multiprocessing.cpu_count() * 2):
    with concurrent.futures.ThreadPoolExecutor(processes) as pool:
        list(pool.map(download, df["url"]))


if __name__ == '__main__':
    df = pd.read_csv("download.csv")
    run(df)
```
