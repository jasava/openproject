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

# Singleton global branding settings for the independent (non-Enterprise)
# "Design" admin feature. See docs/local-design/data-model.md for the full
# schema rationale, including why colors live in one JSONB column here
# rather than in a child table the way the Enterprise DesignColor model
# does.
class LocalDesignSetting < ApplicationRecord
  include ::Colors::HexColor

  IMAGE_FIELDS = %i[logo logo_mobile favicon touch_icon pdf_logo pdf_cover pdf_footer].freeze
  FONT_FIELDS = %i[pdf_font_regular pdf_font_bold pdf_font_italic pdf_font_bold_italic].freeze

  IMAGE_FIELDS.each { |field| mount_uploader field, LocalDesignAssetUploader }
  FONT_FIELDS.each { |field| mount_uploader field, LocalDesignFontUploader }

  validates :theme, inclusion: { in: LocalDesign::ColorThemes.names }
  validates :pdf_cover_text_color,
            format: { with: RGB_HEX_FORMAT, message: :hexcode_invalid, allow_blank: true }
  validate :colors_use_supported_keys_and_valid_hex

  normalizes :pdf_cover_text_color, with: ::Colors::HexColor::Normalizer

  # jsonb round-trips with string keys after a save/reload, but a hash
  # assigned in memory (e.g. from a contract-validated params hash before
  # the first save) may still have symbol keys — normalize eagerly so every
  # other method in this class can assume string keys unconditionally.
  #
  # Values are normalized the same way `pdf_cover_text_color` already is
  # (`Colors::HexColor::Normalizer`, also used here for consistency): a
  # `#RGB`/`#RRGGBB` value (any case) becomes canonical uppercase
  # `#RRGGBB`, satisfying Phase 6's "normalize valid values to a
  # consistent format before saving". Anything else (including any CSS
  # injection attempt) is left for `colors_use_supported_keys_and_valid_hex`
  # to reject with a proper validation error.
  def colors=(value)
    if value.is_a?(Hash)
      super(value.stringify_keys.transform_values { |v| v.is_a?(String) ? ::Colors::HexColor::Normalizer.call(v) : v })
    else
      super
    end
  end

  class << self
    # Returns the single effective settings row, memoized per request via
    # RequestStore — the exact mechanism CustomStyle.current already uses in
    # this codebase, so behavior (and its performance characteristics) is
    # familiar. Unlike CustomStyle (which tolerates zero or many historical
    # rows, taking the newest), this is a true singleton: `singleton_guard`
    # plus its unique index guarantee exactly one row can ever exist, and a
    # concurrent first-request race is resolved by re-reading rather than by
    # either request erroring out.
    def current
      RequestStore.fetch(:current_local_design_setting) { find_or_create_singleton! }
    end

    # Drops the memoized value so the next `.current` call re-reads from the
    # database. Called after every successful write (see LocalDesign::
    # UpdateService/ResetService/UploadAssetService/DeleteAssetService) —
    # required because RequestStore only guards against *repeated* reads
    # within one request, not against staleness after a write earlier in
    # that same request.
    def invalidate_cache!
      RequestStore.delete(:current_local_design_setting)
    end

    private

    def find_or_create_singleton!
      find_by(singleton_guard: 0) || create!(singleton_guard: 0)
    rescue ActiveRecord::RecordNotUnique
      # Lost a concurrent creation race — the winner's row now exists.
      find_by!(singleton_guard: 0)
    end
  end

  # `updated_at.to_i`, mirroring CustomStyle#digest exactly: not a content
  # hash, just a cheap, always-changes-on-write cache-busting token embedded
  # in asset download URLs and used as part of the inline-CSS fragment cache
  # key.
  def digest
    updated_at.to_i
  end

  # The value to actually render for `key`: an administrator-set override if
  # present, otherwise the current theme's computed default, otherwise the
  # default theme's value. Never returns nil for a supported key, so
  # rendering code never needs a third nil-handling branch beyond "is this a
  # supported key at all".
  def effective_color(key)
    key = key.to_s
    return nil unless LocalDesign::Design.supported_key?(key)

    colors[key].presence ||
      LocalDesign::ColorThemes.full_palette_for(theme)&.fetch(key, nil) ||
      LocalDesign::ColorThemes.full_palette_for(LocalDesign::ColorThemes::DEFAULT_THEME_NAME).fetch(key)
  end

  def effective_colors
    LocalDesign::Design::SUPPORTED_COLOR_KEYS.index_with { |key| effective_color(key) }
  end

  def custom_theme?
    theme == LocalDesign::ColorThemes::CUSTOM_THEME_NAME
  end

  private

  def colors_use_supported_keys_and_valid_hex
    return unless colors.is_a?(Hash)

    colors.each do |key, value|
      unless LocalDesign::Design.supported_key?(key)
        errors.add(:colors, :unsupported_key, key:)
        next
      end

      next if value.blank?

      errors.add(:colors, :hexcode_invalid, key:) unless RGB_HEX_FORMAT.match?(value.to_s)
    end
  end
end
