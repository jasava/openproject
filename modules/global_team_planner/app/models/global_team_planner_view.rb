# frozen_string_literal: true

#-- copyright
# OpenProject Global Team Planner
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

# A saved, GLOBAL Team Schedule view: STI record on the core `persisted_views`
# table (see docs/global-team-planner/data-model.md). Unlike the project-scoped
# `TeamSchedule` this replaces, `project_id` is always nil here — the set of
# projects a view covers is stored as data (`selected_project_ids`), not as a
# foreign key, and is re-intersected with the *current viewer's* authorized
# project scope every time the view is opened (never trusted as authorization
# — see #effective_project_ids and GlobalTeamPlanner::QueryBuilder).
#
# A schedule never stores work-package data itself — cards are always
# resolved live from `effective_query` (see GlobalTeamPlanner::QueryBuilder).
class GlobalTeamPlannerView < PersistedView
  DISPLAY_MODES = %w[work_week one_week two_weeks four_weeks].freeze
  PROJECT_SCOPE_MODES = %w[all_visible selected my_projects].freeze
  MAX_ASSIGNEES = 30
  MAX_SELECTED_PROJECTS = 200

  store_attribute :options, :display_mode, :string, default: "one_week"
  store_attribute :options, :anchor_date,            :date
  store_attribute :options, :assignee_ids,           :json,    default: []
  store_attribute :options, :project_scope_mode,     :string,  default: "all_visible"
  store_attribute :options, :selected_project_ids,   :json,    default: []
  store_attribute :options, :show_unassigned,        :boolean, default: false
  store_attribute :options, :group_by_project,       :boolean, default: false

  validates :display_mode, inclusion: { in: DISPLAY_MODES }
  validates :project_scope_mode, inclusion: { in: PROJECT_SCOPE_MODES }
  validates :parent, absence: true
  validates :project, absence: true

  validate :assignee_ids_must_be_integers
  validate :assignee_ids_within_limit
  validate :selected_project_ids_must_be_integers
  validate :selected_project_ids_within_limit
  validate :query_must_be_work_package_query

  after_initialize :set_defaults, if: :new_record?

  # No project-membership check here (there is no single project to check):
  # anyone who can reach Team Schedule at all (see
  # GlobalTeamPlannerController#require_view_access!) may see any *public*
  # view's configuration, and the view's own content is always recalculated
  # against that viewer's authorized projects/work packages when opened — see
  # the class comment and GlobalTeamPlanner::QueryBuilder. Seeing a shared
  # view's name/filters is not the same as seeing its data.
  def visible?(user)
    public? || principal == user
  end

  # Deliberately owner-only, unlike the old project-scoped TeamSchedule
  # (which let anyone holding a project "manage" permission edit a public
  # schedule). A global view has no single project whose permission could
  # govern that, and defaulting to "only the owner may change a shared view's
  # configuration" is the safe MVP choice — see
  # docs/global-team-planner/permissions.md.
  def manageable?(user)
    principal == user
  end

  def build_default_query
    ::Query.new_default(project: nil, user: principal)
  end

  # Ordered, de-duplicated `User`/`Group`/`PlaceholderUser` rows for this
  # view, in the persisted row order. Missing/no-longer-existing principals
  # are silently dropped rather than erroring — row membership is
  # informational only, and (unlike the old project-scoped version) there is
  # no single project to scope `Principal.in_project` against here; per-row
  # relevance to the *current* authorized scope is handled by the grid
  # renderer, not by this method.
  def rows
    return [] if assignee_ids.blank?

    Principal.where(id: assignee_ids).in_order_of(:id, assignee_ids.map(&:to_i)).to_a
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

  # The projects this view is configured to cover, **re-intersected with the
  # given user's currently-visible projects** — never the persisted IDs
  # alone. This is what a shared view opened by a different user actually
  # resolves to; it is not authorization by itself (the query builder applies
  # `.visible` independently at the work-package level too), but it is what
  # the project-scope-selector UI and empty-state detection display.
  def effective_project_ids(user)
    case project_scope_mode
    when "selected"
      Project.visible(user).where(id: selected_project_ids).pluck(:id)
    when "my_projects"
      Project.visible(user).where(id: user.memberships.select(:project_id)).pluck(:id)
    else # "all_visible"
      Project.visible(user).pluck(:id)
    end
  end

  # Reuses the same work-package query/filter infrastructure as the rest of
  # OpenProject rather than a bespoke filter language: `filters_json` is the
  # same APIv3 filter payload shape `Filters::FilterFormComponent` already
  # produces, parsed with the same parser the core work-package table's
  # filter form uses.
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

  def selected_project_ids_must_be_integers
    return if selected_project_ids.blank?
    return if selected_project_ids.all? { |id| id.to_s.match?(/\A\d+\z/) }

    errors.add(:selected_project_ids, :invalid)
  end

  def selected_project_ids_within_limit
    return if selected_project_ids.blank?

    if selected_project_ids.size > MAX_SELECTED_PROJECTS
      errors.add(:selected_project_ids, :too_many, count: MAX_SELECTED_PROJECTS)
    end
  end

  def query_must_be_work_package_query
    resolved = effective_query
    return if resolved.nil? || resolved.is_a?(::Query)

    errors.add(:query, :invalid)
  end
end
