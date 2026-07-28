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
  # Uploads (or replaces) a single branding asset field.
  #
  # Runs independent size and decode checks *before* the file ever reaches
  # CarrierWave's `store!` — MiniMagick for images, TTFunk for fonts (Phase
  # 12: "verify that the file can be decoded", "reject HTML disguised as an
  # image"). A file that only fools the extension/declared Content-Type
  # (checked separately by LocalDesignAssetUploader/LocalDesignFontUploader
  # at save time) is rejected here first, before anything is written to
  # permanent storage.
  #
  # The size check is *not* redundant with each uploader's own `size_range`:
  # `app/uploaders/file_uploader.rb` (a shared core file both uploaders
  # inherit from) overrides `cache!` with a blanket `rescue StandardError`
  # that logs and silently swallows `CarrierWave::IntegrityError` — the
  # exact exception `size_range` raises — so an oversized file would
  # otherwise "succeed" silently instead of being rejected. Checking size
  # here, independently, before CarrierWave ever sees the file, is the only
  # way this feature can honor Phase 12's "set a reasonable size limit" /
  # "return clear validation messages" without changing that shared file.
  class UploadAssetService
    ALL_FIELDS = (LocalDesignSetting::IMAGE_FIELDS + LocalDesignSetting::FONT_FIELDS).freeze
    UPLOADER_FOR_FIELD = LocalDesignSetting::IMAGE_FIELDS.index_with { LocalDesignAssetUploader }.merge(
      LocalDesignSetting::FONT_FIELDS.index_with { LocalDesignFontUploader }
    ).freeze

    def initialize(user:, model: LocalDesignSetting.current)
      @user = user
      @model = model
    end

    def call(field:, file:)
      field = field.to_sym

      return unauthorized_result unless @user&.admin?
      return unsupported_field_result(field) unless ALL_FIELDS.include?(field)
      return file_too_large_result(field) unless size_within_limit?(field, file)

      decode_message = decode_error_for(field, file)
      return decode_failure_result(field, decode_message) if decode_message

      @model.public_send(:"#{field}=", file)
      persist(field)
    end

    private

    def size_within_limit?(field, file)
      max_size = UPLOADER_FOR_FIELD.fetch(field).new.size_range.max
      File.size(tempfile_path(file)) <= max_size
    end

    def persist(field)
      if @model.save
        LocalDesign::AuditLog.record(user: @user, action: :asset_uploaded, changed_settings: [field.to_s])
        LocalDesignSetting.invalidate_cache!
        ServiceResult.success(result: @model)
      else
        ServiceResult.failure(result: @model, errors: @model.errors)
      end
    end

    def decode_error_for(field, file)
      if LocalDesignSetting::IMAGE_FIELDS.include?(field)
        validate_image(file)
      else
        validate_font(file)
      end
    end

    def tempfile_path(file)
      file.respond_to?(:tempfile) ? file.tempfile.path : file.path
    end

    def validate_image(file)
      image = MiniMagick::Image.open(tempfile_path(file))
      :invalid_image unless image.valid?
    rescue StandardError
      :invalid_image
    end

    def validate_font(file)
      font = TTFunk::File.open(tempfile_path(file))
      :invalid_font if font.name.font_name.blank?
    rescue StandardError
      :invalid_font
    end

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

    def file_too_large_result(field)
      max_size = UPLOADER_FOR_FIELD.fetch(field).new.size_range.max
      errors = ActiveModel::Errors.new(@model)
      errors.add(field, :file_too_large, count: max_size)
      ServiceResult.failure(result: @model, errors:)
    end

    def decode_failure_result(field, message)
      errors = ActiveModel::Errors.new(@model)
      errors.add(field, message)
      ServiceResult.failure(result: @model, errors:)
    end
  end
end
