---
layout: post
title: >
  Auto generating SEO-friendly URLs with Scrapy pipelines
---

I was using Scrapy to crawl some websites and mirror their content into a new one and at the same time, generate beautiful and unique URLs based on the title, but the title can appear repeated! So I added part of the original URL in [base36](https://en.wikipedia.org/wiki/Base36) as uniqueness guarantees.

In the *URL* I wanted the title without special symbols, only ASCII and at the end a unique and short inditifier, and part of the result of the [SHA-256](https://en.wikipedia.org/wiki/SHA-2) of the URL in *base36*.

``` python
class PreparePipeline():
  def process_item(self, item, spider):
    url = item["url"]

    title = item.get("title")
    if title is None:
      raise DropItem(f"No title were found on item: {item}.")

    N = 4
    sha256 = hashlib.sha256(url.encode()).digest()
    sliced = int.from_bytes(
        memoryview(sha256)[:N].tobytes(), byteorder=sys.byteorder)
    uid = base36.dumps(sliced)

    strip = str.strip
    lower = str.lower
    split = str.split
    deunicode = lambda n: normalize("NFD", n).encode("ascii", "ignore").decode("utf-8")
    trashout = lambda n: re.sub(r"[.,-@/\\|*]", " ", n)
    functions = [strip, deunicode, trashout, lower, split]
    fragments = [
        *functools.reduce(
        lambda x, f: f(x), functions, title),
        uid,
    ]

    item["uid"] = "-".join(fragments)

    return item
```

For example, with the *URL* `https://en.wikipedia.org/wiki/Déjà_vu` and *title* `Déjà vu - Wikipedia` will result in: `deja-vu-wikipedia-1q9i86k`. Which is perfect for my use case.