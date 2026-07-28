# Data model — Local Design

## `local_design_settings`

A true singleton table: exactly one row can ever exist, enforced at the
database level.

| Column | Type | Notes |
|---|---|---|
| `theme` | `string` | One of `LocalDesign::ColorThemes.names` (`"OpenProject"`, `"OpenProject Gray"`, `"OpenProject Navy Blue"`, `"Custom"`). Default `"OpenProject"`. |
| `colors` | `jsonb` | `{ "<key>" => "#RRGGBB", ... }`, keys restricted to `LocalDesign::Design::SUPPORTED_COLOR_KEYS`. Default `{}`. |
| `logo`, `logo_mobile`, `favicon`, `touch_icon` | `string` | CarrierWave-mounted (`LocalDesignAssetUploader`) — column holds only the sanitized filename, never a full path or binary content. |
| `pdf_logo`, `pdf_cover`, `pdf_footer` | `string` | Same uploader; PDF export branding (Phase 15) — fed into the PDF pipeline via `LocalDesign::PdfBranding`, see below. |
| `pdf_cover_text_color` | `string` | `#RRGGBB`, normalized via `Colors::HexColor::Normalizer`; Phase 15. |
| `pdf_font_regular`, `pdf_font_bold`, `pdf_font_italic`, `pdf_font_bold_italic` | `string` | CarrierWave-mounted (`LocalDesignFontUploader`, `.ttf` only); Phase 16 custom PDF fonts, via `LocalDesign::PdfBranding`. |
| `singleton_guard` | `integer` | Always `0`. Unique-indexed — see "Singleton enforcement" below. |
| `lock_version` | `integer` | Optimistic locking (`ActiveRecord`'s standard column), included per the task's "optional `lock_version`" suggestion. |
| `created_at`, `updated_at` | `datetime` | `updated_at` doubles as the cache-busting digest source (`LocalDesignSetting#digest`) and the fragment-cache key for the rendered inline CSS. |

Why one JSONB column for all 15 colors, rather than one row per color (the
way the Enterprise `DesignColor` model does it): `LocalDesignSetting` is
already a singleton with eager creation on first read (see below), so there
is no "does a color row exist yet" bookkeeping to do — every read of
`effective_colors` is one already-loaded Ruby hash, not up to 15 additional
`DesignColor` rows to load/create/delete as an admin edits individual
fields. The tradeoff is that `LocalDesignSettingContract`'s allowlist
validation (`colors_use_supported_keys_and_valid_hex` on the model) is the
only thing standing between "administrator submits a color key" and "an
arbitrary JSON key gets written" — see [`security.md`](security.md) for how
that's enforced.

## Singleton enforcement

```ruby
def find_or_create_singleton!
  find_by(singleton_guard: 0) || create!(singleton_guard: 0)
rescue ActiveRecord::RecordNotUnique
  find_by!(singleton_guard: 0)
end
```

`singleton_guard` is always `0`, and `add_index :local_design_settings,
:singleton_guard, unique: true` (in the migration) makes a second `0` row a
database-level constraint violation, not just an application-level
convention. Two concurrent first-requests both racing to create the row:
the loser's `create!` raises `ActiveRecord::RecordNotUnique`, which is
rescued by re-reading the winner's row — no error surfaces to either
request, and exactly one row exists afterward. This is deliberately a
stricter guarantee than `CustomStyle.current` (which tolerates zero or many
historical rows and just takes the newest), matching this task's Phase 3
requirement ("Avoid creating duplicate records during concurrent requests");
either approach is valid for the Enterprise feature's own history, but
Local Design has no equivalent history/migration constraint to accommodate.

## Caching

`LocalDesignSetting.current` memoizes the row per request via `RequestStore`
(the same mechanism `CustomStyle.current` uses), so repeated calls within
one request never re-query. Every successful write
(`UpdateService`/`ResetService`/`UploadAssetService`/`DeleteAssetService`)
calls `LocalDesignSetting.invalidate_cache!` afterward, which drops the
`RequestStore` key so the *next* `.current` call — even later in the same
request — re-reads the just-written row. The rendered inline-CSS `<style>`
block (`app/views/local_design/_inline_css.html.erb`) is additionally
wrapped in Rails fragment caching (`cache(LocalDesignSetting.current)` in
`_common_head.html.erb`), keyed off the row's `updated_at`-derived cache
key, so it's never regenerated on requests where nothing changed.

## Effective color resolution

```ruby
def effective_color(key)
  colors[key].presence ||
    LocalDesign::ColorThemes.full_palette_for(theme)&.fetch(key, nil) ||
    LocalDesign::ColorThemes.full_palette_for(DEFAULT_THEME_NAME).fetch(key)
end
```

Three-tier fallback: an explicit per-key override in the `colors` JSONB
column, else the current theme's computed value for that key, else (only
reachable if `theme` is somehow a name `ColorThemes` doesn't recognize) the
default theme's value. This method never returns `nil` for a supported key,
so every rendering call site (`effective_colors`, the inline-CSS partial,
the color-field form) can treat every key as always having a real value —
no third "what if it's blank" branch needed anywhere downstream.

Selecting a predefined theme (`LocalDesign::UpdateService#apply_theme`)
writes the **entire computed 15-key palette** into `colors` (not just the 6
base colors) — so `effective_color` never actually needs the second
fallback tier in practice for a fresh theme selection; it exists for the
edge case of a `colors` hash that only has some keys set (e.g., a
still-unsaved in-memory edit).

## Branding asset precedence (Phase 13)

```ruby
def enterprise_custom_style_active?
  CustomStyle.current.present? && EnterpriseToken.allows_to?(:define_custom_style)
end

def local_design_active?
  !enterprise_custom_style_active?
end
```

Precedence, in order:

1. **Licensed *and* configured Enterprise custom style** — `CustomStyle.current`
   returns a row (an admin has actually saved something) *and*
   `EnterpriseToken.allows_to?(:define_custom_style)` is true. When both
   hold, `_common_head.html.erb` renders `custom_styles/inline_css` /
   `custom_styles/favicons` exactly as it always has — Local Design renders
   nothing.
2. **Local Design setting** — otherwise. `LocalDesignSetting.current` always
   exists (eager singleton creation), so this branch always has *something*
   to render, even in a completely unconfigured state — which happens to
   equal (3).
3. **Default OpenProject assets/colors** — the unconfigured state of (2):
   `theme == "OpenProject"`, `colors == {}`, no uploaded assets. Since the
   `"OpenProject"` theme's hex values are verified-identical to core's own
   `_variable_defaults.scss` defaults (see `adr-001`), rendering (2) in this
   state is visually a no-op — it's not a separate code path from (3).

`CustomStyle.current.present?` (not just the license check) is the
deliberate condition for step 1: a site that is licensed but has never
configured `CustomStyle` should not go visually blank just because a
license exists — whatever Local Design has configured (even nothing, i.e.
stock defaults) keeps rendering until an admin actually saves something
under the Enterprise page. See `spec/requests/local_design_spec.rb`, "with
runtime CSS/favicon integration", for the three states this resolves to
(default palette, Local-Design-customized, and Enterprise-superseded) each
verified against real rendered `<head>` output.

## PDF branding precedence (Phase 15/16)

Same three-tier precedence, applied independently inside the PDF export
pipeline (`app/models/exports/pdf/**`) via `lib/local_design/pdf_branding.rb`:

```ruby
# app/models/exports/pdf/common/logo.rb
def logo_image_filename
  custom_logo_image_filename || LocalDesign::PdfBranding.logo_path || <OpenProject default>
end
```

Unlike the `<head>` precedence above, this does **not** duplicate an
`EnterpriseToken.allows_to?` check inside the PDF files — each existing
`custom_*` lookup (`custom_logo_image_filename`, `custom_cover_image_file`,
the cover-text-color validation, `custom_footer_image`, `valid_custom_font?`)
is tried first, completely unmodified, and `LocalDesign::PdfBranding` is
only ever consulted via `||`/`elsif` once that call returns nil/false. This
is the task's own explicitly-offered alternative for exactly this
situation ("if accessing the Enterprise state creates tight coupling, use:
Local Design setting when enabled, else existing OpenProject rendering
behavior") — see `upgrade-guide.md`, section 4, for the full rationale and
the four affected files.

`LocalDesign::PdfBranding` exposes: `.logo_path`, `.cover_path`,
`.footer_path` (each: present, decodable, PDF-embeddable, or nil),
`.cover_text_color` (validated 6-hex-digit, no leading `#`, for Prawn),
`.custom_font_active?` (regular cut required; bold/italic/bold-italic
individually optional), and `.font_files` (missing cuts fall back to
regular — Phase 16's explicit requirement).
