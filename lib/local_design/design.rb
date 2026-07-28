# frozen_string_literal: true

#-- copyright
# OpenProject Local Design
# Copyright (C) the OpenProject community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#++

# Independent color/variable definitions for the Local Design feature.
#
# Deliberately NOT `require`-ing `OpenProject::CustomStyles::Design` even
# though that module is itself not Enterprise-guarded: it lives under a
# directory that conceptually belongs to the Enterprise feature area and
# could be renamed/removed/gated in a future release without that being
# flagged as an Enterprise-guard change. Local Design also needs a larger
# variable set (15 concepts) than that module exposes (5), so duplicating
# the handful of shared values here is a small, one-time cost in exchange
# for never depending on Enterprise-owned code paths.
# See docs/local-design/architecture-analysis.md, section 1.
module LocalDesign
  module Design
    # Every color key an administrator can configure. Used as the single
    # source of truth for: the settings form, the contract's allowlist
    # validation, and the CSS-rendering partial's fixed property-name
    # mapping. Never derive this list from user input.
    SUPPORTED_COLOR_KEYS = %w[
      primary_button_background
      primary_button_hover_background
      accent_color
      link_color
      link_hover_color
      header_background
      header_hover_background
      header_foreground
      main_menu_background
      main_menu_foreground
      main_menu_hover_background
      main_menu_selected_background
      main_menu_selected_foreground
      body_background
      focus_indicator_color
    ].freeze

    # Maps each supported color key to the CSS custom property it controls.
    # Where OpenProject/Primer already defines the variable (confirmed by
    # grepping frontend/src for each name during Phase 0), we reuse it
    # directly so existing CSS consumes the value with no further wiring.
    # Where no such variable exists yet (hover states, link color, focus
    # indicator), we mint a new, clearly namespaced `--op-local-design-*`
    # property and pair it with a small, narrowly-scoped CSS rule — see
    # app/views/local_design/_inline_css.html.erb.
    CSS_VARIABLES = {
      "primary_button_background" => "--primary-button-color",
      # Reuses CustomStyle's own derived hover shade name so any existing
      # CSS already keying off it (if present) continues to work.
      "primary_button_hover_background" => "--primary-button-color--major1",
      "accent_color" => "--accent-color",
      "link_color" => "--op-local-design-link-color",
      "link_hover_color" => "--op-local-design-link-hover-color",
      "header_background" => "--header-bg-color",
      "header_hover_background" => "--op-local-design-header-hover-background",
      "header_foreground" => "--header-item-font-color",
      "main_menu_background" => "--main-menu-bg-color",
      "main_menu_foreground" => "--main-menu-font-color",
      "main_menu_hover_background" => "--op-local-design-main-menu-hover-background",
      "main_menu_selected_background" => "--main-menu-bg-selected-background",
      "main_menu_selected_foreground" => "--main-menu-selected-font-color",
      "body_background" => "--body-background",
      "focus_indicator_color" => "--op-local-design-focus-indicator-color"
    }.freeze

    # Color keys whose CSS variable did not already exist in v17.6.0 and
    # therefore need the small supplemental CSS rules in _inline_css to
    # actually take visual effect (see that partial for the rules).
    NEWLY_INTRODUCED_VARIABLE_KEYS = %w[
      link_color
      link_hover_color
      header_hover_background
      main_menu_hover_background
      focus_indicator_color
    ].freeze

    def self.css_variable_for(key)
      CSS_VARIABLES.fetch(key.to_s)
    end

    def self.supported_key?(key)
      SUPPORTED_COLOR_KEYS.include?(key.to_s)
    end
  end
end
