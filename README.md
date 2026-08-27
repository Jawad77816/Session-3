# Vanessa O'Neill — REALTOR® | Website Template

A professional, responsive, multi-page website template for **Vanessa O'Neill**, a
Southern California REALTOR® (CA DRE #01499193). Hand-built static HTML/CSS/JS — no
build step, no dependencies. It blends the **luxury editorial** feel of Tim Smith
Real Estate Group with the **conversion-focused structure** of the Gillette Group,
using Vanessa's own bio, reviews, and services.

## Pages

| File | Purpose |
| --- | --- |
| `home.html` | Homepage — hero, trust bar, Meet Vanessa, services, process, featured-listings teaser, testimonials, home-valuation CTA |
| `about.html` | Full bio, "why work with me" values, and all six client success stories |
| `service.html` | Buy, Sell, Home Valuation (with the 3-step process + CMA), an interactive mortgage calculator, and guides/resources |
| `contact.html` | Contact form (with a home-valuation hand-off), contact details, hours, and map placeholder |
| `index.html` | Redirects to `home.html` so the site also loads at the domain root |

Shared assets live in `assets/` (`css/styles.css`, `js/main.js`, `img/`).

## How to view it

It's plain HTML — just open `home.html` in a browser. For clean navigation and to
let the fonts/JS load reliably, serve the folder locally:

```bash
python3 -m http.server 8000
# then visit http://localhost:8000/home.html
```

## Placeholders to replace before going live

Everything below is intentionally a placeholder so the template is safe to publish
as-is and easy to finish.

1. **Vanessa's headshot** — a monogram placeholder appears on `home.html` and
   `about.html`. Add her photo at `assets/img/vanessa.jpg`, then swap the placeholder
   block for the commented-out version already sitting next to it in the HTML:
   ```html
   <div class="portrait"><img src="assets/img/vanessa.jpg" alt="Vanessa O'Neill, REALTOR®"><span class="portrait__frame"></span></div>
   ```
2. **Email address** — the document only listed a phone and office address, so
   `hello@vanessaoneill.com` is a stand-in. Find & replace it site-wide with her real
   address (it appears in each footer and on `contact.html`).
3. **Property listings** — the "Featured Listings" and "Past Transactions" cards are
   placeholders (`$—`). Connect an **MLS / IDX** feed (e.g. through her brokerage,
   iHomefinder, Showcase IDX, or RealScout) to show live listings, or replace the
   cards with real photos and details.
4. **Home search bar** (`service.html#buy`) — wire it to the same MLS/IDX provider.
5. **Contact form** — it validates and shows a confirmation but does **not** send yet.
   Point it at a form service (Formspree, Netlify Forms, Basin) or an email/CRM
   backend. In `contact.html`, set the `<form>`'s `action`/`method`, or keep the
   JavaScript handler in `assets/js/main.js` and post to your endpoint.
6. **Social links** — the Instagram / Facebook / LinkedIn icons in the footer point to
   `#`. Add her real profile URLs.
7. **Hero background** — a subtle architectural texture is used by default. For a
   cinematic look, set a real photo on `.hero__bg` (a signature listing or SoCal
   skyline) in `home.html`.
8. **Map** — `contact.html` has a styled placeholder. Drop in a Google Maps embed
   `<iframe>` for the office address.
9. **Brokerage** — no brokerage name was provided, so none is shown. Add the brokerage
   name/logo and any required license disclosures if desired.

## Customizing the look

All colors and fonts are CSS variables at the top of `assets/css/styles.css`
(`:root`). To rebrand, change `--gold` (accent), `--ink` (dark base), and `--cream`
(light background). Fonts are Playfair Display + Jost (Google Fonts) with system
fallbacks.

## Notes

- Testimonials are Vanessa's real client reviews, lightly copyedited for the web.
- The mortgage calculator is an estimate only (principal, interest, tax, insurance)
  and excludes HOA and PMI.
- Built to be accessible and responsive: semantic HTML, keyboard-friendly navigation,
  visible focus states, `prefers-reduced-motion` support, and mobile layouts.
