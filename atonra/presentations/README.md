# Atonra Presentations — Marp Theme & Templates

Single source of truth for Atonra-branded presentations across all projects.
Theme, logos, and templates live here; presentation content lives in each project.

## Structure

```
atonra/presentations/
├── _themes/
│   └── atonra.css       Marp custom theme (brand colors, logo, layout)
├── _assets/
│   ├── atonra_logo_dark.png    Dark logo for light backgrounds
│   └── atonra_logo_light.png   Light logo for dark backgrounds (cover slide)
├── _templates/
│   └── default.md       Reusable skeleton for new presentations
└── README.md            This file
```

Logos are **embedded as base64 inside `atonra.css`** — the theme is fully self-contained.
The PNG files in `_assets/` are kept for direct reuse (web, docs, etc.) and as source of truth.

## Brand colors (extracted from atonra.ch)

| Variable | Hex | Usage |
|---|---|---|
| `--brand-blue` | `#051F2E` | Primary — titles, dark backgrounds |
| `--brand-orange` | `#EE5B29` | Accent — emphasis, highlights, links |
| `--brand-silver` | `#81888F` | Secondary — subtitles, footers, captions |

## How to use the theme from any project

### 1. Create your presentation `.md` in your project

```yaml
---
marp: true
theme: atonra
paginate: true
size: 16:9
---

<!-- _class: lead -->
<!-- _paginate: false -->

# Presentation Title

Author Name
YYYY-MM-DD

---

# First slide

Content here.
```

The `<!-- _class: lead -->` directive activates the cover slide layout
(dark background, centered logo, large title).

### 2. Generate HTML with the Atonra theme

```bash
FORGE_DIR="$(readlink -f ~/.claude/CLAUDE.md | xargs dirname)"
npx @marp-team/marp-cli \
  --theme-set "$FORGE_DIR/atonra/presentations/_themes/atonra.css" \
  -o my-presentation.html \
  my-presentation.md
```

Open the resulting `.html` in any browser. Press `F` for fullscreen,
arrow keys to navigate, `P` for presenter mode.

### 3. (Optional) Export to PDF

```bash
npx @marp-team/marp-cli \
  --theme-set "$FORGE_DIR/atonra/presentations/_themes/atonra.css" \
  --pdf \
  -o my-presentation.pdf \
  my-presentation.md
```

PDF export requires a local Chrome / Chromium / Edge installation.

## Markdown conventions for Atonra slides

- `# Title` — slide heading (auto-styled with brand-blue + orange underline)
- `**bold text**` — rendered in brand-orange (use for emphasis on key numbers/words)
- `*italic text*` — rendered in brand-silver (use for captions/qualifiers)
- Tables — auto-styled with brand-blue header row
- Lists — bullet markers in brand-orange

## Updating the theme

The theme file is `_themes/atonra.css`. Edit it, commit to forge, push.
All projects pick up the change at next regeneration — no copy-paste, no drift.

To update logos: replace files in `_assets/`, then regenerate the base64
embedding inside `atonra.css` (the relevant `background-image: url('data:image/png;base64,...')`
lines for `section::before` and `section.lead::before`).

## Starting a new presentation

Copy `_templates/default.md` to your project, replace placeholders, generate HTML.
