# Aesthetics Med & Wellness by G — Website Redesign

Five redesigned pages for **aestheticsmedbyg.com**, each a self-contained
`.html` file (embedded font, inline CSS/JS) — open any of them directly in a
browser.

## Pages (`pages/`)

| File | Page |
|------|------|
| `01-home.html` | Homepage |
| `02-about.html` | About / Meet Giana |
| `03-services-aesthetics.html` | Services (Botox, filler, lips, skin) |
| `04-contact.html` | Contact & booking |
| `05-payment-plans.html` | Payment plans / financing |

They cross-link via relative paths, so keep them in the same folder to click
between pages.

## Design system

- **Palette:** defined once as CSS custom properties in `:root` (a warm
  blush / plum / gold scheme). **This is a placeholder** — to match the live
  brand exactly, edit the `:root` tokens and the change cascades everywhere.
- **Type:** Gloock (display serif, embedded as base64) + a system sans stack.
- Responsive to mobile, keyboard-accessible (visible focus, skip link),
  `prefers-reduced-motion` respected.

## Rebuilding (`build/`)

Pages 2–5 are assembled from shared templates so they stay consistent:

- `head.tmpl` — `<head>` + design tokens + header/nav (shared)
- `foot.tmpl` — footer + scripts (shared)
- `body-*.html` — the `<main>` content for each page
- `assemble.py` — stitches head + body + foot, marks the active nav item, and
  embeds the font from `assets/gloock.b64`

Rebuild a page:

```bash
python3 build/assemble.py pages/02-about.html about "<title>" "<meta desc>" build/body-about.html
```

(`01-home.html` was authored directly, not via the assembler.)

## Placeholders to replace with real content

- Photography: hero portrait, provider photo, before/afters, treatment shots,
  Google Maps embeds (all clearly labeled in the markup).
- Real pricing (currently "personalized at consultation") and real
  Google/JaneApp reviews (sample testimonials used).
- Wire-ups: contact form → email/booking backend; financing "Apply" button →
  your provider's link (Cherry used as a sensible default).

## Notes

- `assets/gloock.b64` — base64 of Gloock-Regular (SIL OFL), embedded into pages.
- `qa/` (git-ignored) holds render screenshots used during QA.
