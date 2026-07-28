# Architecture analysis — Local Design

Phase 0 deliverable for `feature/03_admin_design.md`. All findings below are grounded in the
actual checked-out repository (branch `feature/jasava`, commit `8dc3454ef5a`, tag `v17.6.0`
ancestor — confirmed in the two prior features on this same branch). Ruby `4.0.2` (`.ruby-version`,
noting per `feature/01`'s notes that the exact patch isn't publicly installable — local
verification used `4.0.6`), Rails `~> 8.1.3`, Node `^24.15.0`.

## 1. Existing Enterprise implementation map

| Class/component | File | Purpose | EE-guarded? | Reusable as-is? | Independent alternative |
|---|---|---|---|---|---|
| `CustomStylesController` | `app/controllers/custom_styles_controller.rb` | Admin Design page + all upload/delete/download actions | Yes — `guard_enterprise_feature(:define_custom_style, except: UNGUARDED_ACTIONS + %i[show])` | No (by design constraint) | `LocalDesignController`, no guard |
| `CustomStyle` | `app/models/custom_style.rb` | Singleton row: theme, theme_logo, per-asset CarrierWave mounts | No (model itself has no EE check) | Not reused — spec forbids `CustomStyle` as new model name; also its schema (colors split into `DesignColor`) doesn't match the requested single-table JSON design | `LocalDesignSetting` |
| `DesignColor` | `app/models/design_color.rb` | Per-variable hex color rows | No | Not reused — spec wants `colors` JSON/JSONB on the settings row, not a child table | `colors` jsonb column on `LocalDesignSetting` |
| `Design::UpdateDesignService` | `app/services/design/update_design_service.rb` | Persists theme/colors/logo in one transaction | No | Pattern reused (transaction, `ServiceResult`), code not reused | `LocalDesign::UpdateService` |
| `OpenProject::CustomStyles::ColorThemes` | `lib/open_project/custom_styles/color_themes.rb` | 3 predefined theme color sets | No (plain data module, no EE check) | **Data values reused as a reference**, but the module itself is not `require`d — see §"Why not reuse the constant" below | `LocalDesign::ColorThemes` (own copy) |
| `OpenProject::CustomStyles::Design` | `lib/open_project/custom_styles/design.rb` | `customizable_variables`, default asset paths | No | Not depended upon (same reasoning) | `LocalDesign::Design` |
| `Colors::HexColor` | `app/models/colors/hex_color.rb` | `contrasting_font_color`, `bright?`, `darken`/`lighten`, hex format/normalizer | No | **Yes — reused directly** via `include ::Colors::HexColor`, the same way `DesignColor`/`Color` do | n/a |
| `CustomStylesControllerHelper` | `app/helpers/custom_styles_controller_helper.rb` | TTF validation (`valid_ttf?`, `TTFunk`), `MAX_FONT_UPLOAD_SIZE` | No | Pattern reused (TTFunk-based validation), not the module itself (it's mixed into the EE controller) | `LocalDesign::FontValidator` |
| `LocalFileUploader` / `FogFileUploader` | `app/uploaders/local_file_uploader.rb`, `fog_file_uploader.rb` | CarrierWave storage backends, selected via `OpenProject::Configuration.file_uploader` | No | **Yes — reused directly**, same as `Attachment`/`CustomStyle` do | `LocalDesignAssetUploader < OpenProject::Configuration.file_uploader` (adds allowlists) |
| `app/views/custom_styles/_inline_css.erb`, `_inline_css_logo.erb` | same | Renders `:root { --var: ... }` into `<head>` | Gated only via the *caller* (`apply_custom_styles?` in `_common_head.html.erb`), not the partial itself | Not reused (renders `CustomStyle`-specific data) | `local_design/_inline_css.html.erb` |
| `app/views/layouts/_common_head.html.erb` | core layout | Integration point for all of the above | n/a (core file) | Must be **edited** (minimal addition) — no plugin hook exists for `<head>` content today | See §"Layout integration" |
| `config/initializers/menus.rb` (admin_menu block) | core | Registers `:custom_style` menu item with `enterprise_feature: "define_custom_style"` | The *entry itself* is gated, the registration mechanism is not | Mechanism reused, entry not touched | New `menu.push :local_design, ..., if: ->(_) { User.current.admin? }` (no `enterprise_feature:`) |
| `Exports::PDF::Common::Logo/Cover/Page`, `Exports::PDF::Common::View` | `app/models/exports/pdf/**` | Reads `CustomStyle.current` for PDF branding (logo/cover/footer/cover-text-color/fonts) | No (reads EE-owned data, but the reading code itself isn't gated) | Not reused for reading (reads the wrong model) — see Phase 13 precedence design | Own precedence check before delegating to the same Prawn font-registration API |

### Why not reuse the `OpenProject::CustomStyles::*` constants directly

`ColorThemes::THEMES` and `Design.customizable_variables` are plain, non-EE-checked Ruby data —
technically safe to `require` directly. I chose **not** to, for two reasons: (1) both files live
under `lib/open_project/custom_styles/`, a directory that conceptually belongs to the Enterprise
feature area even though these two specific files aren't gated today — a future OpenProject
refactor could rename, gate, or delete them without that being flagged as an Enterprise-guard
change, silently breaking `LocalDesign`; (2) the spec's Phase 6 wants a materially larger color
set (14 concepts) than `Design.customizable_variables` exposes (5) — reusing the constant directly
would only cover a third of the requirement anyway. `LocalDesign::ColorThemes`/`LocalDesign::Design`
therefore define their own copies of the three theme presets (same documented hex values, verified
against `lib/open_project/custom_styles/color_themes.rb` at analysis time) plus the extended
variable list. This is a deliberate DRY-vs-isolation trade-off, made in favor of isolation per the
task's upgrade-safety priorities.

## 2. Proposed architecture

**Structure choice: plain core files under `app/`, not `modules/local_design`.** Unlike the Team
Schedule feature (`feature/01`), which needed its own routes/permissions/menu across many
resources and benefited from engine isolation, Local Design is a single admin-only settings page
with one model. `CustomStyle` itself — the thing being deliberately *not* depended upon — is
implemented as plain `app/` files, confirming that's the established convention for a
core-adjacent, single-page admin feature in this codebase. A `modules/local_design` engine would
add `Gemfile.modules`/asset-pipeline registration overhead (as documented at length in
`docs/community-team-planner/upgrade-guide.md`) for no isolation benefit, since this feature has
no per-project scoping, no additional controllers beyond one, and no reason to be
disable-per-project. Plain `app/` files it is, matching `CustomStyle`'s own precedent.

- **Routes**: `/admin/local_design` (admin-namespaced, per spec) for the page itself and all
  write/delete actions (admin-only); a small set of **public**, digest-in-path download routes
  (`/local_design/:digest/logo/:filename` etc., mirroring `custom_style_logo_path`'s shape) so
  logos/favicon/touch-icon load without authentication, exactly like `CustomStyle`'s downloads do
  (a logged-out visitor must see the custom login-page branding).
- **Controller**: `LocalDesignController < ApplicationController`, `layout "admin"`,
  `menu_item :local_design`, `before_action :require_admin, except: UNGUARDED_DOWNLOAD_ACTIONS`,
  `no_authorization_required! *UNGUARDED_DOWNLOAD_ACTIONS`. No `guard_enterprise_feature` call
  anywhere in this class — that omission *is* the independence.
- **Model**: `LocalDesignSetting` (table `local_design_settings`) — one JSONB `colors` column
  (validated allowlist of keys, see Phase 6), `theme` string, per-asset CarrierWave mounts, PDF
  columns from day one (nullable, unused until Phase 15/16 lands) so no later migration is needed
  to "add" PDF support. Singleton access via `LocalDesignSetting.current`, `RequestStore`-memoized
  like `CustomStyle.current`, with a real DB-level singleton guard (see Phase 3 / data-model.md).
- **Services**: `LocalDesign::UpdateService` (theme+colors, transactional), `LocalDesign::ResetService`
  (defaults, optionally asset-destroying), `LocalDesign::UploadAssetService`,
  `LocalDesign::DeleteAssetService` — thin wrappers matching `Design::UpdateDesignService`'s
  `ServiceResult` convention, each backed by `LocalDesignSettingContract` (a real `ModelContract`,
  unlike `Design::UpdateDesignService`'s ad hoc validation — this repo's own newer modules, e.g.
  `community_team_planner`, already establish contract-per-service as the preferred pattern).
- **Uploaders**: `LocalDesignAssetUploader < OpenProject::Configuration.file_uploader` — a single
  uploader class (CarrierWave lets one class be `mount_uploader`'d for many columns) adding
  `extension_allowlist`/`content_type_allowlist` plus a `MiniMagick`-based decode check, i.e.
  strictly more validation than `CustomStyle` has today (Phase 12 requires this; `mini_magick`
  1.14.0/5.3.1 and `marcel` are already Gemfile dependencies — no new gem needed). A second,
  narrower uploader (or the same class parametrized) handles the four TTF font columns, reusing
  the `TTFunk`-based validation pattern from `CustomStylesControllerHelper`.
- **Views/components**: `app/views/local_design/{show,_interface,_branding,_pdf_export_styles,_pdf_export_font,_inline_css}.html.erb`,
  `app/components/local_design/` for anything reusable across tabs (color-field row, asset-upload
  row) — `CustomStyle`'s tab markup is copy-pasted per color field (confirmed in research); I'll
  extract a `LocalDesign::ColorFieldComponent` instead, since the spec explicitly asks not to copy
  the page "as one large unchanged template" and to prefer "maintainable partials or components."
  Tab bar: `Primer::Alpha::TabNav` via the same `Admin::DesignHeaderComponent`-style pattern
  (`Primer::OpenProject::PageHeader#with_tab_nav`), full-page navigation between tabs (matches
  `CustomStyle`'s own mechanism — no Turbo-frame partial-swap exists for this today, so introducing
  one would be new UI surface area beyond what's needed for parity).
- **Layout integration**: `app/views/layouts/_common_head.html.erb` needs one small, additive
  change — see "Core modification assessment" below.
- **CSS-variable rendering**: `app/views/local_design/_inline_css.html.erb`, rendered from
  `_common_head.html.erb` guarded by a `local_design_active?` helper (true whenever a
  `LocalDesignSetting` row exists **and** no legitimately-licensed Enterprise custom style takes
  precedence — see Phase 13). Wrapped in a Rails fragment `cache` block keyed on
  `LocalDesignSetting.current` (same `updated_at`-based cache-key mechanism `CustomStyle` uses),
  so no new CSS file is written to disk and no asset recompile/restart is needed — this is a
  server-rendered `<style>` block, identical delivery mechanism to the existing one.
- **Asset precedence**: Enterprise custom style (if legitimately licensed and configured) wins,
  then Local Design, then OpenProject defaults — see Phase 13 for the exact helper-level check.
- **Cache strategy**: `RequestStore` for `.current` (per-request), Rails fragment cache for the
  rendered `<style>` block (keyed on the record, invalidated automatically when `updated_at`
  changes — no manual cache-clear code needed beyond what `cache()` already does), 1-year
  `public, must_revalidate: false` HTTP caching on asset download responses with the digest
  embedded in the URL (identical mechanism to `CustomStyle`, proven safe).
- **PDF integration**: Phase 15/16 will read `LocalDesignSetting` through the exact same
  `Exports::PDF::Common::Logo`/`Cover`/`Page`/`View` extension points `CustomStyle` uses today,
  gated by the same precedence rule as CSS rendering. This requires touching those `Exports::PDF::*`
  files (they currently hardcode `CustomStyle.current`) — assessed in detail once Phase 15 starts;
  documented as a **known, unavoidable core touch-point** in the upgrade guide, kept to a minimal
  "check Local Design if no Enterprise style is active" branch per call site.

## 3. Database design

Single table, matching the spec's suggested schema, with one addition (a singleton guard) and one
adjustment (color validation lives in the contract, not the DB):

```ruby
create_table :local_design_settings do |t|
  t.string  :theme, null: false, default: LocalDesign::ColorThemes::DEFAULT_THEME_NAME
  t.jsonb   :colors, null: false, default: {}
  t.string  :logo
  t.string  :logo_mobile
  t.string  :favicon
  t.string  :touch_icon
  t.string  :pdf_logo
  t.string  :pdf_cover
  t.string  :pdf_footer
  t.string  :pdf_cover_text_color
  t.string  :pdf_font_regular
  t.string  :pdf_font_bold
  t.string  :pdf_font_italic
  t.string  :pdf_font_bold_italic
  t.integer :singleton_guard, null: false, default: 0
  t.integer :lock_version, null: false, default: 0
  t.timestamps
end
add_index :local_design_settings, :singleton_guard, unique: true
```

`singleton_guard` is always `0` and carries a unique index — this is the actual concurrency-safety
mechanism the spec asks for ("avoid creating duplicate records during concurrent requests," "add a
unique database constraint if an appropriate singleton key is used"): `LocalDesignSetting.current`
does a `find_or_create_by!(singleton_guard: 0)`, and a second concurrent request that also finds no
row will hit the unique index and raise `ActiveRecord::RecordNotUnique`, which `.current` rescues
by re-querying (the loser of the race simply reads what the winner just created). `lock_version`
(optimistic locking) is included per the spec's "optional" suggestion, since concurrent admin edits
to a singleton settings row is exactly the scenario optimistic locking protects against with clear,
existing Rails semantics (`ActiveRecord::StaleObjectError` surfaces as a normal contract-level
error, not a crash).

Full rationale and rejected alternatives in `docs/local-design/data-model.md` (written alongside
the model in Phase 3).

## 4. Request flow

`GET /admin/local_design(?tab=interface|branding|pdf_export_styles|pdf_export_font)` →
`require_admin` → `LocalDesignController#show` loads `LocalDesignSetting.current` (memoized) →
renders `show.html.erb` (tab header + selected tab partial), matching `CustomStyle`'s own
`params[:tab]`-driven full-page-render pattern exactly (§1 of the second research report).

`POST /admin/local_design/theme` (theme selection) / `POST /admin/local_design/colors` (individual
colors) → controller builds a permitted-params hash (explicit color-key allowlist, Phase 6/14) →
`LocalDesign::UpdateService.new(user:, model: LocalDesignSetting.current).call(params)` →
`LocalDesignSettingContract` validates (hex format via `Colors::HexColor::RGB_HEX_FORMAT`,
theme inclusion, color-key allowlist) → transactional save → cache invalidated (the fragment cache
key changes automatically since it's derived from `updated_at`) → redirect back to the same tab
with a flash notice (POST/redirect/GET, matches spec's resubmission-prevention requirement) → on
failure, re-render the tab with **HTTP 422** and inline error messages, previous valid values
preserved (the contract validates a *copy* of the attributes before they're ever assigned to the
persisted model — mirrors how `ModelContract`-based flows elsewhere in this codebase, e.g.
`community_team_planner`'s `TeamSchedules::UpdateContract`, already avoid partial writes).

## 5. Upload flow

`POST /admin/local_design/logo` (etc., one route per asset) → `require_admin` → strong params
extract the single `ActionDispatch::Http::UploadedFile` → `LocalDesign::UploadAssetService` →
`LocalDesignAssetUploader`-level validation (extension/content-type allowlist, size limit) → a
second, independent decode check (`MiniMagick::Image.open(tempfile).valid?` for images;
`TTFunk::File.open` for fonts) that runs **before** the file ever reaches CarrierWave's `store!`,
so a file that merely has a spoofed extension/`Content-Type` header but fails to decode is rejected
without ever being written to permanent storage → on success, `mount_uploader` stores it via
`OpenProject::Configuration.file_uploader` (local disk or object storage per deployment config,
unchanged) → `LocalDesignSetting#touch` implicitly bumps `updated_at` → redirect with flash notice.
Failure never removes a previously-valid asset in a different field (each asset is validated and
assigned independently before any `save!`).

## 6. CSS rendering flow

Identical delivery shape to `CustomStyle`, different data source, gated by the precedence rule:
`_common_head.html.erb` → `local_design_active?` → `cache(LocalDesignSetting.current) do render
"local_design/inline_css" end`. The partial only ever writes `--fixed-server-side-name: #{escaped
validated hex}` pairs (never an admin-supplied property name — Phase 8's core security
requirement), reading from the `colors` JSONB hash through an explicit allowlisted accessor on the
model (`LocalDesignSetting::SUPPORTED_COLOR_KEYS`), not by iterating arbitrary hash keys. Values are
re-validated at render time (`Colors::HexColor::RGB_HEX_FORMAT` match) in addition to
save-time validation, so a hand-edited DB row can never inject non-hex content into the `<style>`
block — belt-and-suspenders, cheap given the row is already loaded.

## 7. Asset precedence rule (Phase 13)

```
1. CustomStyle.current, only when EnterpriseToken.allows_to?(:define_custom_style) is true
2. LocalDesignSetting.current, when present
3. OpenProject default assets/colors
```

Implemented as a single helper, `LocalDesignHelper#effective_design_source`, that calls
`EnterpriseToken.allows_to?(:define_custom_style)` — the same **public, already-used-elsewhere**
feature-check API `Accounts::EnterpriseGuard` itself calls — never re-implementing or
second-guessing what "licensed" means. This satisfies the spec's explicit instruction ("use only
existing public feature-checking APIs," "do not reimplement Enterprise license validation") while
keeping `LocalDesign` fully decoupled: if the Enterprise gate's internals ever change, only the
truthiness of `EnterpriseToken.allows_to?` matters to this helper, not how it's computed.

## 8. PDF integration flow (Phase 15/16)

> **Implemented as planned below**, with one refinement: the actual module
> is `LocalDesign::PdfBranding` (not `LocalDesign::PdfBranding.logo_path`
> style methods only — it also gained `.cover_text_color`,
> `.custom_font_active?`, `.font_files`). See `data-model.md` ("PDF
> branding precedence") and `upgrade-guide.md` (section 4) for what was
> actually built and why; this section is kept as the original Phase 0
> plan for historical reference.

`Exports::PDF::Common::Logo#custom_logo_image_filename` and the analogous `Cover`/`Page` methods
currently do `CustomStyle.current.export_logo.local_file.path`. The minimal-diff plan is to change
each such call site to go through a small new helper,
`LocalDesign::PdfBranding.logo_path` (and `.cover_path`, `.footer_path`, `.cover_text_color`,
`.font_files`), which internally applies the exact same precedence rule as §7 before falling back
to each method's existing OpenProject-default path. This *does* require editing
`app/models/exports/pdf/common/logo.rb`, `components/cover.rb`, `components/page.rb`, and
`common/view.rb` — four core files — because there is no plugin hook in the PDF pipeline for
branding source selection today. Each edit will be a single-line call-site swap
(`CustomStyle.current.x` → `LocalDesign::PdfBranding.x`), covered by regression specs asserting
PDF export still works with no Local Design configured, and documented individually in
`upgrade-guide.md` with the exact reason no extension point existed. Per the task's explicit
permission ("If supporting PDF branding requires substantial duplication of Enterprise-only code,
document the dependency and postpone this phase"), this is *not* substantial duplication (each
site becomes one line), so PDF branding proceeds rather than being postponed — but is sequenced
after the MVP (Interface + Branding) is complete and tested, per the spec's own phase ordering.

## 9. Security risks

- **Arbitrary CSS injection** — mitigated structurally: the rendering partial never emits an
  admin-supplied property *name*, only fixed names with validated hex *values*; the contract
  rejects anything not matching `#RGB`/`#RRGGBB` before it can ever be persisted.
- **HTML-disguised-as-image / corrupt image** — mitigated by a real decode attempt
  (`MiniMagick`) in addition to extension/content-type allowlisting, run before the file is
  persisted anywhere.
- **Directory traversal / arbitrary file download** — the download routes never accept a
  filesystem path from params; they resolve `LocalDesignSetting.current`'s own uploader-managed
  path server-side, identical to `CustomStyle`'s `file_download(path_method)` pattern, which never
  interpolates `params[:filename]` into a path lookup (the `:filename` route segment exists only
  for URL readability/browser save-as naming, not for path resolution).
- **Malformed font DoS** — `TTFunk::File.open` wrapped in a rescue, same as
  `CustomStylesControllerHelper#valid_ttf?`; a 30MB size cap (matching the existing constant, not
  reinvented) bounds worst-case parse cost.
- **Non-admin access** — `require_admin` server-side on every write route; the four unauthenticated
  download actions are read-only and serve only already-validated, already-stored assets (no
  user-controlled input beyond the digest, which only affects cache-busting, not path resolution).
- **CSRF** — standard Rails `protect_from_forgery`, inherited from `ApplicationController`, no
  opt-out anywhere in the new controller (unlike the download actions' *authorization* opt-out,
  CSRF protection is unrelated and stays on for all state-changing routes).

## 10. Upgrade risks

- The four PDF call-site edits (§8) are the only planned core-file touches for the full feature;
  everything else is new files plus one small `_common_head.html.erb` addition (below). Both are
  isolated, minimal, and documented per-file in `upgrade-guide.md` once implemented.
- `LocalDesign::ColorThemes`'s hardcoded theme values will silently drift from
  `OpenProject::CustomStyles::ColorThemes` if a future OpenProject release changes the Enterprise
  defaults — an accepted, documented trade-off (§1) in favor of decoupling.
- Reuses `Colors::HexColor` and CarrierWave uploader infrastructure directly (not copied), so
  upstream fixes/security patches to those still apply to `LocalDesign` automatically.

## Core modification assessment

| File | Change | Why no extension point exists | Regression coverage plan |
|---|---|---|---|
| `app/views/layouts/_common_head.html.erb` | Add a conditional `render "local_design/inline_css"` + favicon/touch-icon `<link>` block, mirroring the existing `CustomStyle` block, guarded by `local_design_active?` | No plugin/hook point for `<head>` content exists in this layout today (confirmed by reading the file — it's a flat sequence of `render partial:` calls, no `content_for`/hook API) | Request spec asserting login page and a logged-in page both render correctly with (a) no Local Design configured, (b) Local Design configured, (c) Enterprise style configured and taking precedence |
| `app/models/exports/pdf/common/logo.rb`, `components/cover.rb`, `components/page.rb`, `common/view.rb` | One-line call-site swap per branding lookup (Phase 15/16 only) | No plugin hook for PDF branding source selection | PDF export regression specs with/without Local Design configured |

No other core files are expected to change. `config/routes.rb` gets new route *entries* (additive),
not modifications to existing ones.

## 11. Testing strategy

Mirrors the conventions found in `spec/models/custom_style_spec.rb`,
`spec/controllers/custom_styles_controller_spec.rb`, `spec/models/design_color_spec.rb`, and
`spec/features/custom_styles/tabs_navigation_spec.rb` — model specs, controller/request specs,
contract/service specs (a gap `Design::UpdateDesignService` itself has today — `LocalDesign`'s
services get their own specs from the start), helper specs, and a feature spec for the tabbed page.
No `with_ee:` RSpec tag is needed anywhere in the new suite (nothing here is Enterprise-gated);
existing Enterprise specs (`custom_style_spec.rb`, `custom_styles_controller_spec.rb`, etc.) are
re-run unmodified as regression coverage that the Enterprise guard still works. Full breakdown in
`docs/local-design/testing.md` (written in Phase 18).
