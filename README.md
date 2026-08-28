# Vanessa O'Neill — REALTOR® | Website Template

A professional, responsive, multi-page website template for **Vanessa O'Neill**, a
Southern California REALTOR® (CA DRE #01499193). Hand-built static HTML/CSS/JS — no
build step, no dependencies. The structure blends the luxury-editorial feel of Tim
Smith Real Estate with the conversion-focused flow of the Gillette Group, and it's
styled entirely in **Vanessa's own branding kit**.

## Brand

Everything follows her branding kit:

- **Colors** — **Amber** `#fc7f03` (accent) · **Steel** grays `#b2b2b2`–`#d8d8d8` ·
  **Black** `#000`–`#262626` · white. Defined as CSS variables in `:root`
  (`--gold` = amber) and swappable in one place.
- **Fonts** — **Forum** (headings) + **Montserrat** (body), via Google Fonts with
  system fallbacks.
- **Headshot & identity** — her real headshot and REALTOR® / DRE #01499193 identity
  are built in.

## Two versions — same content, two looks

| Version | Where | Look |
| --- | --- | --- |
| **Dark** | root: `home.html`, `about.html`, `service.html`, `contact.html` | Black + amber, cinematic twilight hero |
| **Light** | `light/` folder: `light/home.html`, etc. | White + amber, bright daytime hero |

The two versions share **one stylesheet, one script, and the same images** — the
light pages simply add `data-theme="light"` to the `<html>` tag. Pick whichever you
prefer (or keep both); everything else is identical.

## Pages

| File | Purpose |
| --- | --- |
| `home.html` | Homepage — hero banner, trust bar, Meet Vanessa, services, process, featured listings, testimonials, home-valuation CTA |
| `about.html` | Full bio, "why work with me" values, and all six client success stories |
| `service.html` | Buy, Sell, Home Valuation (3-step process + CMA), an interactive mortgage calculator, and guides/resources |
| `contact.html` | Contact form (with a home-valuation hand-off), contact details, hours, and map placeholder |
| `index.html` | Redirects to `home.html` so the site also loads at the domain root |

Shared assets live in `assets/` — `css/styles.css`, `js/main.js`, and `img/`
(house photos + Vanessa's headshot `vanessa.jpg`).

## How to view it

It's plain HTML — just open `home.html` (or `light/home.html`) in a browser. For
clean navigation and to let the fonts/JS load reliably, serve the folder locally:

```bash
python3 -m http.server 8000
# dark version:  http://localhost:8000/home.html
# light version: http://localhost:8000/light/home.html
```

## Images included

The template ships with **real house photographs** so it looks complete out of the box:

- `assets/img/hero-photo-dark.jpg` — twilight luxury home, hero banner (dark version)
- `assets/img/hero-photo-day.jpg` — bright daytime luxury home, hero banner (light version)
- `assets/img/listing-photo-1.jpg`, `listing-photo-2.jpg`, `listing-photo-3.jpg` — the featured-listing cards

> **Important — these are demo photos.** They come from a public real-estate image
> dataset ([emanhamed/Houses-dataset](https://github.com/emanhamed/Houses-dataset))
> and are included **for layout preview only**. Before the site goes live, replace
> them with photos Vanessa owns or has licensed (or let the MLS/IDX feed supply real
> listing photos). Swapping is trivial — see below.

## Placeholders to replace before going live

Everything below is intentionally a placeholder so the template is safe to publish
as-is and easy to finish.

1. **Vanessa's headshot** — ✅ *done.* Her headshot (from the branding kit) is at
   `assets/img/vanessa.jpg` and shown in the "Meet Vanessa" area of `home.html` and
   `about.html` (both versions). To replace it, just overwrite that file with a new
   photo of the same shape (a 4:5 portrait works best).
2. **Email address** — the document only listed a phone and office address, so
   `hello@vanessaoneill.com` is a stand-in. Find & replace it site-wide.
3. **Property listings** — the featured cards use demo photos and **sample**
   prices/addresses for layout. Connect an **MLS / IDX** feed (through her brokerage,
   iHomefinder, Showcase IDX, or RealScout) to show live listings, or replace the
   `<img class="listing__img">` sources and the price/beds text with real ones.
4. **Home search bar** (`service.html#buy`) — wire it to the same MLS/IDX provider.
5. **Contact form** — it validates and shows a confirmation but does **not** send yet.
   Point it at a form service (Formspree, Netlify Forms, Basin) or an email/CRM
   backend. In `contact.html`, set the `<form>`'s `action`/`method`, or keep the
   JavaScript handler in `assets/js/main.js` and post to your endpoint.
6. **Social links** — the Instagram / Facebook / LinkedIn icons point to `#`.
7. **Hero / property photos** — the demo photos are placeholders; swap them for
   Vanessa's own or licensed images anytime (set a photo on `.hero__bg`, or replace
   the listing `<img>` sources). See the note under **Images included**.
8. **Map** — `contact.html` has a styled placeholder; drop in a Google Maps embed.
9. **Brokerage** — no brokerage name was provided, so none is shown. Add the
   brokerage name/logo and any required license disclosures if desired.

## Customizing the look

All colors and fonts are CSS variables at the top of `assets/css/styles.css`
(`:root`), and the light theme lives in the `[data-theme="light"]` block at the
bottom of the same file. The brand colors map to `--gold` (amber `#fc7f03`),
`--ink` (black), `--sand`/`--sand-2` (steel), and `--cream` (white) — change them
in one place to adjust the whole site. Fonts are Forum + Montserrat (Google Fonts)
with system fallbacks.

## Notes

- Testimonials are Vanessa's real client reviews, lightly copyedited for the web.
- The mortgage calculator is an estimate only (principal, interest, tax, insurance)
  and excludes HOA and PMI.
- Accessible and responsive: semantic HTML, keyboard-friendly navigation, visible
  focus states, `prefers-reduced-motion` support, a mobile drawer menu, and
  progressive enhancement (all content is visible even if JavaScript doesn't run).
