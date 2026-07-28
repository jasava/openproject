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

# A single work-package card on the Team Schedule grid.
#
# Unlike the old project-scoped TeamSchedules::CardComponent, there is no
# `project:` constructor argument — the work package's own `.project`
# (already eager-loaded by GlobalTeamPlanner::QueryBuilder's `base_scope`,
# see its `includes`) is the only source of project context, since a global
# planner row can hold cards from several different projects at once (see
# feature/04_team_planner_rework.md, "Cross-project work-package cards").
module GlobalTeamPlanner
  class CardComponent < ApplicationComponent
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    def initialize(work_package:, view:, grid_style: nil, editable: true)
      super

      @work_package = work_package
      @view = view
      @grid_style = grid_style
      @editable = editable
    end

    def wrapper_key
      "global-team-planner-card-#{@work_package.id}"
    end

    delegate :start_date, to: :@work_package

    delegate :due_date, to: :@work_package

    # Only leaf work packages and manually-scheduled ones accept a direct
    # date write (see WorkPackages::BaseContract#leaf_or_manually_scheduled?)
    # — a parent whose dates are derived from its children cannot be dragged
    # or resized directly, matching how the work-package details view treats
    # those fields as read-only for the same work package.
    def draggable?
      @editable && (@work_package.leaf? || @work_package.schedule_manually?) && editable_dates?
    end

    # Project-aware already: WorkPackages::UpdateContract.update_allowed?
    # checks edit permissions against the work package's own project
    # internally, so a card from a project the current user can only view
    # (not edit) correctly renders read-only here even though the same user
    # can freely edit other projects' cards on the same grid — see
    # feature/04_team_planner_rework.md, "Per-project permissions still
    # apply".
    def editable_dates?
      WorkPackages::UpdateContract.update_allowed?(user: User.current, work_package: @work_package)
    end

    def milestone?
      start_date.present? && start_date == due_date
    end

    def status_name
      @work_package.status&.name
    end

    delegate :project, to: :@work_package

    # Compact project context shown directly on the card (identifier is
    # stable and short, unlike project name, which can be long) — see
    # "Cross-project work-package cards": "The project should be visually
    # recognizable without making the card too crowded."
    def project_label
      project&.identifier
    end

    # Full project name, shown as a Primer::Alpha::Tooltip on the compact
    # badge — attached via `for_id` rather than a native `title` attribute,
    # matching the established pattern for icon/badge tooltips elsewhere in
    # the codebase (see Resources::Allocations::ListItemComponent's
    # overbooked-icon tooltip). `title` attributes are flagged by
    # erblint-github's accessibility rules and are not reliably exposed to
    # screen readers or keyboard users.
    def project_tooltip_text
      I18n.t("global_team_planner.card.project_tooltip", name: project&.name)
    end

    def project_badge_id
      "#{wrapper_key}-project"
    end

    # "#123 Subject" rather than just "Subject": per "Cross-project
    # work-package cards", "Do not assume work-package IDs alone are
    # sufficient project context" — implying the ID is expected to already
    # be visible on the card, with the project badge/tooltip added on top of
    # it, not instead of it.
    def subject_label
      "##{@work_package.id} #{@work_package.subject}"
    end

    def accessible_label
      I18n.t("global_team_planner.card.aria_label",
             id: @work_package.id,
             subject: @work_package.subject,
             assignee: assignee_name,
             start_date: formatted_date(start_date),
             due_date: formatted_date(due_date),
             status: status_name,
             project: project&.name)
    end

    def split_view_href
      # `tab` must be present, not just default-able: WorkPackages::SplitViewHelper
      # forwards `params[:tab]` verbatim into WorkPackages::Details::TabComponent,
      # which calls `.to_sym` on it unconditionally — a missing tab param becomes
      # `nil.to_sym` instead of falling back to the component's own `:overview`
      # default.
      split_view_params = { work_package_split_view: 1, work_package_id: @work_package.id, tab: "overview" }

      if @view.persisted?
        helpers.global_team_planner_view_path(@view, **split_view_params)
      else
        helpers.global_team_planner_path(**split_view_params)
      end
    end

    # The drag/resize PATCH target. Deliberately keyed only by
    # `work_package_id` — no view/schedule id at all, unlike the old
    # project-scoped nested route (`card_project_team_schedule_path`) — see
    # feature/04_team_planner_rework.md, "Route structure".
    def card_url
      helpers.schedule_global_team_planner_work_package_path(@work_package.id)
    end

    private

    def assignee_name
      @work_package.assigned_to&.name || I18n.t("global_team_planner.card.no_assignee")
    end

    def formatted_date(date)
      date ? helpers.format_date(date) : I18n.t("global_team_planner.grid.no_dates")
    end
  end
end
