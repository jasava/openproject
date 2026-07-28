# ADR 001: Build "Local Design" as an independent feature, not an extension of CustomStyle

## Status

Accepted.

## Context

OpenProject already ships an Enterprise-only branding feature (`CustomStyle`,
`DesignColor`, `CustomStylesController`, `Design::UpdateDesignService`) gated
by `guard_enterprise_feature` / `EnterpriseToken.allows_to?(:define_custom_style)`.
The task was to give Community-edition administrators an equivalent-in-spirit
"Design" page — themes, colors, logos, favicon/touch-icon — **without**
touching, weakening, or bypassing that Enterprise guard in any way, and
without ever calling the licensed code path.

The two most obvious implementation strategies were:

1. Extend `CustomStyle`/`CustomStylesController` with an "or you can also use
   it unlicensed" branch.
2. Build a fully independent model, contract, services, controller, views,
   and CSS-rendering path, under new names, that never references the
   Enterprise classes except through the same public, already-used
   `EnterpriseToken.allows_to?` check every other unlicensed/licensed
   precedence decision in this codebase uses.

## Decision

Option 2. Concretely:

- New model `LocalDesignSetting` (own table `local_design_settings`), not a
  subclass or reuse of `CustomStyle`.
- New contract `LocalDesignSettingContract`, new service namespace
  `LocalDesign::*` (`UpdateService`, `ResetService`, `UploadAssetService`,
  `DeleteAssetService`), new controller `LocalDesignController`, new routes
  under `/admin/local_design`, new views under `app/views/local_design/`.
- New `lib/local_design/design.rb` / `lib/local_design/color_themes.rb`
  constants — a **duplicated**, independent copy of the small set of theme
  hex values and CSS variable names, rather than `require`-ing
  `OpenProject::CustomStyles::*` (see "Why not reuse
  `OpenProject::CustomStyles::*`" below).
- No file under `modules/community_team_planner`-style Rails engine: this
  feature is plain `app/`/`lib/` files, matching where `CustomStyle` itself
  lives (see "Why not a Rails engine" below).
- The **only** code that ever asks "is Enterprise licensed?" is
  `LocalDesignHelper#enterprise_custom_style_active?`, which calls the same
  public `EnterpriseToken.allows_to?(:define_custom_style)` API every other
  precedence decision in this codebase already uses — never
  `guard_enterprise_feature`, never `EnterpriseToken` validation internals,
  never a bypass or weakening of the existing check.

## Why not extend `CustomStylesController`/`CustomStyle`

- `CustomStylesController#show`/`#update_colors`/`#update_themes` etc. are
  wrapped by `with_enterprise_banner_guard(:define_custom_style, ...)` and
  every mutating action ends with `guard_enterprise_feature`
  (`app/controllers/custom_styles_controller.rb`). Adding an "unlicensed
  fallback" branch inside that controller would mean editing the exact
  code path the license check protects — precisely what the task
  explicitly forbids, and a much larger, riskier diff than a parallel
  implementation.
- `CustomStyle`'s own model, and `DesignColor`, are registered as an
  Enterprise feature (`OpenProject::Enterprise.register_feature`, see
  `lib/open_project/custom_styles/engine.rb`'s
  `define_custom_style`), so any shared code touching those classes
  inherits an implicit "this is the licensed feature" identity that is
  awkward (and risky to reason about on every future upgrade) to partially
  un-gate.
- The task's own naming mandate (`LocalDesignController`, `LocalDesignSetting`,
  `LocalDesign` service namespace, forbidding `CustomStyle`/
  `define_custom_style` as identifiers) is itself evidence that the intended
  shape is a parallel implementation, not a branch inside the existing one.

## Why not a Rails engine (`modules/local_design`)

The Community Team Planner feature (a previous, separate task) *was* built
as a Rails engine under `modules/`, because it needed its own permission
set, project-module registration, and Team-Planner-specific persistence
integration that the engine boilerplate (`Gemfile.modules` entry, `engine.rb`,
own routes/locales/migrate namespace) earns back.

Local Design has none of that: it is a single, global, admin-only settings
page — structurally identical in shape to `CustomStyle` itself, which lives
as plain `app/`/`lib/` files, not an engine. Building it as an engine would
add Gemfile/engine-registration surface area for no isolation benefit this
feature actually needs, and would diverge from the precedent the feature it
mirrors already sets.

## Why not reuse `OpenProject::CustomStyles::Design` / `OpenProject::CustomStyles::ColorThemes` directly

These two modules are *not* Enterprise-guarded themselves — they are plain
Ruby constants (variable-name mapping, theme hex values) that
`CustomStylesHelper`/`_inline_css.erb` read regardless of license state.
Local Design could technically `require` and reuse them.

Three reasons against it:

1. **Directory ownership.** Both files live under
   `lib/open_project/custom_styles/`, a directory whose name and continued
   existence is conceptually owned by the Enterprise feature area. A future
   refactor that folds these constants into an EE-gated class, moves them,
   or changes their shape would not be flagged by any test or review process
   as "an Enterprise-guard change" — it would look like an ordinary internal
   CustomStyle refactor — yet it would silently break Local Design. Owning
   an independent copy means Local Design's behavior is never at the mercy
   of a refactor decision made for a different, license-gated feature.
2. **Different variable set.** `OpenProject::CustomStyles::Design` exposes 5
   color concepts; Phase 6 of this task requires 15. Reusing the smaller
   module would still require inventing the other 10 independently, so the
   "shared code" savings are smaller than they first appear.
3. **Verified equivalence, not blind duplication.** The values in
   `lib/local_design/color_themes.rb` were copied from
   `lib/open_project/custom_styles/color_themes.rb` and confirmed
   byte-for-byte identical at analysis time (Phase 0), specifically so that
   switching between the two features (e.g. during an Enterprise trial) does
   not visually surprise an administrator. The duplication is a one-time,
   verified cost, not an ongoing maintenance risk — these are stable,
   rarely-changed brand color constants.

## Consequences

- **Positive:** Enterprise licensing code (`guard_enterprise_feature`,
  `EnterpriseToken` validation, `CustomStylesController`,
  `Design::UpdateDesignService`) is provably untouched — `git diff` against
  any of those files is empty. An OpenProject core upgrade that changes how
  Enterprise licensing works cannot break Local Design, and a Local Design
  bug cannot affect the licensed feature.
- **Positive:** the only two files where "who governs `<head>`
  output"/"which admin menu entry shows" logic had to become
  license-aware are `config/initializers/menus.rb` and
  `app/views/layouts/_common_head.html.erb` — both documented in
  [`upgrade-guide.md`](upgrade-guide.md) — and both are additive
  (`if`/`elsif` branches placed alongside the existing Enterprise branch,
  nothing inside it modified).
- **Negative:** some genuine duplication exists (theme hex values, the
  general shape of "tabs + color-field form + upload partial"). This is an
  accepted, deliberate cost in exchange for the independence guarantee
  above — see "Why not reuse" section.
- **Negative:** two features now both need to agree on a precedence rule
  when both could theoretically apply. This is handled by a single,
  centrally-defined check (`local_design_active?` /
  `enterprise_custom_style_active?` in `LocalDesignHelper`) reused
  everywhere the precedence matters (menu, `<head>` CSS/favicon rendering) —
  see [`data-model.md`](data-model.md) for the exact precedence rule and its
  test coverage in `spec/requests/local_design_spec.rb`.
