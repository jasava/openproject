# Local Design

An independent, Enterprise-free admin "Design" feature for OpenProject
Community edition — interface theming, colors, and branding assets (logo,
favicon, touch icon), reachable at **Administration → Design**
(`/admin/local_design`), for installations without an Enterprise
`define_custom_style` license.

This mirrors, in spirit, the licensed Enterprise `CustomStyle` feature, but
is a fully independent implementation: no code, table, controller, or route
is shared with it, and nothing about `guard_enterprise_feature` or
`EnterpriseToken` validation is touched. See
[`adr-001-independent-design-feature.md`](adr-001-independent-design-feature.md)
for the full reasoning.

## Status

All 19 phases are implemented and tested: Interface + Branding (the MVP),
PDF export branding and fonts (Phase 15/16), and auditability (Phase 17).

## What's implemented

- **Interface tab**: 3 predefined color themes (OpenProject / OpenProject
  Gray / OpenProject Navy Blue) plus an implicit "Custom" state, 15
  configurable color concepts (button/accent/link/header/main-menu/body/
  focus-indicator, each with a hex text field, native color picker, swatch,
  per-field reset-to-default, and inline validation/contrast feedback), a
  live preview panel that updates without saving or hitting the backend,
  and a reset-to-defaults action with an asset-aware confirmation.
- **Branding tab**: upload/replace/delete for desktop logo, mobile logo,
  favicon, and touch icon, each with the documented responsive-fallback and
  default-fallback rules.
- **PDF export styles tab** (Phase 15): PDF header logo, cover background
  image, footer image (behind the same `minutes_styling_meeting_pdf`
  feature decision CustomStyle itself uses), cover text color, and a
  Generate Demo PDF action — admin-only, never publicly cached.
- **PDF export font tab** (Phase 16): regular/bold/italic/bold-italic
  TrueType uploads; the regular cut is required before any custom font
  applies, missing bold/italic/bold-italic cuts fall back to regular.
- **Runtime integration**: saved colors/theme/logo/favicon/touch-icon are
  rendered globally via `app/views/layouts/_common_head.html.erb`, and PDF
  branding is picked up by the existing `Exports::PDF::**` pipeline
  (`Exports::PDF::DemoGenerator` and every real export use it unmodified),
  with a documented precedence rule against the licensed Enterprise
  feature in both cases (see [`data-model.md`](data-model.md)).
- **Auditability** (Phase 17): every successful write (theme/color change,
  reset, asset upload, asset removal) logs an informational server event
  (`LocalDesign::AuditLog`) with the admin's user ID, action type,
  timestamp, and changed setting *names* — never a file path or binary
  content.
- **Security**: real content-decode validation (not just extension/MIME
  trust), an explicit color-key allowlist, path-traversal-safe uploads and
  downloads, admin-only authorization at two independent layers. See
  [`security.md`](security.md).

## Where things live

| Concern | Location |
|---|---|
| Model | `app/models/local_design_setting.rb` |
| Contract | `app/contracts/local_design_setting_contract.rb` |
| Services | `app/services/local_design/*.rb` |
| Controller | `app/controllers/local_design_controller.rb` |
| Helper | `app/helpers/local_design_helper.rb` |
| Views | `app/views/local_design/**` |
| Header component | `app/components/local_design/header_component.rb` |
| Uploaders | `app/uploaders/local_design_{asset,font}_uploader.rb` |
| Theme/color constants | `lib/local_design/{design,color_themes}.rb` |
| PDF branding source | `lib/local_design/pdf_branding.rb` |
| Audit logging | `lib/local_design/audit_log.rb` |
| Migration | `db/migrate/20260728120000_create_local_design_settings.rb` |
| Stimulus controllers | `frontend/src/stimulus/controllers/dynamic/local-design/*.controller.ts` |
| Locale strings | `config/locales/en.yml`, under the top-level `local_design:` key, plus a handful of shared `activerecord.attributes.local_design_setting.*` / `errors.messages.*` entries |
| Request spec | `spec/requests/local_design_spec.rb` |

## Documentation index

- [`architecture-analysis.md`](architecture-analysis.md) — the Phase 0
  repository analysis and proposed architecture (written before any code).
- [`adr-001-independent-design-feature.md`](adr-001-independent-design-feature.md)
  — why this is an independent implementation, not an extension of
  `CustomStyle`.
- [`data-model.md`](data-model.md) — the `local_design_settings` schema,
  singleton enforcement, caching, and the Enterprise-precedence rule.
- [`security.md`](security.md) — authorization, upload validation, path
  handling, CSS-output sanitization, and one real bug this session found
  and fixed (CarrierWave's size-limit check being silently swallowed by a
  shared core file).
- [`testing.md`](testing.md) — what the request-spec suite covers, the
  manual/browser verification checklist (not performed this session — no
  browser tool available), and known limitations.
- [`upgrade-guide.md`](upgrade-guide.md) — every core file this feature
  touches (`config/initializers/menus.rb`,
  `app/views/layouts/_common_head.html.erb`,
  `frontend/src/stimulus/setup.ts`, and the four `app/models/exports/pdf/**`
  PDF pipeline files), why, and how to reassess each on a future
  OpenProject upgrade.

## GPL and attribution

All new files carry the same GPLv3 header convention as the rest of this
repository, attributed to "OpenProject Local Design / Copyright (C) the
OpenProject community" rather than "OpenProject is an open source project
management software... Copyright (C) the OpenProject GmbH" — this is new,
independent code, not a modification of existing GmbH-authored files (the
handful of genuinely modified core files keep their original header
untouched).
