# Web

Static marketing and documentation site for Cookey. Built with React + Tailwind CSS (Vite MPA), served via nginx in Docker.

## Structure

| Path                           | Purpose                                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `index.html`                   | Vite entry for landing page (/)                                                                                         |
| `get-started.html`             | Vite entry for get-started page (/get-started)                                                                          |
| `src/home.tsx`                 | React entry point for landing page                                                                                      |
| `src/get-started.tsx`          | React entry point for get-started page                                                                                  |
| `src/index.css`                | Tailwind directives + @theme tokens + @layer base overrides                                                             |
| `src/components/`              | Shared React components (Nav, Footer, Button, Badge, Terminal, Container, PropertyCard, QrCode, SectionBlock, StepCard) |
| `src/pages/HomePage.tsx`       | Landing page content                                                                                                    |
| `src/pages/GetStartedPage.tsx` | Agent handoff page content                                                                                              |
| `src/data/agentMarkdown.ts`    | Clipboard content string for agent handoff                                                                              |
| `public/`                      | Static assets (favicons, llms.txt) copied as-is to dist/                                                                |
| `nginx.conf`                   | Nginx config — port 3000, MPA routing, `/api/health` proxy                                                              |
| `Dockerfile`                   | Multi-stage: node build → nginx serve, exposes port 3000                                                                |

## Build

```bash
npm install
npm run build    # typecheck + vite build → dist/
npm run dev      # local dev server
npm run preview  # preview production build
```

## Design Conventions

- Dark theme: `#0a0a0a` background, `#f0f0f0` text, `#4ade80` accent green
- System fonts + monospace (SF Mono, JetBrains Mono, Fira Code)
- Tailwind CSS v4 with custom @theme tokens in `src/index.css`
- Responsive layout with `clamp()` fluid typography
- Container max-width: 760px
- Terminal window components for CLI demos
