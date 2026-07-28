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
  # Removes a single uploaded branding asset (logo, favicon, touch icon, or
  # a PDF asset/font). Never touches any other field — deleting one asset
  # must never affect another valid one (Phase 14).
  class DeleteAssetService
    ALL_FIELDS = (LocalDesignSetting::IMAGE_FIELDS + LocalDesignSetting::FONT_FIELDS).freeze

    def initialize(user:, model: LocalDesignSetting.current)
      @user = user
      @model = model
    end

    def call(field:)
      field = field.to_sym

      return unauthorized_result unless @user&.admin?
      return unsupported_field_result(field) unless ALL_FIELDS.include?(field)
      return ServiceResult.success(result: @model) if @model.public_send(field).blank?

      # Matches CustomStyle's own remove pattern: the uploader-level bang
      # method removes the stored file, then the model is explicitly saved
      # so the cleared column value is persisted.
      @model.public_send(:"remove_#{field}!")
      @model.save!
      LocalDesign::AuditLog.record(user: @user, action: :asset_removed, changed_settings: [field.to_s])
      LocalDesignSetting.invalidate_cache!
      ServiceResult.success(result: @model)
    end

    private

    def unauthorized_result
      errors = ActiveModel::Errors.new(@model)
      errors.add(:base, :error_unauthorized)
      ServiceResult.failure(result: @model, errors:)
    end

    def unsupported_field_result(field)
      errors = ActiveModel::Errors.new(@model)
      errors.add(:base, :unsupported_asset_field, field:)
      ServiceResult.failure(result: @model, errors:)
    end
  end
end
