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
  # Resets theme/colors to the OpenProject default. Uploaded branding assets
  # (logos, favicon, touch icon, PDF assets/fonts) are preserved unless
  # `remove_assets: true` is explicitly passed — the controller only ever
  # passes that after a second, explicit confirmation step names assets by
  # name (Phase 5's "must not delete uploaded branding assets unless the
  # confirmation explicitly states that branding assets will also be
  # removed").
  class ResetService
    include Contracted

    def initialize(user:, model: LocalDesignSetting.current)
      @user = user
      @model = model
      self.contract_class = LocalDesignSettingContract
    end

    def call(remove_assets: false)
      LocalDesignSetting.transaction do
        @model.theme = LocalDesign::ColorThemes::DEFAULT_THEME_NAME
        @model.colors = {}
        remove_all_assets! if remove_assets

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
      LocalDesign::AuditLog.record(user: @user, action: :reset_to_defaults, changed_settings:)

      LocalDesignSetting.invalidate_cache!
      ServiceResult.success(result: @model)
    end

    def remove_all_assets!
      (LocalDesignSetting::IMAGE_FIELDS + LocalDesignSetting::FONT_FIELDS).each do |field|
        @model.public_send(:"remove_#{field}!")
      end
      @model.pdf_cover_text_color = nil
    end
  end
end
