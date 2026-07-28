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

module LocalDesign
  # Applies a predefined theme (populating all 15 supported colors
  # atomically) or an individual color-field edit (merged into the existing
  # colors, switching the stored theme to "Custom" unless the resulting set
  # happens to exactly match a predefined theme's full palette — Phase 5).
  #
  # Uses the core `Contracted` concern directly (`validate_and_save`) rather
  # than the `BaseServices::Update` auto-naming convention: this feature's
  # mandated names (service namespace `LocalDesign`, model
  # `LocalDesignSetting`, contract `LocalDesignSettingContract`) don't follow
  # the plural-namespace-matches-singular-model convention that
  # `BaseServices` derives class names from, so working with `Contracted`
  # directly (the same building block `BaseServices` itself is built on) is
  # more transparent than fighting that convention with overrides.
  class UpdateService
    include Contracted

    def initialize(user:, model: LocalDesignSetting.current)
      @user = user
      @model = model
      self.contract_class = LocalDesignSettingContract
    end

    def call(params)
      params = params.to_h.symbolize_keys

      LocalDesignSetting.transaction do
        assign_attributes(params)

        success, errors = validate_and_save(@model, @user)
        raise ActiveRecord::Rollback unless success

        return finish(success:, errors:)
      end

      finish(success: false, errors: @model.errors)
    end

    private

    def finish(success:, errors:)
      return ServiceResult.failure(result: @model, errors:) unless success

      changed_settings = @model.saved_changes.keys - %w[updated_at lock_version]
      LocalDesign::AuditLog.record(user: @user, action: :settings_updated, changed_settings:)

      LocalDesignSetting.invalidate_cache!
      ServiceResult.success(result: @model)
    end

    def assign_attributes(params)
      if params.key?(:theme) && LocalDesign::ColorThemes.base_colors_for(params[:theme])
        apply_theme(params[:theme])
      elsif params.key?(:colors)
        apply_custom_colors(params[:colors])
      end

      @model.pdf_cover_text_color = params[:pdf_cover_text_color] if params.key?(:pdf_cover_text_color)
    end

    def apply_theme(theme_name)
      @model.theme = theme_name
      @model.colors = LocalDesign::ColorThemes.full_palette_for(theme_name)
    end

    def apply_custom_colors(submitted_colors)
      merged = @model.colors.merge(submitted_colors.to_h.stringify_keys)
      @model.colors = merged
      @model.theme = matching_theme_name(merged) || LocalDesign::ColorThemes::CUSTOM_THEME_NAME
    end

    def matching_theme_name(colors_hash)
      LocalDesign::ColorThemes::THEMES.map { |t| t[:theme] }.find do |name|
        palette = LocalDesign::ColorThemes.full_palette_for(name)
        LocalDesign::Design::SUPPORTED_COLOR_KEYS.all? { |key| colors_hash[key].presence == palette[key] }
      end
    end
  end
end
