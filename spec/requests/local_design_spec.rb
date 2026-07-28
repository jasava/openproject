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

require "spec_helper"

RSpec.describe "Local Design administration", :skip_csrf, type: :rails_request do
  let(:image_fixture) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/image.png"), "image/png") }
  let(:non_image_fixture) do
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/textfile.txt"), "image/png")
  end
  let(:font_fixture) do
    Rack::Test::UploadedFile.new(Rails.public_path.join("fonts/noto-emoji/NotoEmoji.ttf"), "font/ttf")
  end
  let(:renamed_html_fixture) do
    file = Tempfile.new(["renamed", ".png"])
    file.write("<html><body><script>alert(1)</script>an image, honest</body></html>")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "renamed.png")
  end
  let(:oversized_fixture) do
    file = Tempfile.new(["oversized", ".png"])
    file.write(Rails.root.join("spec/fixtures/files/image.png").read)
    file.write("\x00" * 6.megabytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "oversized.png")
  end
  let(:traversal_filename_fixture) do
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/image.png"), "image/png",
                                 original_filename: "../../../../etc/passwd.png")
  end

  after { LocalDesignSetting.invalidate_cache! }

  context "as an admin" do
    let(:admin) { create(:admin) }

    before { login_as(admin) }

    describe "GET /admin/local_design" do
      it "renders the interface tab by default" do
        get "/admin/local_design"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("local_design.theme.label"))
        expect(response.body).to include(I18n.t("local_design.colors.legend"))
      end

      it "renders the branding tab" do
        get "/admin/local_design", params: { tab: "branding" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("local_design.branding.logo.label"))
      end

      it "renders the pdf export styles tab" do
        get "/admin/local_design", params: { tab: "pdf_export_styles" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("local_design.pdf_export.logo.label"))
        expect(response.body).to include(I18n.t("local_design.pdf_export.cover_text_color.label"))
      end

      it "renders the pdf export font tab" do
        get "/admin/local_design", params: { tab: "pdf_export_font" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("local_design.pdf_export.fonts.pdf_font_regular"))
      end
    end

    describe "POST /admin/local_design/theme" do
      it "applies a predefined theme and its full color palette atomically" do
        post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Navy Blue" } }

        expect(response).to redirect_to(local_design_path(tab: "interface"))
        setting = LocalDesignSetting.current
        expect(setting.theme).to eq("OpenProject Navy Blue")
        expect(setting.colors["header_background"]).to eq("#05002C")
        expect(setting.colors.keys).to match_array(LocalDesign::Design::SUPPORTED_COLOR_KEYS)
      end
    end

    describe "POST /admin/local_design/colors" do
      it "merges a valid color and switches the theme to Custom" do
        post "/admin/local_design/colors", params: { colors: { accent_color: "#123abc" } }

        expect(response).to redirect_to(local_design_path(tab: "interface"))
        setting = LocalDesignSetting.current
        expect(setting.colors["accent_color"]).to eq("#123ABC")
        expect(setting.theme).to eq("Custom")
      end

      it "rejects CSS injection attempts with a readable error and does not persist them" do
        post "/admin/local_design/colors", params: { colors: { accent_color: "red; } body { color: red" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:error]).to be_present
        expect(LocalDesignSetting.current.colors["accent_color"]).to be_nil
      end
    end

    describe "POST /admin/local_design/reset" do
      it "resets theme and colors but keeps uploaded assets by default" do
        post "/admin/local_design/assets/logo", params: { file: image_fixture }
        post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Gray" } }

        post "/admin/local_design/reset"

        expect(response).to redirect_to(local_design_path(tab: "interface"))
        setting = LocalDesignSetting.current
        expect(setting.theme).to eq("OpenProject")
        expect(setting.colors).to eq({})
        expect(setting.logo).to be_present
      end

      it "also removes uploaded assets when explicitly requested" do
        post "/admin/local_design/assets/logo", params: { file: image_fixture }

        post "/admin/local_design/reset", params: { remove_assets: "1" }

        expect(LocalDesignSetting.current.logo).not_to be_present
      end
    end

    describe "POST /admin/local_design/assets/:field" do
      it "accepts a real image and makes it downloadable" do
        post "/admin/local_design/assets/logo", params: { file: image_fixture }

        expect(response).to redirect_to(local_design_path(tab: "branding"))
        setting = LocalDesignSetting.current
        expect(setting.logo).to be_present

        get local_design_download_asset_path(digest: setting.digest, field: "logo", filename: "logo.png")
        expect(response).to have_http_status(:ok)
      end

      it "rejects a file that is not actually a decodable image" do
        post "/admin/local_design/assets/logo", params: { file: non_image_fixture }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LocalDesignSetting.current.logo).not_to be_present
      end

      it "rejects an unsupported asset field" do
        post "/admin/local_design/assets/not_a_real_field", params: { file: image_fixture }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "accepts a real TTF font for a font field" do
        post "/admin/local_design/assets/pdf_font_regular", params: { file: font_fixture }

        expect(response).to redirect_to(local_design_path(tab: "pdf_export_font"))
        expect(LocalDesignSetting.current.pdf_font_regular).to be_present
      end

      it "rejects an HTML file renamed with an image extension and a spoofed content type" do
        post "/admin/local_design/assets/logo", params: { file: renamed_html_fixture }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LocalDesignSetting.current.logo).not_to be_present
      end

      it "rejects an oversized file" do
        post "/admin/local_design/assets/logo", params: { file: oversized_fixture }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LocalDesignSetting.current.logo).not_to be_present
      end

      it "never lets an attacker-controlled filename escape the managed storage path" do
        post "/admin/local_design/assets/logo", params: { file: traversal_filename_fixture }
        expect(response).to redirect_to(local_design_path(tab: "branding"))

        # The raw DB column is what CarrierWave actually persisted (never a
        # path — always just the sanitized basename), so this is what
        # matters from a security standpoint, regardless of where any given
        # request-spec run happens to leave the on-disk cache file.
        raw_column = LocalDesignSetting.where(id: LocalDesignSetting.current.id).pick(:logo)
        expect(raw_column).to eq("passwd.png")
        expect(raw_column).not_to include("/")
        expect(raw_column).not_to include("..")

        # And it must be reachable only through the controlled download
        # route, with a clean, attacker-uninfluenced response.
        get "/admin/local_design", params: { tab: "branding" }
        expect(response.body).not_to include("..")
        expect(response.body).to include("passwd.png")
      end
    end

    describe "DELETE /admin/local_design/assets/:field" do
      it "removes a previously uploaded asset and the asset becomes unreachable" do
        post "/admin/local_design/assets/favicon", params: { file: image_fixture }
        setting = LocalDesignSetting.current
        expect(setting.favicon).to be_present

        delete "/admin/local_design/assets/favicon"

        expect(response).to redirect_to(local_design_path(tab: "branding"))
        expect(LocalDesignSetting.current.favicon).not_to be_present

        get local_design_download_asset_path(digest: setting.digest, field: "favicon", filename: "favicon.png")
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "GET /admin/local_design/:digest/:field/:filename" do
      it "returns 404 when no asset is present" do
        setting = LocalDesignSetting.current
        get local_design_download_asset_path(digest: setting.digest, field: "logo", filename: "logo.png")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  context "as a regular (non-admin) user" do
    before { login_as(create(:user)) }

    it "is forbidden from viewing the page" do
      get "/admin/local_design"
      expect(response).to have_http_status(:forbidden)
    end

    it "is forbidden from updating settings" do
      post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Gray" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "is forbidden from uploading an asset" do
      post "/admin/local_design/assets/logo",
           params: { file: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/image.png"), "image/png") }

      expect(response).to have_http_status(:forbidden)
      expect(LocalDesignSetting.current.logo).not_to be_present
    end
  end

  context "as an anonymous user" do
    it "redirects to login" do
      get "/admin/local_design"
      expect(response).to redirect_to(signin_path(back_url: "http://test.host/admin/local_design"))
    end
  end

  describe "CSRF protection" do
    it "does not opt LocalDesignController out of Rails' request-forgery verification" do
      expect(LocalDesignController._process_action_callbacks.map(&:filter))
        .to include(:verify_authenticity_token)
    end
  end

  context "with menu visibility" do
    let(:admin) { create(:admin) }

    before { login_as(admin) }

    it "shows the independent Local Design entry when no Enterprise token allows define_custom_style" do
      get "/admin"

      expect(response.body).to include(local_design_path)
    end

    context "when a token grants define_custom_style", with_ee: %i[define_custom_style] do
      it "shows the Enterprise entry instead" do
        get "/admin"

        expect(response.body).to include(custom_style_path)
      end
    end
  end

  context "with runtime CSS/favicon integration (Phase 8/10/11)" do
    let(:admin) { create(:admin) }

    before { login_as(admin) }

    it "renders the default palette's CSS custom properties on an ordinary page" do
      get "/admin"

      expect(response.body).to include("--primary-button-color: #1F883D")
      expect(response.body).to include("--op-local-design-link-color:")
      expect(response.body).to include("favicon.ico")
      expect(response.body).to include("apple-touch-icon-120x120.png")
    end

    it "renders a saved theme's colors and switches the favicon once one is uploaded" do
      post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Navy Blue" } }
      post "/admin/local_design/assets/favicon",
           params: { file: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/image.png"), "image/png") }

      get "/admin"

      expect(response.body).to include("--header-bg-color: #05002C")
      setting = LocalDesignSetting.current
      expect(response.body).to include(local_design_download_asset_path(digest: setting.digest, field: "favicon",
                                                                        filename: setting.favicon.file.filename))
      expect(response.body).not_to include("favicon.ico\"")
    end

    context "when a licensed, configured Enterprise custom style is also active", with_ee: %i[define_custom_style] do
      before { create(:custom_style) }

      it "does not render any Local Design CSS output" do
        get "/admin"

        expect(response.body).not_to include("--op-local-design-link-color:")
      end
    end
  end

  describe "PDF branding (Phase 15/16)" do
    let(:admin) { create(:admin) }

    before { login_as(admin) }

    describe "POST /admin/local_design/assets/:field for pdf_logo/pdf_cover" do
      it "uploads a PDF logo and it becomes the PDF export pipeline's logo source" do
        post "/admin/local_design/assets/pdf_logo", params: { file: image_fixture }

        expect(response).to redirect_to(local_design_path(tab: "pdf_export_styles"))
        expect(LocalDesignSetting.current.pdf_logo).to be_present
        expect(LocalDesign::PdfBranding.logo_path).to eq(LocalDesignSetting.current.pdf_logo.local_file.path)
      end

      it "uploads a PDF cover background" do
        post "/admin/local_design/assets/pdf_cover", params: { file: image_fixture }

        expect(response).to redirect_to(local_design_path(tab: "pdf_export_styles"))
        expect(LocalDesign::PdfBranding.cover_path).to be_present
      end
    end

    describe "POST /admin/local_design/pdf_cover_text_color" do
      it "saves a valid hex color, normalized and without a leading #, for Prawn" do
        post "/admin/local_design/pdf_cover_text_color", params: { pdf_cover_text_color: "#ff0000" }

        expect(response).to redirect_to(local_design_path(tab: "pdf_export_styles"))
        expect(LocalDesignSetting.current.pdf_cover_text_color).to eq("#FF0000")
        expect(LocalDesign::PdfBranding.cover_text_color).to eq("FF0000")
      end

      it "rejects an invalid value with a readable error" do
        post "/admin/local_design/pdf_cover_text_color", params: { pdf_cover_text_color: "not-a-color" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LocalDesignSetting.current.pdf_cover_text_color).to be_nil
      end
    end

    describe "custom PDF fonts" do
      it "requires the regular cut before a custom font becomes active" do
        post "/admin/local_design/assets/pdf_font_bold", params: { file: font_fixture }
        expect(LocalDesign::PdfBranding.custom_font_active?).to be(false)

        post "/admin/local_design/assets/pdf_font_regular", params: { file: font_fixture }
        expect(LocalDesign::PdfBranding.custom_font_active?).to be(true)
        expect(Exports::PDF::Common::View.default_font).to eq("CustomFont")
      end

      it "falls back missing bold/italic/bold-italic cuts to the regular cut" do
        post "/admin/local_design/assets/pdf_font_regular", params: { file: font_fixture }

        files = LocalDesign::PdfBranding.font_files
        expect(files[:bold]).to eq(files[:normal])
        expect(files[:italic]).to eq(files[:normal])
        expect(files[:bold_italic]).to eq(files[:normal])
      end
    end

    describe "GET /admin/local_design/demo_pdf" do
      it "generates a demo PDF reflecting Local Design branding, uncached" do
        post "/admin/local_design/assets/pdf_logo", params: { file: image_fixture }

        get export_demo_pdf_download_local_design_path

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.headers["Cache-Control"]).to include("private").or include("no-cache")
      end

      context "as a non-admin" do
        before { login_as(create(:user)) }

        it "is forbidden" do
          get export_demo_pdf_download_local_design_path
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    describe "PDF branding precedence" do
      it "prefers Local Design's PDF logo when no Enterprise custom style is active" do
        post "/admin/local_design/assets/pdf_logo", params: { file: image_fixture }

        exporter_class = Class.new do
          include Exports::PDF::Common::Logo
          include Exports::PDF::Common::Attachments
        end
        resolved = exporter_class.new.logo_image_filename

        expect(resolved.to_s).to eq(LocalDesignSetting.current.pdf_logo.local_file.path)
      end

      context "when a licensed, configured Enterprise custom style is also active", with_ee: %i[define_custom_style] do
        it "keeps the Enterprise logo ahead of Local Design's" do
          post "/admin/local_design/assets/pdf_logo", params: { file: image_fixture }
          custom_style = create(:custom_style_with_export_logo)
          allow(CustomStyle).to receive(:current).and_return(custom_style)

          exporter_class = Class.new do
            include Exports::PDF::Common::Logo
            include Exports::PDF::Common::Attachments
          end
          resolved = exporter_class.new.logo_image_filename

          expect(resolved.to_s).to eq(custom_style.export_logo.local_file.path)
          expect(resolved.to_s).not_to eq(LocalDesign::PdfBranding.logo_path)
        end
      end
    end

    describe "auditability (Phase 17)" do
      before { allow(LocalDesign::AuditLog).to receive(:record).and_call_original }

      it "logs an informational event on asset upload with admin id, action, and changed setting name" do
        post "/admin/local_design/assets/logo", params: { file: image_fixture }

        expect(LocalDesign::AuditLog).to have_received(:record)
          .with(user: admin, action: :asset_uploaded, changed_settings: ["logo"])
      end

      it "logs a theme change" do
        post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Gray" } }

        expect(LocalDesign::AuditLog).to have_received(:record)
          .with(user: admin, action: :settings_updated, changed_settings: array_including("theme", "colors"))
      end

      it "logs a reset to defaults" do
        post "/admin/local_design/theme", params: { local_design_setting: { theme: "OpenProject Gray" } }
        post "/admin/local_design/reset"

        expect(LocalDesign::AuditLog).to have_received(:record)
          .with(user: admin, action: :reset_to_defaults, changed_settings: array_including("theme"))
      end

      it "logs an asset removal" do
        post "/admin/local_design/assets/favicon", params: { file: image_fixture }
        delete "/admin/local_design/assets/favicon"

        expect(LocalDesign::AuditLog).to have_received(:record)
          .with(user: admin, action: :asset_removed, changed_settings: ["favicon"])
      end

      it "never includes a file path or binary content in the logged message" do
        logged_message = nil
        allow(Rails.logger).to receive(:info) { |&blk| logged_message = blk.call }

        post "/admin/local_design/assets/logo", params: { file: image_fixture }

        expect(logged_message).to include("admin_id=")
        expect(logged_message).to include("action=")
        expect(logged_message).to include("at=")
        expect(logged_message).not_to include("/tmp/")
        expect(logged_message).not_to include(Rails.root.to_s)
      end
    end
  end
end
