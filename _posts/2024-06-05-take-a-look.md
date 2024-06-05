# TakeALook Pro

### Intro

Since the first URL shorteners emerged, that's always drawn me in for some reason, perhaps because I figured out on my own that they encoded the primary key in base36 (maybe).

So around ~2010, I decided to make my own. It was called "encurta.ae" (make it short there in Portuguese), and it was based on AppEngine. Even back then, I was quite fond of serverless and such.

It worked great locally, but when I deployed it, the datastore IDs were too large, causing the URLs to be too long.

Fast-forward to nowadays, I've decided to bring this project to life again. This time with a twist: when shortening the URL, the shortener would take a screenshot of the website and embed Open Graph tags in the redirect URL. This way, when shared on a social network, the link would display a title, description, and thumbnail that accurately represent what the user is about to open.

### Stack

Typically, I use serverless for my personal projects because they scale to zero, thus eliminating costs when not in use. However, after working with serverless for many years, I've been wanting to experiment with a more grounded and down-to-earth approach to development and deployment.

- I opted to use [Go](https://go.dev/), with several [goroutines](https://en.wikipedia.org/wiki/Coroutine) performing tasks in parallel, and a purely written work queue mechanism.
- [Playwright](https://playwright.dev/) & Chromium for automation and screenshot.
- [SQLite](https://sqlite.org/) for the database (it's simple)
- [Backblaze](https://www.backblaze.com/) for storage
- [BunnyCDN](https://bunny.net/) for cotent delivery

Deployment is done using Docker Compose, via SSH using the DOCKER_HOST environment variable pointing directly to a Raspberry Pi that I had bought and never used before. Now it saves me $5 per month, and I can keep a limited number of projects running on it.

And then you might ask: How do you expose it to the internet? I use [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/); the setup is simple and creates a direct connection between the Raspberry Pi and the nearest PoP.

This type of hosting is extremely advantageous because the server's IP and/or ports are never revealed; it stays behind my firewall. Everything goes through Cloudflare.

Example of the "worker queue"

```go
package functions

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	google "cloud.google.com/go/vision/apiv1"
	visionpb "cloud.google.com/go/vision/v2/apiv1/visionpb"
	"github.com/martinlindhe/base36"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/playwright-community/playwright-go"
	"go.uber.org/zap"
	"google.golang.org/api/option"
	log "skhaz.dev/urlshortnen/logging"
)

var (
	accessKeyID     = os.Getenv("BACKBLAZE_ACCESS_ID")
	secretAccessKey = os.Getenv("BACKBLAZE_APPLICATION_KEY")
	bucket          = os.Getenv("BACKBLAZE_BUCKET")
	endpoint        = os.Getenv("BACKBLAZE_ENDPOINT")
	useSSL          = true
	extension       = "webp"
	mimetype        = "image/webp"
	quality         = "50"
)

type WorkerFunctions struct {
	db      *sql.DB
	vision  *google.ImageAnnotatorClient
	mc      *minio.Client
	browser playwright.BrowserContext
}

func Worker(db *sql.DB) {
	defer func() {
		if r := recover(); r != nil {
			log.Error("worker panic", zap.Any("error", r))
			time.Sleep(time.Second * 10)
			go Worker(db)
		}
	}()

	ctx := context.Background()

	vision, err := google.NewImageAnnotatorClient(ctx, option.WithCredentialsJSON([]byte(os.Getenv("GOOGLE_CREDENTIALS"))))
	if err != nil {
		log.Error("failed to create vision client", zap.Error(err))
		return
	}
	defer vision.Close()

	mc, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		log.Error("failed to create minio client", zap.Error(err))
		return
	}

	pw, err := playwright.Run()
	if err != nil {
		log.Error("failed to launch playwright", zap.Error(err))
		return
	}
	//nolint:golint,errcheck
	defer pw.Stop()

	userDataDir, err := os.MkdirTemp("", "chromium")
	if err != nil {
		log.Error("failed to create temporary directory", zap.Error(err))
		return
	}
	defer os.RemoveAll(userDataDir)

	browser, err := pw.Chromium.LaunchPersistentContext(userDataDir, playwright.BrowserTypeLaunchPersistentContextOptions{
		Args: []string{
			"--headless=new",
			"--no-zygote",
			"--no-sandbox",
			"--disable-gpu",
			"--hide-scrollbars",
			"--disable-setuid-sandbox",
			"--disable-dev-shm-usage",
			"--disable-extensions-except=/opt/extensions/ublock,/opt/extensions/isdncac",
			"--load-extension=/opt/extensions/ublock,/opt/extensions/isdncac",
		},
		DeviceScaleFactor: playwright.Float(4.0),
		Headless:          playwright.Bool(false),
		Viewport: &playwright.Size{
			Width:  1200,
			Height: 630,
		},
		UserAgent: playwright.String("Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/125.0.0.0 Safari/537.36"),
	})
	if err != nil {
		log.Error("failed to launch chromium browser", zap.Error(err))
		return
	}
	defer browser.Close()

	wf := WorkerFunctions{
		db:      db,
		vision:  vision,
		mc:      mc,
		browser: browser,
	}

	for {
		start := time.Now()

		func() {
			var (
				wg   sync.WaitGroup
				rows *sql.Rows
				err  error
			)

			rows, err = db.Query("SELECT id, url FROM data WHERE ready = 0 ORDER BY created_at LIMIT 6")
			if err != nil {
				log.Error("error executing query", zap.Error(err))
				return
			}
			defer rows.Close()

			for rows.Next() {
				var id int64
				var url string
				if err = rows.Scan(&id, &url); err != nil {
					log.Error("error scanning row", zap.Error(err))
					return
				}

				wg.Add(1)
				go wf.run(&wg, url, id)
			}

			if err := rows.Err(); err != nil {
				log.Error("error during rows iteration", zap.Error(err))
				return
			}

			wg.Wait()
		}()

		elapsed := time.Since(start)
		if remaining := 5*time.Second - elapsed; remaining > 0 {
			time.Sleep(remaining)
		}
	}
}

func (wf *WorkerFunctions) run(wg *sync.WaitGroup, url string, id int64) {
	defer wg.Done()

	var message string

	if id < 0 {
		message = "invalid id: id must be non-negative"
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	var (
		ctx   = context.Background()
		short = base36.Encode(uint64(id))
	)

	dir, err := os.MkdirTemp("", "screenshot")
	if err != nil {
		message = fmt.Sprintf("failed to create temporary directory: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}
	defer os.RemoveAll(dir)

	var (
		fileName = fmt.Sprintf("%s.%s", short, extension)
		filePath = filepath.Join(dir, fileName)
	)

	page, err := wf.browser.NewPage()
	if err != nil {
		message = fmt.Sprintf("failed to create new page: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}
	defer page.Close()

	if _, err = page.Goto(url, playwright.PageGotoOptions{
		WaitUntil: playwright.WaitUntilStateDomcontentloaded,
	}); err != nil {
		message = fmt.Sprintf("failed to navigate to url: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	time.Sleep(time.Second * 5)

	title, err := page.Title()
	if err != nil {
		message = fmt.Sprintf("could not get title: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	description, err := page.Locator(`meta[name="description"]`).GetAttribute("content")
	if err != nil {
		log.Info("could not get meta description", zap.Error(err))
		description = ""
	}

	if _, err = page.Screenshot(playwright.PageScreenshotOptions{
		Path: playwright.String(filePath),
	}); err != nil {
		message = fmt.Sprintf("failed to create screenshot: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	fp, err := os.Open(filePath)
	if err != nil {
		message = fmt.Sprintf("failed to open screenshot: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}
	defer fp.Close()

	image, err := google.NewImageFromReader(fp)
	if err != nil {
		message = fmt.Sprintf("failed to load screenshot: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	annotations, err := wf.vision.DetectSafeSearch(ctx, image, nil)
	if err != nil {
		message = fmt.Sprintf("failed to detect labels: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	if annotations.Adult >= visionpb.Likelihood_POSSIBLE || annotations.Violence >= visionpb.Likelihood_POSSIBLE || annotations.Racy >= visionpb.Likelihood_POSSIBLE {
		message = fmt.Sprintf("site is not safe %v", annotations)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	cmd := exec.Command("convert", filePath, "-resize", "50%", "-filter", "Lanczos", "-quality", quality, filePath)
	if err := cmd.Run(); err != nil {
		message = fmt.Sprintf("error during image conversion: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	_, err = wf.mc.FPutObject(ctx, bucket, fileName, filePath, minio.PutObjectOptions{ContentType: mimetype})
	if err != nil {
		message = fmt.Sprintf("failed to upload file to minio: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	if _, err = wf.db.Exec("UPDATE data SET ready = 1, title = ?, description = ? WHERE url = ?", title, description, url); err != nil {
		message = fmt.Sprintf("failed to update database record: %v", err)
		log.Error(message)
		setError(wf.db, url, message)
		return
	}

	go warmup(fmt.Sprintf("%s/%s", os.Getenv("DOMAIN"), short))
}

func setError(db *sql.DB, url, message string) {
	if _, err := db.Exec("UPDATE data SET ready = 1, error = ? WHERE url = ?", message, url); err != nil {
		log.Error("failed to update database error record", zap.Error(err))
	}
}
```

It's noticeable that it took a bit more effort than if I had used a task queue. However, it turned out to be quite robust and easy to debug, and for that reason alone, it was worth it.

### Conclusion

In sharing the shortened link ([https://takealook.pro/4MP](https://takealook.pro/4MP)) for my company [Ultratech Software](https://ultratech.software/) on social networks, you can have a really nice preview, as seen below.

![takealook.pro](/public/2024-06-05-take-a-look/takealook.pro.avif){: .center }

[Take A Look](https://takealook.pro/)
