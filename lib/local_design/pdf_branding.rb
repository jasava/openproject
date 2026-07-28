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

# Feeds LocalDesignSetting's PDF branding assets (Phase 15/16) into the
# existing OpenProject PDF export pipeline (`app/models/exports/pdf/**`) —
# never a separate PDF library, per the task's explicit requirement.
#
# Every call site that uses this module already has its own existing
# `CustomStyle.current...` lookup evaluated *first*, unmodified — this
# module is only ever consulted via `||` after that lookup returns nil (see
# docs/local-design/upgrade-guide.md, section 5, for the exact four call
# sites and why this ordering, not a duplicated license check here, is what
# keeps a licensed Enterprise custom style taking precedence).
module LocalDesign
  module PdfBranding
    extend Exports::PDF::Common::Attachments

    COVER_TEXT_COLOR_FORMAT = /\A[0-9A-F]{6}\z/

    module_function

    def logo_path
      asset_path(:pdf_logo)
    end

    def cover_path
      asset_path(:pdf_cover)
    end

    def footer_path
      asset_path(:pdf_footer)
    end

    # Mirrors Exports::PDF::Components::Cover#validate_cover_text_color:
    # normalize, strip the leading `#` (Prawn hex colors have none), and
    # only ever return a value that passes a fixed 6-hex-digit format check
    # — never arbitrary PDF color syntax.
    def cover_text_color
      hexcode = LocalDesignSetting.current.pdf_cover_text_color
      return nil if hexcode.blank?

      normalized = ::Colors::HexColor::Normalizer.call(hexcode)
      color = normalized.delete_prefix("#")
      return nil unless COVER_TEXT_COLOR_FORMAT.match?(color)

      color
    end

    # Mirrors Exports::PDF::Common::View.valid_custom_font? — Phase 16's
    # "regular font is required before custom PDF font configuration
    # becomes active" is exactly this: `regular` uses the non-optional
    # check, the other three cuts are individually optional.
    def custom_font_active?
      setting = LocalDesignSetting.current
      valid_font_cut?(setting.pdf_font_regular) &&
        valid_optional_font_cut?(setting.pdf_font_bold) &&
        valid_optional_font_cut?(setting.pdf_font_italic) &&
        valid_optional_font_cut?(setting.pdf_font_bold_italic)
    rescue StandardError => e
      Rails.logger.error "Failed to apply Local Design PDF font to export: #{e.message}"
      false
    end

    # Mirrors Exports::PDF::Common::View#custom_font_files: missing
    # bold/italic/bold-italic cuts fall back to regular (Phase 16's
    # "handle a missing bold or italic variant by falling back to regular
    # where appropriate").
    def font_files
      setting = LocalDesignSetting.current
      default = setting.pdf_font_regular.local_file
      {
        normal: default,
        bold: font_or_default(setting.pdf_font_bold, default),
        italic: font_or_default(setting.pdf_font_italic, default),
        bold_italic: font_or_default(setting.pdf_font_bold_italic,
                                     font_or_default(setting.pdf_font_bold,
                                                     font_or_default(setting.pdf_font_italic, default)))
      }.compact
    end

    def valid_font_cut?(cut)
      cut.present? && cut.local_file.present?
    end

    def valid_optional_font_cut?(cut)
      cut.blank? || cut.local_file.present?
    end

    def font_or_default(cut, default)
      cut.present? && cut.local_file.present? ? cut.local_file : default
    end

    # Mirrors Exports::PDF::Common::Logo#custom_logo_image_filename /
    # Components::Cover#custom_cover_image_file / Components::Page#custom_footer_image:
    # only an already-validated, already-stored, actually-decodable image is
    # ever returned; never a user-controlled path.
    def asset_path(field)
      uploader = LocalDesignSetting.current.public_send(field)
      return nil unless uploader.present? && uploader.local_file.present?

      image_file = uploader.local_file.path
      content_type = OpenProject::ContentTypeDetector.new(image_file).detect
      return nil unless pdf_embeddable?(content_type)

      image_file
    rescue StandardError => e
      Rails.logger.error "Failed to access Local Design PDF asset (#{field}): #{e.message}"
      nil
    end
  end
end
