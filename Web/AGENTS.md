# Web

Static marketing and documentation site for Cookey. Served via nginx in Docker.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Landing page — hero, features, "how it works" steps, design properties |
| `get-started.html` | Install guide — platform tabs (macOS/Linux), CLI reference, LLM agents section |
| `llms.txt` | Machine-readable tool description for LLM agent integration |
| `nginx.conf` | Nginx config — port 3000, SPA routing, `/api/health` proxy to `api:5800` |
| `Dockerfile` | nginx:1.29-alpine base, copies static files, exposes port 3000 |

## Design Conventions

- Dark theme: `#0a0a0a` background, `#f0f0f0` text, `#4ade80` accent green
- System fonts + monospace (SF Mono, JetBrains Mono, Fira Code)
- Inline CSS, no build step or external dependencies
- Responsive layout with `clamp()` fluid typography
- Container max-width: 760px
- Terminal window components for CLI demos
