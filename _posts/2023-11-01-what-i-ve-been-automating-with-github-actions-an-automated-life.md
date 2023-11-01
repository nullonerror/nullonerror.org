---
layout: post
title: >
  What I've been automating with GitHub Actions, an automated life
---

# Automate all the things!

Programmers, like no other beings on the planet, are completely obsessed with automating things, from the simplest to the most complex, and I'm no different.

I have automated several things using GitHub Actions, and today I will show some of the things I've done.

## README.md

In my GitHub README, I periodically fetch the RSS feed from my blog (the one you are currently reading) and populate it with the latest articles, like this:

Ah, you can use any source of RSS, like your YouTube channel!

```yaml
name: Latest blog post workflow
on:
  schedule:
    - cron: "0 */6 * * *"
  workflow_dispatch: # Run workflow manually

jobs:
  update-readme-with-blog:
    name: Update this repo's README with latest blog posts
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Pull NULL on Error posts
        uses: gautamkrishnar/blog-post-workflow@v1
        with:
          comment_tag_name: BLOG
          commit_message: Update with the latest blog posts
          committer_username: Rodrigo Delduca
          committer_email: 46259+skhaz@users.noreply.github.com
          max_post_count: 6
          feed_list: "https://nullonerror.org/feed"
```

## Resume

My resume is public. I have an action in the repository that compiles and uploads it to a Google Cloud bucket and sets the object as public, like this:

```yaml
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    container: texlive/texlive
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build
        run: |
          xelatex resume.tex
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GOOGLE_CREDENTIALS }}
      - name: Upload to Google Cloud Storage
        uses: google-github-actions/upload-cloud-storage@v1
        with:
          path: resume.pdf
          destination: gcs.skhaz.dev
          predefinedAcl: publicRead
```

You can check it out at https://gcs.skhaz.dev/resume.pdf

## GitHub Stars

I believe everyone enjoys starring repositories, but GitHub's interface doesn't help much when it comes to finding or organizing them.

To do this, I use [starred](https://github.com/maguowei/starred), which generates a README file categorizing by language. You can check it out at the following address: [https://github.com/skhaz/stars](https://github.com/skhaz/stars)

```yaml
name: Update Stars
on:
  workflow_dispatch:
  schedule:
    - cron: 0 0 * * *

jobs:
  stars:
    name: Update stars
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v3
        with:
          python-version: "3.10"
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install starred
      - name: Get repository name
        run: echo "REPOSITORY_NAME=${GITHUB_REPOSITORY#*/}" >> $GITHUB_ENV
      - name: Update repository category by language
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPOSITORY: ${{ env.REPOSITORY_NAME }}
          USERNAME: ${{ github.repository_owner }}
        run: starred --username ${USERNAME} --repository ${REPOSITORY} --sort --token ${GITHUB_TOKEN} --message 'awesome-stars category by language update by github actions cron, created by starred'
```

## Healthchecks

I imagine that, just like me, you also have several websites. In my case, all of them are simple and do not generate any income. However, I want to make sure that everything is in order, so I use https://healthchecks.io in conjunction with GitHub Actions. Healthchecks.io operates passively; it does not make requests to your site. On the contrary, you must make a request to it, and then it marks it as healthy. If there are no pings for a certain amount of time (configurable), it will notify you through various means that the site or application is not functioning as it should. Think of it as a Kubernetes probe.

```yaml
name: Health Check

on:
  workflow_dispatch:
  schedule:
    - cron: "0 * * * *"

jobs:
  health:
    runs-on: ubuntu-latest
    steps:
      - name: Check health
        run: |
          STATUSCODE=$(curl -s -o /dev/null --write-out "%{http_code}" "${SITE_URL}")

          if test $STATUSCODE -ne 200; then
            exit 1
          fi

          curl -fsS -m 10 --retry 5 -o /dev/null "https://hc-ping.com/${HEALTH_UUID}"
        env:
          HEALTH_UUID: ${{ secrets.HEALTH_UUID }}
          SITE_URL: ${{ secrets.SITE_URL }}
```

## Salary

This one is a bit more complex, as it goes beyond just an action. I have a repository called 'salary', where there's an action that runs every hour. What this action does is essentially run a Go code, and the result updates the README file. This way, I can simply access the URL and get an estimate of how much I'll receive.

In the program, I have two goroutines running in parallel. In one of them, I query the number of hours on Toggl, multiply it by my rate, and return it through a channel. The other does the same, but it uses an API to convert dollars to Brazilian reais, and in the end, the values are summed up.

`main.go`

```go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

type DateRange struct {
	StartDate string `json:"start_date"`
	EndDate   string `json:"end_date"`
}

type Summary struct {
	TrackedSecond int `json:"tracked_seconds"`
}

func toggl(result chan<- int, wg *sync.WaitGroup) {
	defer wg.Done()

	var (
		now      = time.Now()
		firstDay = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
		lastDay  = firstDay.AddDate(0, 1, -1)

		url       = fmt.Sprintf("https://api.track.toggl.com/reports/api/v3/workspace/%s/projects/summary", os.Getenv("TOGGL_WORKSPACE_ID"))
		dataRange = DateRange{
			StartDate: firstDay.Format("2006-01-02"),
			EndDate:   lastDay.Format("2006-01-02"),
		}
	)

	payload, err := json.Marshal(dataRange)
	if err != nil {
		log.Fatalln(err)
	}

	req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(payload))
	if err != nil {
		log.Fatalln(err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(os.Getenv("TOGGL_EMAIL"), os.Getenv("TOGGL_PASSWORD"))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatalln(err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalln(err)
	}

	var summaries []Summary
	if err = json.Unmarshal(body, &summaries); err != nil {
		log.Fatalln(err)
	}

	total := 0
	for _, summary := range summaries {
		total += summary.TrackedSecond
	}

	hourlyRate, err := strconv.Atoi(os.Getenv("TOGGL_HOURLY_RATE"))
	if err != nil {
		log.Fatalln(err)
	}

	result <- (total / 3600) * hourlyRate
}

type CurrencyData struct {
	Quotes struct {
		USDBRL float64 `json:"USDBRL"`
	} `json:"quotes"`
}

func husky(result chan<- int, wg *sync.WaitGroup) {
	defer wg.Done()

	var (
		currency = os.Getenv("HUSKY_CURRENCY")
		url      = fmt.Sprintf("https://api.apilayer.com/currency_data/live?base=USD&symbols=%s&currencies=%s", currency, currency)
	)

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		log.Fatalln(err)
	}

	req.Header.Set("apikey", os.Getenv("APILAYER_APIKEY"))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatalln(err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalln(err)
	}

	var data CurrencyData
	if err = json.Unmarshal(body, &data); err != nil {
		log.Fatalln(err)
	}

	monthlySalary, err := strconv.ParseFloat(os.Getenv("HUSKY_MONTHLY_SALARY"), 64)
	if err != nil {
		log.Fatalln(err)
	}

	gross := int(math.Floor(monthlySalary * data.Quotes.USDBRL))
	deduction := gross * 1 / 100
	result <- gross - deduction
}

func main() {
	var (
		ch    = make(chan int)
		wg    sync.WaitGroup
		funcs = []func(chan<- int, *sync.WaitGroup){toggl, husky}
	)

	wg.Add(len(funcs))

	for _, fun := range funcs {
		go fun(ch, &wg)
	}

	go func() {
		wg.Wait()
		close(ch)
	}()

	var sum int
	for result := range ch {
		sum += result
	}

	fmt.Print(sum)
}
```

So in the action, all you have to do is run and update the README periodically.

```yaml
name: Run

on:
  workflow_dispatch:
  schedule:
    - cron: "0 * * * *"

permissions:
  contents: write

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Go
        uses: actions/setup-go@v4
      - name: Update Markdown
        run: |
          salary=$(make run)

          cat > README.md <<EOF
          ### Salary

          EOF

          printf "%s\n" "$salary" >> README.md
        env:
          APILAYER_APIKEY: ${{ secrets.APILAYER_APIKEY }}
          HUSKY_MONTHLY_SALARY: ${{ secrets.HUSKY_MONTHLY_SALARY }}
          HUSKY_CURRENCY: ${{ secrets.HUSKY_CURRENCY }}
          TOGGL_WORKSPACE_ID: ${{ secrets.TOGGL_WORKSPACE_ID }}
          TOGGL_EMAIL: ${{ secrets.TOGGL_EMAIL }}
          TOGGL_PASSWORD: ${{ secrets.TOGGL_PASSWORD }}
          TOGGL_HOURLY_RATE: ${{ secrets.TOGGL_HOURLY_RATE }}
      - name: Commit report
        run: |
          git config --global user.name 'github-actions[bot]'
          git config --global user.email '41898282+github-actions[bot]@users.noreply.github.com'
          git add README.md
          git commit -am "Automated Salary Update" || true
          git push
```

## Blog

The next step is to automate the publishing of new blog posts using ChatGPT ;-).
