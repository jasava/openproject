# Testing — Local Design

## What exists today

A single request-spec file, `spec/requests/local_design_spec.rb`
(`type: :rails_request`), 43 examples, exercising the full stack through
real HTTP requests and real view rendering — not mocked controllers or
isolated unit tests. All 43 pass against a real PostgreSQL test database.

Run it:

```bash
bundle exec rspec spec/requests/local_design_spec.rb
```

Coverage by area:

- **Page rendering** — interface tab (default), branding tab, PDF export
  styles tab, and PDF export font tab all return `200` and render expected
  content.
- **Theme selection** — selecting a predefined theme populates and saves
  the full 15-key color palette atomically.
- **Color editing** — a single color override merges into `colors` and
  switches `theme` to `"Custom"`; a CSS-injection-shaped value is rejected
  with a `422` and a readable flash error, and never persists.
- **Reset** — resets theme/colors to defaults while preserving uploaded
  assets by default; removes assets too only when `remove_assets: "1"` is
  explicitly passed.
- **Asset upload** — accepts a real image and makes it downloadable via the
  digest-based route; accepts a real TTF for a font field; rejects an
  unsupported field name, a non-decodable "image", an HTML file renamed
  with a spoofed image content-type, and an oversized file.
- **Asset deletion** — removes an asset and confirms the download route
  then returns `404`.
- **Path-traversal** — an upload with `original_filename:
  "../../../../etc/passwd.png"` results in a raw DB column of exactly
  `"passwd.png"` (no `/`, no `..`).
- **Authorization** — non-admin and anonymous users are blocked from every
  action, including upload; `LocalDesignController`'s callback chain
  includes `:verify_authenticity_token` (CSRF protection is not opted out
  of).
- **Menu visibility** — the independent `local_design` admin-menu entry
  shows when no licensed `define_custom_style` token is active; the
  Enterprise `custom_style` entry shows instead when one is.
- **Runtime `<head>` integration** — a default (never-configured) page
  renders the default palette's CSS custom properties and the stock
  favicon/touch-icon; a saved theme's colors and an uploaded favicon
  correctly replace them; a **licensed and configured** Enterprise custom
  style suppresses all Local Design `<head>` output (Phase 13 precedence).
- **PDF branding (Phase 15/16)** — uploading a PDF logo/cover makes
  `LocalDesign::PdfBranding` resolve to the stored file's real path; saving
  a cover text color normalizes and strips the leading `#` for Prawn and
  rejects an invalid value with a `422`; the regular font cut is required
  before `custom_font_active?`/`Exports::PDF::Common::View.default_font`
  switch to the custom font, and missing bold/italic/bold-italic cuts fall
  back to the regular cut; a real `Class.new { include
  Exports::PDF::Common::Logo; include Exports::PDF::Common::Attachments }`
  instance is used (not a mock) to prove `logo_image_filename` actually
  resolves to Local Design's stored file when no Enterprise style is
  configured, and to the Enterprise style's file (not Local Design's) when
  one is licensed *and* configured.
- **Demo PDF download** — admin-only (`403` for a non-admin), returns
  `application/pdf`, response headers do not indicate public caching.
- **Auditability (Phase 17)** — asset upload, theme change, reset, and
  asset removal each call `LocalDesign::AuditLog.record` with the expected
  admin user, action type, and changed setting names (verified as an
  RSpec spy — `allow(...).and_call_original` — so the real
  `Rails.logger.info` call still happens); a separate test captures the
  actual logged message text and asserts it contains `admin_id=`,
  `action=`, `at=`, and never a `/tmp/` path or `Rails.root`.

Everything above was executed, not just written — see the phase reports in
this session's transcript for the actual failures found and fixed while
building this suite (a lowercase-hex validation bug, a `params.expect`
shape bug, a `readonly_attributes_unchanged` contract-authorization gap
that broke `reset(remove_assets: true)`, an `uploader.readable?` vs.
`uploader.local_file.readable?` bug, and the CarrierWave
size-limit-swallowing issue documented in `security.md`).

## Manual / browser verification

**Not performed this session** — no browser tool was available in this
environment. Everything above is HTTP-request-level and rendered-HTML-level
verification (real `response.body` assertions against real ERB output),
which is strong evidence the feature *functions* correctly end-to-end, but
it is not the same as a human (or automated browser) confirming the page
*looks* right: color contrast in practice, the live-preview panel's visual
behavior, the native `<input type="color">` picker, drag-free keyboard
navigation through the color fields, and screen-reader announcement of the
`aria-live` validation feedback have not been visually confirmed.

If you have browser access, the manual checklist is:

1. Log in as an admin, visit `/admin/local_design`.
2. Interface tab: switch each predefined theme, confirm the preview panel
   updates instantly (Header/Logo/Search/icons/sidebar/selected
   item/primary+secondary buttons/link/sample text — Phase 9's required
   list) without a page reload or backend request per keystroke.
3. Edit a single color's hex text field and its native color-picker
   sibling; confirm they stay in sync and the preview updates; confirm the
   "reset to theme default" button per field restores it.
4. Deliberately pick a low-contrast pair (e.g. a very light
   `main_menu_selected_background` with white `main_menu_selected_foreground`)
   and confirm the contrast warning appears near that field
   (`aria-live="polite"` — should be screen-reader announced, not just a
   color change).
5. Save colors, reload the page, confirm the real OpenProject header/menu
   now reflect the saved theme (not just the preview panel).
6. Branding tab: upload a desktop logo only, then also a mobile logo, then
   remove the desktop logo (mobile-only fallback) — resize the browser
   below ~850px each time to confirm the responsive swap described in
   `data-model.md`/Phase 10.
7. Upload a favicon and touch icon; confirm the browser tab icon changes.
8. Tab through the entire color-fields form using only the keyboard;
   confirm every control (hex input, native color input, reset button) is
   reachable and operable without a mouse.

## Known limitations

- **Five CSS custom properties are best-effort, not visually verified.**
  `LocalDesign::Design::NEWLY_INTRODUCED_VARIABLE_KEYS` (`link_color`,
  `link_hover_color`, `header_hover_background`,
  `main_menu_hover_background`, `focus_indicator_color`) did not exist as
  CSS variables in v17.6.0, so `_inline_css.html.erb` pairs each with a
  small supplemental rule targeting the closest matching selector found by
  grepping `frontend/src/global_styles` at analysis time
  (`.op-uc-container a`, `.op-app-header *:hover`, `#main-menu a:hover`,
  `:focus-visible`). These are reasonable, conservatively-scoped guesses,
  not a guarantee of pixel-perfect parity with every hover/focus state in
  the app — some existing hover feedback is applied via JS-toggled classes
  rather than native CSS `:hover`, which a CSS-only supplemental rule
  cannot reach. If you have browser access, spot-check these five
  specifically; the other ten color keys reuse pre-existing variable names
  and have no such caveat.
- **No frontend (Jasmine/Karma) tests** for the two new Stimulus
  controllers (`local-design--preview`, `local-design--reset`) — only
  `eslint` was run (clean). The team-schedule feature built earlier in this
  session established the same pattern (ESLint as the available bar,
  without a running dev server to exercise the controller live);
  `frontend/src/stimulus/controllers/dynamic/local-design/*.controller.ts`
  would benefit from `*.controller.spec.ts` coverage using the same pattern
  as `generic-drag-and-drop.controller.spec.ts` if this becomes a priority.
- **PDF footer image is behind a feature decision.** The footer-image
  upload row on the PDF export styles tab only renders when
  `OpenProject::FeatureDecisions.minutes_styling_meeting_pdf_active?` is
  true — the same gate `CustomStyle`'s own footer-image row uses. On an
  installation without that feature decision enabled, the `pdf_footer`
  column/upload route still work (exercised at the service layer in specs),
  but there is no UI to reach them, matching Phase 15's "footer image if
  supported by v17.6.0."
- **PDF visual output was not rendered and inspected by eye** — the specs
  confirm `LocalDesign::PdfBranding` resolves to the correct file/color/font
  and that `Exports::PDF::Common::Logo`/`Common::View` pick it up (via real,
  non-mocked module instances), and a manual `bundle exec rails runner`
  session during development confirmed `Exports::PDF::DemoGenerator#export!`
  produces a non-trivial PDF (tens of KB) both with and without Local
  Design PDF branding configured — but no one has opened the resulting PDF
  file and visually confirmed the logo/cover/font/color render correctly on
  the page. If you have the ability to open a generated PDF, use the
  "Generate Demo PDF" button on either PDF tab after configuring some
  branding.
