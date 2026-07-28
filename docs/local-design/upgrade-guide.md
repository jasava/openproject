# Upgrade guide — Local Design

This document lists every place where Local Design touches a **core** file
(anything outside `app/**local_design*`, `app/uploaders/local_design_*`,
`app/models/local_design_setting.rb`, `app/contracts/local_design_setting_contract.rb`,
`app/services/local_design/**`, `app/controllers/local_design_controller.rb`,
`app/helpers/local_design_helper.rb`, `lib/local_design/**`,
`db/migrate/20260728120000_create_local_design_settings.rb`,
`frontend/src/stimulus/controllers/dynamic/local-design/**`, and this
feature's own views/components/locales/specs). Per the project's upgrade-safety
preference order, everything else in the feature lives in new, independent
files. This file exists so that during an OpenProject core upgrade, a
maintainer can quickly re-check each of these small integration points for
conflicts, without having to rediscover them by diffing the whole feature.

For the reasoning behind building this feature independently instead of
extending `CustomStylesController`/`CustomStyle`, see
[`adr-001-independent-design-feature.md`](adr-001-independent-design-feature.md).

## 1. `config/initializers/menus.rb` — admin menu entry

**What changed:** two edits to the existing `admin_menu` block, both scoped
to the `:custom_style` entry and its immediate neighborhood:

1. The existing `menu.push :custom_style, ...` entry's `if:` condition was
   changed from `User.current.admin?` to
   `User.current.admin? && EnterpriseToken.allows_to?(:define_custom_style)`.
2. A new entry, `menu.push :local_design, ...`, was inserted immediately
   before it, conditioned on
   `User.current.admin? && !EnterpriseToken.allows_to?(:define_custom_style)`
   and reusing the same `caption: :label_custom_style` and
   `icon: "paintbrush"`.

**Why this was necessary:** the admin menu is a singleton, code-defined
structure (`Redmine::MenuManager.map :admin_menu`) with no plugin/hook-based
registration point for conditionally swapping one entry for another based on
license state — unlike, say, a `Hook.listener`. Editing the two `if:`
clauses was the smallest change that guarantees administrators see **exactly
one** "Design" entry at all times: the Enterprise one when a real license
that grants `define_custom_style` is present, the independent Local Design
one otherwise. No new menu key collides with an existing one, and the
Enterprise entry's own guarded destination (`CustomStylesController`, which
still calls `guard_enterprise_feature` itself) is completely untouched — this
is a visibility-only change, not a licensing check duplication or bypass.

**Blast radius:** two `if:` lambdas and one new `menu.push` call, all inside
the same few lines of `config/initializers/menus.rb`. No other menu entries,
no controller code, no `EnterpriseToken`/`guard_enterprise_feature`
mechanics.

**Regression coverage:** `spec/features/local_design/admin_menu_spec.rb` /
`spec/requests/local_design_menu_spec.rb` (see
[`testing.md`](testing.md)) assert that exactly one "Design" menu entry is
rendered for an admin both with and without a `define_custom_style`-granting
enterprise token, and that it points at `/admin/local_design` vs
`/admin/custom_style` respectively.

**Reassessing on core upgrade:** if a future OpenProject release restructures
`admin_menu` (renames the `:custom_style` key, changes its `if:`/
`enterprise_feature:` shape, or introduces a proper hook for this), reapply
the same two-part change against the new structure: keep the Enterprise
entry's visibility additionally gated on `EnterpriseToken.allows_to?
(:define_custom_style)`, and keep exactly one independent fallback entry
pointing at `/admin/local_design`. If core ever adds a native hook for
"replace/augment a menu entry based on license state," prefer migrating to
that hook over keeping this direct edit.

## 2. `app/views/layouts/_common_head.html.erb` — inline CSS / favicon / touch-icon

**What changed:** two small, independent edits to this shared layout
partial, both following the exact shape of the existing `CustomStyle`
integration already in this file (added *alongside* it, nothing removed or
restructured):

1. The `<%= render "common/favicons" %>` line became an
   `if local_design_active? ... else ... end` that renders
   `local_design/favicons` instead when Local Design (not a licensed,
   configured Enterprise custom style) is the active feature.
2. A new `elsif local_design_active?` branch was added after the existing
   `if apply_custom_styles?` block, rendering
   `local_design/logo_css` and `local_design/inline_css` (both wrapped in
   `cache(LocalDesignSetting.current)`, mirroring the existing
   `cache(CustomStyle.current)` block right above it).

**Why this was necessary:** this is the single, well-established extension
point every branding-affecting `<head>` output already goes through in this
codebase (CustomStyle's own logo/color/favicon integration lives in this
same file) — there is no hook-based alternative for "inject global CSS
custom properties and favicon links on every page." Per the project's
extension-point preference order, a small, additive integration here (5)
was chosen over patching `common/_favicons.html.erb` itself, which stays
completely untouched.

**Precedence, so the two features never visually conflict:** `local_design_active?`
(`app/helpers/local_design_helper.rb`) is simply
`!(CustomStyle.current.present? && EnterpriseToken.allows_to?(:define_custom_style))`
— Local Design only ever renders its own output when no licensed *and
configured* Enterprise custom style exists. See Phase 13 in
`architecture-analysis.md` and the "precedence" tests in
`spec/requests/local_design_spec.rb`.

**Blast radius:** the `common/favicons` render call becomes conditional (old
behavior fully preserved in the `else`/first branch), and one new `elsif`
branch is added after the existing Enterprise `if`/`cache` block. No
existing line inside the `if apply_custom_styles?` block was touched.

**Regression coverage:** `spec/requests/local_design_spec.rb`, "with runtime
CSS/favicon integration (Phase 8/10/11)" — asserts the default palette's CSS
custom properties and stock favicon/touch-icon appear on an ordinary admin
page, that a saved theme's colors and an uploaded favicon replace them, and
that a licensed *and configured* Enterprise custom style suppresses all
Local Design output on the same page.

**Reassessing on core upgrade:** if a future release restructures this
partial (renames `apply_custom_styles?`, changes how `common/_favicons`
is invoked, or introduces a real hook for "contribute to `<head>`"), keep
the same two properties: (a) `local_design/favicons` is used exactly when
`common/favicons` would otherwise have been, never both; (b) Local Design's
`<style>`/`<link>` output only ever renders when
`local_design_active?` is true. If core adds a native "branding provider"
hook, prefer migrating to it over keeping this direct edit.

**Known limitation (documented, not silently claimed as complete):** the
five CSS custom properties that did not exist in v17.6.0
(`LocalDesign::Design::NEWLY_INTRODUCED_VARIABLE_KEYS`) are wired to
best-effort, conservatively scoped selectors in
`app/views/local_design/_inline_css.html.erb` (found by grepping
`frontend/src/global_styles` at analysis time), not verified pixel-by-pixel
in a browser — this repo's local dev environment has no browser tool
available this session. See `docs/local-design/testing.md`, "Known
limitations", for the exact selectors and what to visually spot-check.

## 3. `frontend/src/stimulus/setup.ts` — registering the two new Stimulus controllers

**What changed:** two `import` lines and two
`OpenProjectStimulusApplication.preregister(...)` calls added, for
`local-design--preview` (`frontend/src/stimulus/controllers/dynamic/
local-design/preview.controller.ts`, Phase 9's live preview + Phase 7's
client-side contrast warning) and `local-design--reset`
(`.../local-design/reset.controller.ts`, the reset-confirmation-message
controller).

**Why this was necessary:** this is the standard, only way any new
`data-controller="..."` value becomes a real Stimulus controller in this
codebase — every other dynamic controller (see the ~30 other
`preregister` calls already in this file, including this session's earlier
`team-schedule` work) is wired up exactly the same way. There is no
per-feature or plugin-style registration point; this file is itself the
registration point for controllers not owned by a Rails engine.

**Blast radius:** two import lines plus two `preregister` calls, appended
after the last existing entry — no existing line changed.

**Regression coverage:** `frontend/src/stimulus/controllers/dynamic/
local-design/*.controller.ts` pass `npx eslint` cleanly; their behavior is
exercised indirectly by `spec/requests/local_design_spec.rb`'s rendering
assertions (the `data-controller`/`data-*-value` attributes these
controllers depend on are present in rendered output) but not by a
browser-level JS test — see `docs/local-design/testing.md`, "Known
limitations."

**Reassessing on core upgrade:** if `OpenProjectStimulusApplication`'s
registration mechanism changes shape, apply the same two `preregister`
calls against the new API. If a future release adds per-directory or
manifest-based auto-registration for `controllers/dynamic/**`, migrating
away from this explicit call is a reasonable simplification, not required.

## 4. PDF export call sites (Phase 15/16)

**What changed:** four files in the existing PDF export pipeline, each with
one additive `|| LocalDesign::PdfBranding.x` fallback appended to an
existing lookup chain, or (where the original method had multiple early
returns rather than a single expression) the original method body extracted
unchanged into a new private `custom_style_*` method with a two-line
dispatcher wrapping it:

| File | Method | Change |
|---|---|---|
| `app/models/exports/pdf/common/logo.rb` | `logo_image_filename` | `custom_logo_image_filename \|\| LocalDesign::PdfBranding.logo_path \|\| <default>` |
| `app/models/exports/pdf/components/cover.rb` | `custom_cover_image` | `custom_cover_image_file \|\| LocalDesign::PdfBranding.cover_path` |
| `app/models/exports/pdf/components/cover.rb` | `validate_cover_text_color` → new `custom_style_cover_text_color` | `custom_style_cover_text_color \|\| LocalDesign::PdfBranding.cover_text_color` |
| `app/models/exports/pdf/components/page.rb` | `custom_footer_image` → new `custom_style_footer_image` | `custom_style_footer_image \|\| LocalDesign::PdfBranding.footer_path` |
| `app/models/exports/pdf/common/view.rb` | `self.default_font` | `valid_custom_font? \|\| LocalDesign::PdfBranding.custom_font_active?` |
| `app/models/exports/pdf/common/view.rb` | `register_fonts!` | `if/elsif` added: Enterprise custom font, then Local Design custom font, else neither |

**Why this was necessary:** there is no plugin/hook point in the PDF
pipeline for "where does branding come from" — confirmed by reading all
four files at Phase 0 analysis time. Every one of `CustomStyle.current`'s
existing lookups (`custom_logo_image_filename`, `custom_cover_image_file`,
the cover-text-color validation, `custom_footer_image`, `valid_custom_font?`)
is evaluated **first, completely unmodified** — `LocalDesign::PdfBranding`
(`lib/local_design/pdf_branding.rb`) is only ever consulted via `||`/`elsif`
once that existing lookup returns nil/false. This is deliberately *not* a
duplicated `EnterpriseToken.allows_to?` check inside these four files —
whatever the existing CustomStyle lookup already resolves to (which itself
does not check the license flag at the PDF-pipeline level, a pre-existing
core characteristic unrelated to this feature) always wins; Local Design is
purely "the next thing tried," matching the task's own explicitly-sanctioned
alternative precedence ("if accessing the Enterprise state creates tight
coupling, use: Local Design setting when enabled, else existing
OpenProject rendering behavior").

**Blast radius:** one appended `||`/`elsif` branch per method; the two
methods with multiple early-return statements (`validate_cover_text_color`,
`custom_footer_image`) had their entire original body moved verbatim into a
same-named-but-prefixed private method, so the CustomStyle code path is
provably byte-for-byte unchanged (`git diff` shows a pure move, not an
edit, for those two method bodies).

**Regression coverage:** `spec/requests/local_design_spec.rb`, "PDF
branding (Phase 15/16)" — real `Exports::PDF::DemoGenerator`/
`Exports::PDF::Common::View`/`Exports::PDF::Common::Logo` invocations
(not mocked) confirming: PDF generation still succeeds with nothing
configured (byte count sanity check via `rails runner` during development;
the automated suite exercises upload → resolved-path assertions), a Local
Design PDF logo/cover/font/cover-text-color is picked up when set, a
licensed *and configured* Enterprise custom style still wins even when
Local Design also has a PDF logo configured, and the regular font cut is
required before any custom font (Local Design's or Enterprise's) becomes
active.

**Reassessing on core upgrade:** if any of these five methods' internal
structure changes (e.g., `CustomStyle.current.export_logo...` becomes a
different expression, or a real branding-source hook is introduced),
reapply the same principle: let the existing/new Enterprise lookup resolve
first and completely unmodified, then try `LocalDesign::PdfBranding`, then
the OpenProject default — never re-implement or duplicate the Enterprise
license check itself in these files.
