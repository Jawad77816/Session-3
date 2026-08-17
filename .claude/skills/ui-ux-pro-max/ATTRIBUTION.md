# Attribution — UI/UX Pro Max skill bundle

These seven skills were vendored into this repository from a third-party,
MIT-licensed project. This note records their provenance and the local
modifications made during install.

## Source

- **Upstream:** https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- **Version:** 2.13.0
- **Commit:** `a38d04c3d5c298c851dbe5e6ee1965ee3de42cb5`
- **License:** MIT © 2024 Next Level Builder (a copy of `LICENSE` is included
  in each vendored skill directory).

## Vendored skills

Installed under `.claude/skills/`:

- `ui-ux-pro-max` — flagship design-intelligence skill (Python search tool +
  local databases of styles, palettes, fonts, charts, stacks).
- `ui-styling` — Tailwind / shadcn styling guidance and generators.
- `brand` — brand-guideline tooling (Node `.cjs` scripts).
- `design` — logo / corporate-identity (CIP) generation (Python scripts).
- `design-system` — design tokens and slide tooling (Node + Python scripts).
- `banner-design` — banner-design guidance (see caveat below).
- `slides` — slide-design guidance (reference-only, no scripts).

## Local modifications

To make the scripts resolve when the skills are vendored as **project** skills
(rather than loaded as a Claude Code plugin), absolute/plugin-specific paths in
the skill docs were rewritten to be project-root-relative:

- `ui-ux-pro-max/SKILL.md`: `${CLAUDE_PLUGIN_ROOT}/.claude/skills/…`
  → `.claude/skills/…`
- `design/` (SKILL.md, reference docs, and one script's printed hint):
  `~/.claude/skills/design/…` → `.claude/skills/design/…`

All other files are copied verbatim from upstream.

## Usage notes & caveats

- **Runtimes:** the flagship search tool and most helper scripts need
  **Python 3.x** (standard library only). Some skills (`brand`,
  `design-system`) use **Node.js** helper scripts. Both runtimes are available
  in this environment.
- **Run from the repo root.** The patched paths above are relative to the
  repository root, e.g.
  `python .claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --domain ux`.
- **`brand` / `design-system` / `ui-styling`** document some helper commands
  relative to their own skill directory (e.g. `node scripts/…`). Invoke those
  from inside the skill's folder, or prefix the path with
  `.claude/skills/<skill>/`.
- **`banner-design`** orchestrates companion skills (`ai-artist`,
  `ai-multimodal`, `chrome-devtools`) that are **not part of this repository**.
  Its written guidance still applies, but its scripted image/screenshot steps
  will not run here without those additional skills.
- **Network/API-dependent scripts** (e.g. `design-system`'s
  `fetch-background.py`, which pulls from Pexels/Unsplash) require the relevant
  access to function.

To upgrade later, re-vendor from the upstream repo (or use the author's
`ui-ux-pro-max-cli`) and re-apply the path rewrites above.
