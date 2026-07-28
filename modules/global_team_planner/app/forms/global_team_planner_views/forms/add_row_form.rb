# frozen_string_literal: true

module GlobalTeamPlannerViews
  module Forms
    # Unlike the old TeamSchedules::Forms::AddRowForm, this does not drive a
    # `Primer::Forms` `autocompleter` field against the (Angular-based)
    # `opce-user-autocompleter` custom element — this module is
    # Hotwire/Stimulus-only, no Angular. Instead this just declares the two
    # plain inputs a lightweight Stimulus picker needs: a free-text search
    # box and a hidden field that actually carries the selected principal id
    # on submit. The picker itself (live search against
    # `global_team_planner_principal_candidates_path`, already scoped to
    # `view.effective_project_ids(current_user)` by the caller — see
    # GlobalTeamPlanner::AddRowDialogComponent) is wired up in the
    # surrounding dialog template, matching how
    # frontend/src/stimulus/controllers/dynamic/global-team-planner/project-picker.controller.ts
    # is wired to GlobalTeamPlannerViews::Forms::ProjectScopeForm.
    #
    # Both fields render under the surrounding form's `scope: :row`, so they
    # submit as `row[principal_search]`/`row[principal_id]` — matching what
    # GlobalTeamPlannerController#new_row_principal_id reads.
    class AddRowForm < ApplicationForm
      form do |f|
        f.text_field(
          name: :principal_search,
          value: "",
          label: GlobalTeamPlannerView.human_attribute_name(:assignee_ids),
          required: false,
          autofocus: true,
          autocomplete: "off",
          placeholder: I18n.t("global_team_planner.grid.add_row_placeholder"),
          data: {
            "global-team-planner--principal-picker-target": "search",
            action: "input->global-team-planner--principal-picker#search"
          }
        )

        f.hidden(
          name: :principal_id,
          value: "",
          data: { "global-team-planner--principal-picker-target": "value" }
        )
      end
    end
  end
end
