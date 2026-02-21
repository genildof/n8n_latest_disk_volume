# n8n + FFmpeg — Easypanel Deploy

Self-hosted [n8n](https://n8n.io/) (latest) with static FFmpeg built in.
Designed for AI video automation workflows with dark frame detection and retry logic.

---

## Repository Structure

```
.
├── Dockerfile          # n8n (latest) + static FFmpeg 6.0
├── docker-compose.yml  # Easypanel-ready service definition
└── README.md
```

---

## Deploy on Easypanel

### 1. Push this repo to GitHub

```bash
git init
git add Dockerfile docker-compose.yml README.md
git commit -m "feat: n8n latest + FFmpeg with dark video detection"

# Create the repo at https://github.com/new (can be private), then:
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git branch -M main
git push -u origin main
```

### 2. Create the log folder on the host server

SSH into the server where Easypanel is running and run this **before** deploying:

```bash
sudo mkdir -p /opt/n8n/logs/dark_video_errors
sudo chown -R 1000:1000 /opt/n8n/logs
```

> **Why uid 1000?** The n8n container runs as the `node` user (uid 1000).
> Without this, Code nodes cannot write the `.jsonl` error log files.

### 3. Create the service in Easypanel

1. **Create Project → Create Service → App**
2. **Source tab** → connect GitHub → select this repository
3. **Build tab** → confirm **Dockerfile** is selected as the builder
4. **Domains tab** → add your domain (e.g. `n8n.yourdomain.com`)
   - Easypanel provisions SSL automatically via Traefik
5. **Environment tab** → add the required variables:

| Variable | Description |
|---|---|
| `N8N_HOST` | Your domain, e.g. `n8n.yourdomain.com` |
| `WEBHOOK_URL` | Full URL, e.g. `https://n8n.yourdomain.com` |
| `N8N_ENCRYPTION_KEY` | Random 32-char string (see below to generate) |

Generate a secure encryption key:
```bash
openssl rand -hex 32
```

6. **Deploy** — the first build takes ~3–5 minutes (FFmpeg binary is large)

---

## Environment Variables Reference

All variables already set in `docker-compose.yml` with their defaults:

| Variable | Value | Notes |
|---|---|---|
| `N8N_RUNNERS_ENABLED` | `true` | Required in n8n 2.x for Code nodes |
| `N8N_RUNNERS_MODE` | `internal` | Runs task runner inside the same container |
| `NODE_FUNCTION_ALLOW_BUILTIN` | `fs,child_process,os,path,buffer` | Node built-ins allowed in Code nodes |
| `N8N_ALLOW_EXEC` | `true` | Re-enables ExecuteCommand node (disabled by default in n8n 2.x) |
| `N8N_DEFAULT_BINARY_DATA_MODE` | `filesystem` | In-memory binary mode was removed in n8n 2.x |
| `N8N_SECURE_COOKIE` | `true` | Requires HTTPS — set to `false` for local dev only |
| `EXECUTIONS_DATA_PRUNE` | `true` | Auto-delete old execution logs |
| `EXECUTIONS_DATA_MAX_AGE` | `168` | Keep execution history for 7 days (hours) |
| `DB_TYPE` | `sqlite` | Change to `postgresdb` for PostgreSQL |
| `GENERIC_TIMEZONE` / `TZ` | `America/Sao_Paulo` | Adjust to your timezone |

---

## Volumes

| Mount | Path in container | Description |
|---|---|---|
| `n8n_data` (Docker volume) | `/home/node/.n8n` | Workflows, credentials, SQLite DB |
| `/opt/n8n/logs` (bind mount) | `/home/n8n/logs` | Dark video error logs (`.jsonl`) |

---

## Dark Video Error Logs

When the workflow detects a black/dark video from the generation API, it saves a structured log entry to:

```
/opt/n8n/logs/dark_video_errors/dark_videos_YYYY-MM-DD.jsonl
```

Each line is a JSON object with:

```json
{
  "timestamp": "2025-02-21T14:30:00.000Z",
  "act_id": "2",
  "scene_id": "5",
  "retry_count": 1,
  "mean_luma": 3.4,
  "video_url": "https://...",
  "prompt": "Studio Ghibli...",
  "ffmpeg_output": "3.4000",
  "ffmpeg_error": null
}
```

> Detection threshold: `mean_luma < 15` (scale 0–255). Normal videos are typically above 30.
> The workflow retries up to 3 times with a 30-second interval before moving on.

---

## Useful Commands

All commands run via SSH on the host server.

### Container management

```bash
# Check container status
docker ps | grep n8n

# Stream live logs
docker logs -f n8n

# Last 100 lines
docker logs --tail=100 n8n

# Restart without rebuild
docker restart n8n
```

### Verify FFmpeg inside the container

```bash
docker exec n8n ffmpeg -version
docker exec n8n ffprobe -version
```

### Test luma analysis manually

```bash
# Replace the URL with a real video URL from the generation API
docker exec n8n bash -c "
  wget -q -O /tmp/test.mp4 'https://YOUR_VIDEO_URL.mp4' && \
  ffmpeg -hide_banner -i /tmp/test.mp4 \
    -vf 'signalstats=stat=tout' -f null - 2>&1 \
  | grep YAVG | awk '{sum+=\$NF; n++} END {printf \"Mean luma: %.2f\n\", sum/n}'
"
```

### Read dark video logs

```bash
# Today's errors (raw)
cat /opt/n8n/logs/dark_video_errors/dark_videos_$(date +%Y-%m-%d).jsonl

# Pretty-printed (requires jq: apt install jq)
cat /opt/n8n/logs/dark_video_errors/dark_videos_$(date +%Y-%m-%d).jsonl | jq .

# One-liner summary: timestamp | act | scene | retry | luma
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r \
  '[.timestamp,
    "act="+(.act_id|tostring),
    "scene="+(.scene_id|tostring),
    "retry="+(.retry_count|tostring),
    "luma="+(.mean_luma|tostring)] | join(" | ")'

# Only entries where FFmpeg failed completely (luma = -1)
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq 'select(.mean_luma == -1)'

# Error count per day
for f in /opt/n8n/logs/dark_video_errors/*.jsonl; do
  echo "$(basename $f): $(wc -l < $f) errors"
done

# Unique video URLs with issues (for support ticket)
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r '.video_url' | sort -u
```

### Export CSV for support ticket

```bash
echo "timestamp,act_id,scene_id,retry_count,mean_luma,video_url,ffmpeg_error" \
  > /tmp/dark_videos_report.csv

cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r \
  '[.timestamp,
    (.act_id|tostring),
    (.scene_id|tostring),
    (.retry_count|tostring),
    (.mean_luma|tostring),
    .video_url,
    (.ffmpeg_error // "")] | @csv' \
  >> /tmp/dark_videos_report.csv

cat /tmp/dark_videos_report.csv
```

### Fix log folder permissions

```bash
sudo chown -R 1000:1000 /opt/n8n/logs
```

### Backup

```bash
# Find the exact volume name
docker volume ls | grep n8n

# Backup n8n data (workflows, credentials, SQLite)
docker run --rm \
  -v VOLUME_NAME:/source \
  -v /opt/n8n/backup:/backup \
  alpine tar czf /backup/n8n_data_$(date +%Y%m%d_%H%M).tar.gz -C /source .

# Backup error logs
tar czf /opt/n8n/backup/dark_logs_$(date +%Y%m%d).tar.gz \
  /opt/n8n/logs/dark_video_errors/
```

---

## Updating n8n

```bash
# Edit Dockerfile locally: change n8n:latest or pin to a specific version
# Commit and push — Easypanel auto-deploys on push (if webhook is configured)

git add Dockerfile
git commit -m "chore: update n8n to X.X.X"
git push
```

---

## Troubleshooting

**Container doesn't start**
```bash
docker logs n8n --tail=50
```

**"permission denied" when writing logs**
```bash
sudo chown -R 1000:1000 /opt/n8n/logs
```

**Code node fails with `require is not defined` or `Cannot find module`**
Confirm these environment variables are set in Easypanel:
```
N8N_RUNNERS_ENABLED=true
NODE_FUNCTION_ALLOW_BUILTIN=fs,child_process,os,path,buffer
```

**ExecuteCommand node is disabled**
Confirm this is set:
```
N8N_ALLOW_EXEC=true
```

**FFmpeg not found inside container**
```bash
docker exec n8n which ffmpeg   # should return /usr/local/bin/ffmpeg
# If empty, the build failed — trigger a fresh redeploy (clear cache) in Easypanel
```
