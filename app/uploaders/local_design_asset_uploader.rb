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

# Image asset uploader (logos, favicon, touch icon, PDF logo/cover/footer).
#
# Subclasses whatever uploader OpenProject is configured to use for local
# filesystem or object-storage deployments (`OpenProject::Configuration
# .file_uploader`, the same base class `CustomStyle` and `Attachment` mount)
# so storage backend selection keeps working unmodified. Adds allowlist
# validation CustomStyle's own uploads do not currently have (Phase 12) —
# extension + declared-content-type allowlisting at the CarrierWave layer,
# on top of the byte-level decode check performed before this uploader ever
# sees the file (LocalDesign::UploadAssetService, using MiniMagick — see
# that service for why the decode check happens separately/earlier).
class LocalDesignAssetUploader < OpenProject::Configuration.file_uploader
  IMAGE_EXTENSIONS = %w[png jpg jpeg gif webp].freeze
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  # SVG is deliberately excluded: it is an XML format that can carry
  # embedded scripts/external references, and this repository has no
  # existing SVG sanitization pipeline to reuse (confirmed during Phase 0
  # analysis) — Phase 12 explicitly forbids allowing SVG without one.
  def extension_allowlist
    IMAGE_EXTENSIONS
  end

  def content_type_allowlist
    IMAGE_CONTENT_TYPES
  end

  def size_range
    (1.byte)..(5.megabytes)
  end
end
