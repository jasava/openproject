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

# A single row of the Team Schedule *views* index (the list of saved,
# global planner views) — not to be confused with a schedule row inside the
# grid itself (see GlobalTeamPlanner::GridComponent). Unlike the old
# project-scoped TeamSchedules::RowComponent, there is no project to
# delegate to or build links against: `GlobalTeamPlannerView` has no
# `project` of its own (see the model's class comment), so every path here
# is the plain, non-project-nested `global_team_planner_view*` route.
module GlobalTeamPlannerViews
  class RowComponent < ::OpPrimer::BorderBoxRowComponent
    def name
      icon = if model.favorited_by?(User.current)
               render(Primer::Beta::Octicon.new(
                        icon: :"star-fill",
                        "aria-label": I18n.t(:label_favorite),
                        classes: "op-primer--star-icon",
                        mr: 2
                      ))
             end

      link = render(Primer::Beta::Link.new(
                      href: global_team_planner_view_path(model),
                      font_weight: :bold
                    )) { model.name }

      safe_join([icon, link].compact)
    end

    def members
      model.assignee_ids.size
    end

    def updated_at
      helpers.format_time(model.updated_at)
    end

    def button_links
      [action_menu]
    end

    def action_menu
      render(Primer::Alpha::ActionMenu.new) do |menu|
        menu.with_show_button(icon: "kebab-horizontal",
                              "aria-label": t(:label_more),
                              scheme: :invisible)

        favorite_item(menu)
        toggle_public_item(menu) if manage_allowed?
        delete_item(menu) if manage_allowed?
      end
    end

    def favorite_item(menu)
      favorited = model.favorited_by?(User.current)
      label = favorited ? t("global_team_planner.action.unfavorite") : t("global_team_planner.action.favorite")
      icon = favorited ? :star : :"star-fill"
      method = favorited ? :delete : :post

      menu.with_item(
        label:,
        href: favorite_path(object_type: "persisted_views", object_id: model.id),
        content_arguments: { data: { turbo_method: method } }
      ) do |item|
        item.with_leading_visual_icon(icon:)
      end
    end

    def toggle_public_item(menu)
      label = model.public? ? t("global_team_planner.action.make_private") : t("global_team_planner.action.make_public")
      icon = model.public? ? :lock : :globe

      menu.with_item(
        label:,
        href: toggle_public_global_team_planner_view_path(model),
        content_arguments: { data: { turbo_method: :post } }
      ) do |item|
        item.with_leading_visual_icon(icon:)
      end
    end

    def delete_item(menu)
      menu.with_item(
        label: t("global_team_planner.action.delete"),
        scheme: :danger,
        href: global_team_planner_view_path(model),
        content_arguments: {
          data: {
            turbo_method: :delete,
            turbo_confirm: t(:text_are_you_sure)
          }
        }
      ) do |item|
        item.with_leading_visual_icon(icon: :trash)
      end
    end

    # `GlobalTeamPlannerView#manageable?` is deliberately owner-only (see
    # the model's class comment) — no per-project "manage" permission to
    # branch on here, unlike the old TeamSchedule#manageable?.
    def manage_allowed?
      model.manageable?(User.current)
    end
  end
end
