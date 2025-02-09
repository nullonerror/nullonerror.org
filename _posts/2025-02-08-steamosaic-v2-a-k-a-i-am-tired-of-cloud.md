---
layout: post
title: >
  Steamosaic V2, A.K.A. I am tired of cloud
---

I have a project called [steamosaic.com](https://steamosaic.com) that was quite popular among Steam players. I estimate that over 50,000 users created their mosaics; unfortunately, I only added a counter after the initial hype, and today it stands at 15,991.

In the initial version, I jumped completely on the cloud and serverless bandwagon. It worked more or less like this:

1. When a user entered their username, I saved it as a document in Firestore (Firebase’s document-based database).
2. Whenever any document was saved, a Cloud Function was triggered, which then published a message to a PubSub topic (Google Cloud’s message queue).
3. On the other side, there was a Cloud Run (a serverless container-based runtime) that, whenever it received a message, had a new instance triggered by Google’s infrastructure.
4. Generating the mosaics took a long time because even the cheaper instances were still too expensive.
5. Once finished, Cloud Run saved the mosaic in a bucket and marked it as “ready.”
6. On the client side, a small JavaScript waited for the “ready” signal before finally displaying the mosaic.

I didn’t use Infrastructure as Code since it was just a pet project, so any maintenance or setup took days.

For about two years, I ran it this way, incurring some costs—around $20 to $10 during peak times.

So recently, I adopted a much simpler and much cheaper way to keep my projects online and hassle-free.

I rented a VM from Hetzner; it costs me 12 euros and comes with 16 GB of RAM and 8 vCPUs.

Yes, I know—you might say, “Aren’t you putting all your eggs in one basket?” And the answer is yes; since these are non-critical, personal projects, I don’t see any problem.

You might be wondering how I manage several projects with a single IP address. No, I don’t use an ingress—I use Cloudflare Tunnel. There are several advantages to using it; for me, the main one is not exposing HTTP/S ports to the internet.

My deployment is handled via GitHub Actions; basically, every project follows this process:

```yaml
- name: Deploy using Docker Compose
  env:
    DOCKER_HOST: ssh://root@${{ secrets.HETZNER_IP }}
    CLOUDFLARE_TOKEN: ${{ secrets.CLOUDFLARE_TOKEN }}
  run: |
    set -e

    docker compose --file compose.yaml --file production.yaml down --remove-orphans

    docker system prune --all --force

    docker compose --file compose.yaml --file production.yaml up --build --force-recreate --detach

    echo "Listing all Docker containers:"
    docker ps -a

- name: Purge Cloudflare Cache
  env:
    CLOUDFLARE_ZONE_ID: ${{ secrets.CLOUDFLARE_ZONE_ID }}
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
  run: |
    curl -X POST "https://api.cloudflare.com/client/v4/zones/${{ secrets.CLOUDFLARE_ZONE_ID }}/purge_cache" \
          -H "Authorization: Bearer ${{ secrets.CLOUDFLARE_API_TOKEN }}" \
          -H "Content-Type: application/json" \
          --data '{"purge_everything":true}'
```

I could even easily have pull request previews, because with Cloudflare’s API I could create a subdomain for each PR, and when the PR is merged or closed, an action would tear down the resources.

In production, I have the Cloudflare Tunnel container and log forwarding to Papertrail—an excellent solution for visualizing logs and creating alerts based on search.

```yaml
x-logging: &logging
  driver: syslog
  options:
    syslog-address: "udp://logs2.papertrailapp.com:N"
    tag: "{{.Name}}/{{.ID}}"

services:
  app:
    logging:
      <<: *logging
  cloudflare:
    image: cloudflare/cloudflared:latest
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TOKEN}
    command: tunnel --no-autoupdate run
    restart: unless-stopped
    logging:
      <<: *logging
```

Finally, I concluded that I don’t need a bucket; with the correct headers, Cloudflare caches the mosaic for a while—after all, Cloudflare is a CDN.

The project turned out to be significantly simpler and free from the nasty lock-ins that cloud providers love to push.

If you want to see how it turned out, check out this repository: [https://github.com/skhaz/steamosaic](https://github.com/skhaz/steamosaic)

And if you’d like to try it, simply log in with your Steam account. Unfortunately, your collection needs to be public, since I don’t request permission to use user data—only public data: [https://steamosaic.com](https://steamosaic.com)
