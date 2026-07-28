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

# Administration -> Design (independent of, and never depending on, the
# Enterprise-gated CustomStylesController). No `guard_enterprise_feature`
# call anywhere in this class, no `EnterpriseToken` write/bypass — that
# omission is the entire independence story. See
# docs/local-design/adr-001-independent-design-feature.md.
class LocalDesignController < ApplicationController
  include LocalDesignHelper

  layout "admin"
  menu_item :local_design

  # Only these four are reachable without an admin session — they serve
  # already-validated, already-stored public assets (login-page branding,
  # favicon) and accept no user-controlled path (Phase 2, Phase 12).
  UNGUARDED_ACTIONS = %i[download_asset].freeze

  before_action :require_admin, except: UNGUARDED_ACTIONS
  skip_before_action :check_if_login_required, only: UNGUARDED_ACTIONS
  no_authorization_required! *UNGUARDED_ACTIONS

  before_action :find_setting

  def show; end

  def update_theme
    call = LocalDesign::UpdateService.new(user: current_user, model: @local_design_setting)
             .call(theme: params.expect(local_design_setting: [:theme])[:theme])

    respond_to_update(call, redirect_tab: "interface")
  end

  def update_colors
    call = LocalDesign::UpdateService.new(user: current_user, model: @local_design_setting)
             .call(colors: permitted_colors)

    respond_to_update(call, redirect_tab: "interface")
  end

  def reset
    call = LocalDesign::ResetService.new(user: current_user, model: @local_design_setting)
             .call(remove_assets: params[:remove_assets] == "1")

    respond_to_update(call, redirect_tab: "interface")
  end

  def upload_asset
    field = params.expect(:field)
    file = params.require(:file)

    call = LocalDesign::UploadAssetService.new(user: current_user, model: @local_design_setting)
             .call(field:, file:)

    respond_to_update(call, redirect_tab: tab_for_field(field))
  end

  def delete_asset
    field = params.expect(:field)

    call = LocalDesign::DeleteAssetService.new(user: current_user, model: @local_design_setting)
             .call(field:)

    respond_to_update(call, redirect_tab: tab_for_field(field))
  end

  def update_pdf_cover_text_color
    call = LocalDesign::UpdateService.new(user: current_user, model: @local_design_setting)
             .call(pdf_cover_text_color: params[:pdf_cover_text_color])

    respond_to_update(call, redirect_tab: "pdf_export_styles")
  end

  # Phase 15: administrator-only (enforced by the same `require_admin`
  # before_action every other action here uses — not in UNGUARDED_ACTIONS),
  # and never publicly cached (`expires_in 0, public: false` below).
  # Reuses Exports::PDF::DemoGenerator directly — the same class
  # CustomStylesController#export_demo_pdf_download uses — rather than a
  # separate PDF library, per Phase 15's explicit requirement; the PDF
  # pipeline itself already resolves Local Design branding via the four
  # call-site edits documented in docs/local-design/upgrade-guide.md.
  def export_demo_pdf_download
    result = ::Exports::PDF::DemoGenerator.new.export!
    expires_in 0, public: false
    send_data result.content,
              filename: result.title,
              type: "application/pdf",
              disposition: "inline"
  rescue StandardError => e
    Rails.logger.error "Failed to generate demo PDF: #{e.message}"
    flash[:error] = e.message
    redirect_to local_design_path(tab: "pdf_export_styles")
  end

  # Public, unauthenticated: serves a previously-uploaded, previously-
  # validated asset. `:digest` only affects cache-busting (the URL embeds
  # LocalDesignSetting#digest); `:filename` only affects the browser's
  # Save-As name. Neither is used to resolve a filesystem path — the actual
  # path always comes from the uploader-managed column on the current
  # settings row, never from params (Phase 12).
  def download_asset
    field = params.expect(:field).to_sym
    return head :not_found unless LocalDesign::DeleteAssetService::ALL_FIELDS.include?(field)

    uploader = @local_design_setting.public_send(field)
    return head :not_found unless uploader.present? && uploader.readable?

    expires_in 1.year, public: true, must_revalidate: false
    send_file uploader.local_file.path, disposition: "inline"
  end

  private

  def find_setting
    @local_design_setting = LocalDesignSetting.current
  end

  def permitted_colors
    params.expect(colors: LocalDesign::Design::SUPPORTED_COLOR_KEYS.map(&:to_sym)).to_h.compact_blank
  end

  def tab_for_field(field)
    field = field.to_sym
    return "pdf_export_font" if LocalDesignSetting::FONT_FIELDS.include?(field)
    return "pdf_export_styles" if %i[pdf_logo pdf_cover pdf_footer].include?(field)

    "branding"
  end

  def respond_to_update(call, redirect_tab:)
    if call.success?
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to local_design_path(tab: redirect_tab)
    else
      @local_design_setting = call.result
      flash.now[:error] = call.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end
end
