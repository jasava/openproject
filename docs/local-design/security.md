# Security — Local Design

## Authentication and authorization

- Every `LocalDesignController` action except `download_asset` requires
  `require_admin` (`before_action :require_admin, except: UNGUARDED_ACTIONS`)
  — unauthenticated users are redirected to login, authenticated non-admins
  get `403 Forbidden`. Verified in `spec/requests/local_design_spec.rb`
  ("as a regular (non-admin) user", "as an anonymous user").
- `LocalDesignSettingContract#user_must_be_admin` is a second,
  independent admin check at the contract layer (`errors.add :base,
  :error_unauthorized unless user&.admin?`) — the "defense in depth" layer
  documented inline in the contract: it holds even if the contract is ever
  invoked directly (console, a future non-controller caller, a test) without
  going through the controller's `before_action`.
  `UploadAssetService`/`DeleteAssetService` (which bypass the contract —
  see `data-model.md`) each carry their own equivalent `@user&.admin?`
  check.
- `download_asset` is the one intentionally unauthenticated action — it
  serves already-validated, already-stored public assets (a logo needs to
  be visible on the public login page). It accepts no user-controlled
  filesystem path (see "Path handling" below) and no way to enumerate or
  guess assets beyond what `LocalDesignSetting::IMAGE_FIELDS`/`FONT_FIELDS`
  already exist as.
- `LocalDesignController` does **not** skip or override
  `protect_from_forgery` (declared once, unconditionally, in
  `ApplicationController`) — verified in
  `spec/requests/local_design_spec.rb` ("CSRF protection") by asserting
  `:verify_authenticity_token` is present in the controller's callback
  chain, since this codebase's existing Rails request-spec harness has no
  established pattern for triggering the actual raised exception from a
  request spec.

## Upload validation (Phase 12)

Every upload goes through, in order, before anything reaches CarrierWave's
`store!`:

1. **Admin check** (`LocalDesign::UploadAssetService`).
2. **Field allowlist** — `field` must be one of
   `LocalDesignSetting::IMAGE_FIELDS + LocalDesignSetting::FONT_FIELDS`;
   nothing else is even considered a valid target.
3. **Size check** — `File.size(tempfile) <= uploader.size_range.max`
   (5 MB images, 30 MB fonts), checked **independently of CarrierWave's own
   `size_range`/`check_size!` mechanism**. This is not redundant: see
   "Known gotcha: silent size-limit swallowing" below — it was added after
   discovering CarrierWave's own enforcement is silently defeated by a
   shared core file.
4. **Real decode check** — `MiniMagick::Image.open(...).valid?` for images,
   `TTFunk::File.open(...).name.font_name.present?` for fonts. This is what
   actually catches "HTML renamed to `.png` with a spoofed
   `Content-Type: image/png`" — the browser-declared content type and the
   file extension are both attacker-controlled and never trusted; only
   whether the byte content genuinely decodes as the claimed format matters.
5. **Extension + declared-content-type allowlist**, enforced a second time
   at the CarrierWave layer (`LocalDesignAssetUploader#extension_allowlist`
   /`#content_type_allowlist`) when the model is saved — belt-and-suspenders
   with (4), not a replacement for it.

SVG is deliberately excluded from `IMAGE_EXTENSIONS`/`IMAGE_CONTENT_TYPES`:
it's an XML format that can carry embedded scripts or external references,
and this repository has no existing SVG-sanitization pipeline to reuse
(confirmed at Phase 0 analysis time) — Phase 12 explicitly forbids allowing
SVG without one.

All five checks, and every error path, are exercised in
`spec/requests/local_design_spec.rb`: non-admin upload, oversized file,
HTML renamed with a spoofed image content type, corrupt/undecodable image,
unsupported field name, missing asset (404), and deleted asset becoming
unreachable (404 after delete).

### Known gotcha: silent size-limit swallowing

`app/uploaders/file_uploader.rb` (a **shared core file**, inherited by every
uploader in this codebase, not something Local Design owns or should
modify) overrides CarrierWave's `cache!`:

```ruby
def cache!(new_file = sanitized_file)
  super
rescue StandardError => e
  Rails.logger.error "Failed cache! of temporary upload file: #{e}"
end
```

CarrierWave's own size-limit enforcement (`size_range`) works by raising
`CarrierWave::IntegrityError` — a `StandardError` — from inside `cache!`.
The override above catches and logs it, then returns normally, so from the
caller's point of view an oversized file "succeeds" silently instead of
being rejected. This was discovered empirically while writing the request
spec for this feature (a 6 MB file over the 5 MB limit was accepted with no
error), not assumed — see step 3 above: `UploadAssetService` performs its
own, independent size check specifically to route around this, since
changing the shared `cache!` override was out of scope (and would affect
every other uploader in the app, including `Attachment`).

## Path handling / traversal prevention

- **Uploads:** CarrierWave's `SanitizedFile` always derives the stored
  filename from `File.basename` of the (attacker-controlled)
  `original_filename`, discarding any directory component — confirmed by
  directly reproducing an upload with `original_filename:
  "../../../../etc/passwd.png"` and inspecting the raw `logo` column
  afterward: it contains exactly `"passwd.png"`, no `/` or `..` anywhere.
  Verified in `spec/requests/local_design_spec.rb`, "never lets an
  attacker-controlled filename escape the managed storage path".
- **Downloads:** `LocalDesignController#download_asset` takes `:digest`,
  `:field`, and `:filename` from the URL, but only `:field` is ever used to
  resolve which file to serve (checked against
  `LocalDesign::DeleteAssetService::ALL_FIELDS`, an explicit allowlist) —
  the actual filesystem path always comes from
  `@local_design_setting.public_send(field).local_file.path`, i.e. the
  uploader-managed column on the current singleton row. `:digest` only
  affects HTTP cache-busting; `:filename` only affects the browser's
  Save-As suggested name (via `send_file`, itself not used to resolve a
  path). Neither is ever interpolated into a filesystem path.

## Rendered CSS output (Phase 8)

`app/views/local_design/_inline_css.html.erb` and `_logo_css.html.erb`
print inside a `<style>` block. Two independent layers keep this safe:

1. **Fixed property names only.** The left-hand side of every `:` is always
   a literal from `LocalDesign::Design::CSS_VARIABLES` (a Ruby constant, not
   read from params) — user input is never used as a CSS property/selector
   name.
2. **Re-validated values.** Every value printed is passed through
   `LocalDesignHelper#sanitize_hex`, which re-checks the exact
   `RGB_HEX_FORMAT` (`\A#[0-9A-F]{6}\z`) regex immediately before printing
   and substitutes `#000000` on any mismatch — deliberately redundant with
   the model-level validation that should already guarantee this, so a bug
   in some *other*, future write path can never result in unvalidated text
   reaching raw CSS output. No `html_safe`/`raw` is used on any
   user-influenced string in either partial.

Verified in `spec/requests/local_design_spec.rb`, "rejects CSS injection
attempts with a readable error and does not persist them" — a value like
`"red; } body { color: red"` is rejected by `RGB_HEX_FORMAT` validation at
save time (via `Colors::HexColor::Normalizer`, which strips a leading `#`
if present but otherwise passes the value through unchanged for the format
validator to then reject) and never reaches the database, let alone the
rendered `<style>` block.

## Color-key allowlist (Phase 14)

`LocalDesignSetting#colors_use_supported_keys_and_valid_hex` rejects any
JSONB key not in `LocalDesign::Design::SUPPORTED_COLOR_KEYS` (a fixed,
15-entry Ruby array) with a proper validation error
(`activerecord.errors.models... unsupported_key`) — an administrator (or a
crafted request) cannot add arbitrary JSON keys to the `colors` column.
`LocalDesignController#permitted_colors` additionally uses
`params.expect(colors: LocalDesign::Design::SUPPORTED_COLOR_KEYS.map(&:to_sym))`
(Rails strong parameters), so unexpected keys are dropped before the model
even sees them — two independent layers, matching Phase 14's explicit "do
not mass-assign unexpected JSON keys" / "define an explicit allowlist"
requirements.

## PDF branding (Phase 15/16)

- **Same upload pipeline, same guarantees.** `pdf_logo`/`pdf_cover`/
  `pdf_footer` go through the exact same `LocalDesign::UploadAssetService`
  as the branding-tab image fields (`LocalDesignSetting::IMAGE_FIELDS`
  includes them) — same admin check, same independent size check, same
  MiniMagick decode check, same extension/content-type allowlist, same
  path-traversal-safe storage. The four `pdf_font_*` fields go through the
  same TTFunk structural decode check as any other font field
  (`LocalDesignSetting::FONT_FIELDS`), with the same 30 MB size cap.
- **Cover text color is a fixed hex value, never PDF markup.**
  `LocalDesign::PdfBranding#cover_text_color` re-validates against
  `/\A[0-9A-F]{6}\z/` immediately before handing a value to Prawn
  (mirroring `Exports::PDF::Components::Cover#validate_cover_text_color`'s
  own re-validation of the Enterprise value) — there is no way to inject
  arbitrary Prawn/PDF drawing instructions through this field, satisfying
  Phase 15's "validate cover text color as a fixed hex value" / "do not
  allow arbitrary PDF HTML or CSS."
- **Demo PDF is admin-only and never publicly cached.**
  `LocalDesignController#export_demo_pdf_download` is not in
  `UNGUARDED_ACTIONS`, so it requires `require_admin` like every other
  write-adjacent action; the response sets `expires_in 0, public: false`.
  Verified in `spec/requests/local_design_spec.rb` (a non-admin gets `403`;
  response headers never indicate public caching).
- **No new PDF library, no arbitrary PDF assembly.**
  `export_demo_pdf_download` calls `Exports::PDF::DemoGenerator` — the
  exact class `CustomStylesController#export_demo_pdf_download` already
  uses — and the four PDF-pipeline call-site edits (see
  `upgrade-guide.md`, section 4) only ever swap *which file/color/font is
  fed into Prawn's existing, unchanged embedding/font-registration APIs*;
  nothing about how a PDF is assembled changes.
- **Malformed font DoS.** `LocalDesign::PdfBranding.custom_font_active?`
  wraps its checks in the same `rescue StandardError` pattern as
  `Exports::PDF::Common::View.valid_custom_font?` (log and treat as
  inactive rather than raise), so a corrupt or adversarial font file that
  causes a downstream storage/read error degrades to "no custom font
  applied," not a broken export or a raised exception mid-request.

## Auditability (Phase 17)

`LocalDesign::AuditLog.record` is called after every successful write
(theme/color update, PDF cover text color update, reset, asset upload,
asset removal) with the admin's user ID, an action-type symbol, and the
list of changed attribute *names* (sourced from `model.saved_changes.keys`,
never a value). See `lib/local_design/audit_log.rb` and `data-model.md` for
why this is a plain `Rails.logger.info` call rather than a persisted audit
model — this codebase has no generic administrator audit-trail mechanism to
reuse, only `has_paper_trail` on specific content models. Verified in
`spec/requests/local_design_spec.rb` ("auditability (Phase 17)"), including
a test that captures the actual logged message text and asserts it never
contains a `/tmp/` path or `Rails.root` — satisfying "do not log raw
uploaded file paths from temporary directories" and, since only attribute
names are ever logged, "do not write image contents or sensitive binary
data into logs."
