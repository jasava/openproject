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

# Phase 17 (auditability). This codebase has no generic administrator
# audit-trail model to hook into — `has_paper_trail` is used only on
# content models (Project, WorkPackage, Attachment, Principal) for
# versioning/journaling, not for admin-settings change logging — so, per
# the task's own "where practical" / "at minimum, log an informational
# server event" fallback, this is a plain structured `Rails.logger.info`
# call, matching the existing convention in e.g.
# `Users::ChangePasswordService#log_success` (`Rails.logger.info { "..." }`
# with a lazily-built message).
#
# Deliberately logs only attribute *names* that changed (`"logo"`,
# `"theme"`, `"colors"`, ...), sourced from `model.saved_changes.keys` —
# never a file path, never binary/image content, never a color hex value —
# satisfying "do not write image contents or sensitive binary data into
# logs" and "do not log raw uploaded file paths from temporary
# directories."
module LocalDesign
  module AuditLog
    def self.record(user:, action:, changed_settings: [])
      Rails.logger.info do
        "[LocalDesign] admin_id=#{user&.id.inspect} action=#{action} " \
          "changed_settings=#{Array(changed_settings).join(',').inspect} " \
          "at=#{Time.current.iso8601}"
      end
    end
  end
end
