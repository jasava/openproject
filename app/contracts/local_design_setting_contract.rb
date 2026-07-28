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

# Validates theme/color/asset updates to the singleton LocalDesignSetting.
#
# Deliberately not namespaced under `LocalDesign::` (unlike the services) —
# the task's naming spec calls this out explicitly as a top-level
# `LocalDesignSettingContract`, one level above the `LocalDesign::` service
# namespace, and its own model-attribute validations already live on
# `LocalDesignSetting` (the AR model), so this contract's job is narrower
# than the model's: authorization plus "is this the shape of update we
# accept", not full re-validation of every possible model field.
#
# Every column is declared writable here (not just theme/colors): this
# contract is the single authorization gate for the whole singleton — there
# is no per-field permission distinction on an admin-only settings row — and
# `ModelContract#readonly_attributes_unchanged` raises `error_readonly` for
# any *changed* attribute not declared here. `UploadAssetService`/
# `DeleteAssetService` save directly and never hit that check, but
# `ResetService`'s `remove_assets: true` path clears the same asset columns
# through this contract (`Contracted#validate_and_save`), so they must be
# declared writable or every reset-with-assets call fails.
class LocalDesignSettingContract < ModelContract
  def self.model
    LocalDesignSetting
  end

  attribute :theme
  attribute :colors
  (LocalDesignSetting::IMAGE_FIELDS + LocalDesignSetting::FONT_FIELDS).each { |field| attribute field }
  attribute :pdf_cover_text_color

  validate :user_must_be_admin

  private

  # Every write to this singleton is an instance-administration action —
  # there is no "owner" concept the way there is for e.g. TeamSchedule, so
  # this is a flat admin-only check. The controller also enforces
  # `require_admin` (Phase 2's explicit server-side requirement); this is
  # the defense-in-depth layer that holds even if the contract is invoked
  # directly (console, a future non-controller caller, tests).
  def user_must_be_admin
    errors.add :base, :error_unauthorized unless user&.admin?
  end
end
