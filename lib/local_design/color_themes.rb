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

# Predefined interface themes. `THEMES`' base colors are verified against
# `lib/open_project/custom_styles/color_themes.rb` at analysis time (Phase 0)
# — same hex values, so switching between the Enterprise and Local Design
# features (e.g. during an Enterprise trial) does not visually surprise an
# administrator. See docs/local-design/architecture-analysis.md, section 1,
# for why these are an independent copy rather than a shared constant.
module LocalDesign
  module ColorThemes
    DEFAULT_THEME_NAME = "OpenProject"
    CUSTOM_THEME_NAME = "Custom"

    # Only the "base" colors are stored per theme; the remaining supported
    # color keys (hover shades, foreground/text colors, focus indicator) are
    # derived from these via Colors::HexColor in `.full_palette_for` —
    # mirroring how CustomStyle itself derives hover/font colors rather than
    # storing every shade explicitly (see _inline_css.erb in the existing
    # Enterprise implementation).
    THEMES = [
      {
        theme: DEFAULT_THEME_NAME,
        colors: {
          "primary_button_background" => "#1F883D",
          "accent_color" => "#1A67A3",
          "header_background" => "#1A67A3",
          "main_menu_background" => "#FFFFFF",
          "main_menu_selected_background" => "#175A8E",
          "body_background" => "#FFFFFF"
        }
      },
      {
        theme: "OpenProject Gray",
        colors: {
          "primary_button_background" => "#1F883D",
          "accent_color" => "#1A67A3",
          "header_background" => "#FAFAFA",
          "main_menu_background" => "#ECECEC",
          "main_menu_selected_background" => "#A9A9A9",
          "body_background" => "#FFFFFF"
        }
      },
      {
        theme: "OpenProject Navy Blue",
        colors: {
          "primary_button_background" => "#1F883D",
          "accent_color" => "#1A67A3",
          "header_background" => "#05002C",
          "main_menu_background" => "#0E2045",
          "main_menu_selected_background" => "#3270DB",
          "body_background" => "#FFFFFF"
        }
      }
    ].freeze

    def self.names
      THEMES.pluck(:theme) + [CUSTOM_THEME_NAME]
    end

    def self.base_colors_for(theme_name)
      THEMES.find { |t| t[:theme] == theme_name }&.fetch(:colors)
    end

    # Every supported color key, with the derived ones computed the same way
    # the existing Enterprise implementation derives them (contrast for
    # foreground/text-on-color, darken for hover/pressed shades) — see Phase
    # 7's requirement to reuse existing derivation behavior rather than
    # inventing a new formula.
    def self.full_palette_for(theme_name)
      base = base_colors_for(theme_name)
      return nil if base.nil?

      base.merge(derived_colors_for(base))
    end

    # `::Color` (app/models/color.rb) is a plain core model — used here,
    # unsaved, purely as a Colors::HexColor-mixin wrapper around a hex
    # string, the same way `CustomStylesHelper#icon_for_color` does.
    def self.wrap(base, key)
      ::Color.new(hexcode: base.fetch(key))
    end
    private_class_method :wrap

    # `Colors::HexColor#blend` (which `darken`/`lighten` delegate to) formats
    # its result with `%02x`, i.e. lowercase — but `LocalDesignSetting`'s
    # `RGB_HEX_FORMAT` validation (matching the core mixin's own private
    # constant) only accepts uppercase A-F. Upcase every derived value so a
    # palette computed here always round-trips through a save/reload.
    def self.derived_colors_for(base)
      wrapped = {
        accent: wrap(base, "accent_color"),
        header: wrap(base, "header_background"),
        menu: wrap(base, "main_menu_background"),
        selected: wrap(base, "main_menu_selected_background"),
        primary: wrap(base, "primary_button_background")
      }

      colors_from(**wrapped)
    end
    private_class_method :derived_colors_for

    def self.colors_from(accent:, header:, menu:, selected:, primary:)
      {
        "primary_button_hover_background" => primary.darken(0.18).upcase,
        "link_color" => accent.hexcode,
        "link_hover_color" => accent.darken(0.15).upcase,
        "header_hover_background" => header.darken(0.1).upcase,
        "header_foreground" => header.contrasting_font_color,
        "main_menu_hover_background" => (menu.dark? ? menu.lighten(0.1) : menu.darken(0.06)).upcase,
        "main_menu_foreground" => menu.contrasting_font_color,
        "main_menu_selected_foreground" => selected.contrasting_font_color,
        "focus_indicator_color" => accent.hexcode
      }
    end
    private_class_method :colors_from
  end
end
