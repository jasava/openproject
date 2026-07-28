# frozen_string_literal: true

#-- copyright
# OpenProject Community Team Planner
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

# A saved Team Schedule view: STI record on the core `persisted_views` table
# (see docs/community-team-planner/data-model.md for why this reuses
# PersistedView instead of introducing new tables). A schedule never stores
# work-package data itself — cards are always resolved live from `effective_query`.
class TeamSchedule < PersistedView
  DISPLAY_MODES = %w[work_week one_week two_weeks four_weeks].freeze
  MAX_ASSIGNEES = 30

  store_attribute :options, :display_mode, :string, default: "one_week"
  store_attribute :options, :anchor_date,  :date
  store_attribute :options, :assignee_ids, :json, default: []

  validates :display_mode, inclusion: { in: DISPLAY_MODES }
  validates :project, presence: true
  validates :parent, absence: true

  validate :assignee_ids_must_be_integers
  validate :assignee_ids_within_limit
  validate :query_must_be_work_package_query

  after_initialize :set_defaults, if: :new_record?

  def visible?(user)
    return false if project.nil?
    return false unless user.allowed_in_project?(:view_community_team_planner, project)

    public? || principal == user
  end

  # Manage rights follow visibility: a private schedule is only manageable by
  # its own owner (it is not even visible to anyone else), a public schedule
  # is manageable by anyone in the project holding the manage permission.
  def manageable?(user)
    visible?(user) && user.allowed_in_project?(:manage_community_team_planner, project)
  end

  def build_default_query
    ::Query.new_default(project:, user: principal)
  end

  # Ordered, de-duplicated `User`/`Group`/`PlaceholderUser` rows for this
  # schedule, in the persisted row order. Missing/no-longer-visible principals
  # (e.g. removed from the project) are silently dropped rather than erroring,
  # since row membership is informational only.
  def rows
    return [] if assignee_ids.blank?

    scope = Principal.in_project(project).where(id: assignee_ids)
    scope.in_order_of(:id, assignee_ids.map(&:to_i)).to_a
  end

  def add_row(principal_id)
    principal_id = principal_id.to_i
    return if assignee_ids.map(&:to_i).include?(principal_id)

    self.assignee_ids = assignee_ids.map(&:to_i) + [principal_id]
  end

  def remove_row(principal_id)
    self.assignee_ids = assignee_ids.map(&:to_i) - [principal_id.to_i]
  end

  def reorder_rows(ordered_ids)
    current = assignee_ids.map(&:to_i)
    ordered_ids = ordered_ids.map(&:to_i) & current
    self.assignee_ids = ordered_ids | current
  end

  # Reuses the same work-package query/filter infrastructure as the rest of
  # OpenProject (Phase 11) rather than a bespoke filter language: `filters_json`
  # is the same APIv3 filter payload shape `Filters::FilterFormComponent`
  # already produces, parsed with the same parser the core work-package
  # table's filter form uses.
  def apply_filters(filters_json)
    return if effective_query.nil?

    effective_query.filters.clear
    ::Queries::ParamsParser::APIV3FiltersParser.parse(filters_json).each do |filter|
      effective_query.add_filter(filter[:attribute], filter[:operator], filter[:values])
    end
  rescue JSON::ParserError
    nil
  end

  private

  def set_defaults
    self.anchor_date ||= Date.current
    self.principal ||= User.current
  end

  def assignee_ids_must_be_integers
    return if assignee_ids.blank?
    return if assignee_ids.all? { |id| id.to_s.match?(/\A\d+\z/) }

    errors.add(:assignee_ids, :invalid)
  end

  def assignee_ids_within_limit
    return if assignee_ids.blank?

    errors.add(:assignee_ids, :too_many, count: MAX_ASSIGNEES) if assignee_ids.size > MAX_ASSIGNEES
  end

  def query_must_be_work_package_query
    resolved = effective_query
    return if resolved.nil? || resolved.is_a?(::Query)

    errors.add(:query, :invalid)
  end
end
