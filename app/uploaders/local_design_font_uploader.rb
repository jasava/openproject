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

# PDF export font uploader (regular/bold/italic/bold-italic TTF variants).
#
# Same storage-backend inheritance as LocalDesignAssetUploader. The actual
# "is this really a TTF" structural check happens before this uploader
# stores anything (LocalDesign::UploadAssetService, via TTFunk — the same
# gem and approach CustomStylesControllerHelper#valid_ttf? already uses);
# this class only enforces the cheap extension/size checks.
class LocalDesignFontUploader < OpenProject::Configuration.file_uploader
  FONT_EXTENSIONS = %w[ttf].freeze

  # Matches CustomStylesControllerHelper::MAX_FONT_UPLOAD_SIZE — not
  # reinventing a different limit for the same kind of upload.
  MAX_FONT_UPLOAD_SIZE = 30.megabytes

  def extension_allowlist
    FONT_EXTENSIONS
  end

  def size_range
    (1.byte)..MAX_FONT_UPLOAD_SIZE
  end
end
