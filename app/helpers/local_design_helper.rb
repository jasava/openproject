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

module LocalDesignHelper
  include TabsHelper
  # For `RGB_HEX_FORMAT` (a private constant, but accessible unqualified to
  # any includer — the same pattern `LocalDesignSetting` itself uses).
  include ::Colors::HexColor

  def local_design_tabs
    [
      {
        name: "interface",
        partial: "local_design/interface",
        path: local_design_path(tab: :interface),
        label: t("local_design.tabs.interface")
      },
      {
        name: "branding",
        partial: "local_design/branding",
        path: local_design_path(tab: :branding),
        label: t("local_design.tabs.branding")
      },
      {
        name: "pdf_export_styles",
        partial: "local_design/pdf_export_styles",
        path: local_design_path(tab: :pdf_export_styles),
        label: t("local_design.tabs.pdf_export_styles"),
        pdf: true
      },
      {
        name: "pdf_export_font",
        partial: "local_design/pdf_export_font",
        path: local_design_path(tab: :pdf_export_font),
        label: t("local_design.tabs.pdf_export_font"),
        pdf: true
      }
    ]
  end

  # Phase 13 precedence: a legitimately licensed, configured Enterprise
  # custom style always wins over Local Design, so an installation that
  # later activates the Enterprise feature (or is evaluating a trial) sees
  # consistent, non-conflicting branding rather than a mix of both. Uses
  # only the same public, already-used-elsewhere feature-check API
  # `Accounts::EnterpriseGuard` itself calls — never reimplementing what
  # "licensed" means.
  def enterprise_custom_style_active?
    CustomStyle.current.present? && EnterpriseToken.allows_to?(:define_custom_style)
  end

  def local_design_active?
    !enterprise_custom_style_active?
  end

  def local_desktop_logo_present?
    LocalDesignSetting.current.logo.present?
  end

  def local_mobile_logo_present?
    LocalDesignSetting.current.logo_mobile.present?
  end

  def local_favicon_present?
    LocalDesignSetting.current.favicon.present?
  end

  def local_touch_icon_present?
    LocalDesignSetting.current.touch_icon.present?
  end

  def local_design_asset_download_path(field)
    setting = LocalDesignSetting.current
    uploader = setting.public_send(field)
    filename = uploader.file&.filename || field.to_s
    local_design_download_asset_path(digest: setting.digest, field:, filename:)
  end

  # Defense-in-depth for the inline-CSS partial (Phase 8): even though every
  # value read from `LocalDesignSetting#effective_colors` already passed
  # `RGB_HEX_FORMAT` validation on write, this re-checks the exact same
  # format immediately before printing it inside a `<style>` block, so a
  # future bug in some other write path can never result in unvalidated
  # text reaching raw CSS output. Falls back to a neutral, always-safe
  # value rather than silently dropping the property.
  def sanitize_hex(value)
    RGB_HEX_FORMAT.match?(value.to_s) ? value : "#000000"
  end

  # Phase 16: the four upload rows on the PDF export font tab. Mirrors
  # CustomStylesHelper#export_fonts_fields's shape.
  def local_design_pdf_font_fields
    setting = LocalDesignSetting.current

    %i[pdf_font_regular pdf_font_bold pdf_font_italic pdf_font_bold_italic].map do |field|
      font = setting.public_send(field)
      {
        field:,
        label: t("local_design.pdf_export.fonts.#{field}"),
        present: font.present?,
        filename: font.present? ? File.basename(font.file.path) : nil,
        instructions: t("local_design.pdf_export.fonts.instructions")
      }
    end
  end
end
