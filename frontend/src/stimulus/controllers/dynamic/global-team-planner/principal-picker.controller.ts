/*
 * -- copyright
 * OpenProject Global Team Planner
 * Copyright (C) the OpenProject community
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 * ++
 */

import { Controller } from '@hotwired/stimulus';

// Single-principal picker backing GlobalTeamPlannerViews::Forms::AddRowForm
// ("Add row" dialog). The old project-scoped version used the Angular
// `opce-user-autocompleter` custom element; this module is
// Hotwire/Stimulus-only, so this is a small hand-rolled replacement
// following the same plain fetch + DOM manipulation approach as the sibling
// project-picker controller.
//
// `candidatesUrlValue` is `global_team_planner_principal_candidates_path`,
// which is always called here with `projectIdsValue` (the *view's* current
// `effective_project_ids(current_user)`, computed server-side by
// GlobalTeamPlanner::AddRowDialogComponent) — never omitted — because the
// endpoint falls back to "all visible projects" when no project_ids[] are
// given at all, which would be broader than the row picker is supposed to
// offer (see feature/04_team_planner_rework.md, "Team rows": search across
// members of authorized *selected* projects, not everyone the user could
// ever see).
//
// `existingIdsValue` (rows already on the view) is filtered out client-side
// so the same principal cannot be picked twice — the candidates endpoint
// itself has no notion of "existing rows", only project membership.
interface PrincipalCandidate {
  id:number;
  name:string;
}

export default class PrincipalPickerController extends Controller {
  static targets = ['search', 'results', 'value', 'selected'];

  static values = {
    candidatesUrl: String,
    projectIds: Array,
    existingIds: Array,
    noResultsMessage: String,
    removeLabel: String,
  };

  declare readonly searchTarget:HTMLInputElement;
  declare readonly resultsTarget:HTMLElement;
  declare readonly valueTarget:HTMLInputElement;
  declare readonly selectedTarget:HTMLElement;
  declare readonly candidatesUrlValue:string;
  declare readonly projectIdsValue:number[];
  declare readonly existingIdsValue:number[];
  declare readonly noResultsMessageValue:string;
  declare readonly removeLabelValue:string;

  private debounceTimeout:number|undefined;
  private requestId = 0;

  disconnect() {
    window.clearTimeout(this.debounceTimeout);
  }

  search() {
    // A fresh search always invalidates a previous pick.
    this.valueTarget.value = '';
    this.selectedTarget.replaceChildren();

    window.clearTimeout(this.debounceTimeout);
    this.debounceTimeout = window.setTimeout(() => { void this.fetchCandidates(); }, 250);
  }

  private async fetchCandidates() {
    const query = this.searchTarget.value.trim();
    this.requestId += 1;
    const currentRequest = this.requestId;

    if (!query) {
      this.resultsTarget.replaceChildren();
      return;
    }

    const url = new URL(this.candidatesUrlValue, window.location.origin);
    url.searchParams.set('q', query);
    this.projectIdsValue.forEach((id) => url.searchParams.append('project_ids[]', String(id)));

    const response = await fetch(url.toString(), { headers: { Accept: 'application/json' } });
    if (!response.ok || currentRequest !== this.requestId) return;

    const candidates = await response.json() as PrincipalCandidate[];
    this.renderResults(candidates.filter((candidate) => !this.existingIdsValue.includes(candidate.id)));
  }

  private renderResults(candidates:PrincipalCandidate[]) {
    this.resultsTarget.replaceChildren();

    if (candidates.length === 0) {
      const empty = document.createElement('li');
      empty.classList.add('op-global-team-planner--principal-picker-empty');
      empty.textContent = this.noResultsMessageValue;
      this.resultsTarget.append(empty);
      return;
    }

    candidates.forEach((candidate) => {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = candidate.name;
      button.addEventListener('click', () => this.select(candidate));
      item.append(button);
      this.resultsTarget.append(item);
    });
  }

  private select(candidate:PrincipalCandidate) {
    this.valueTarget.value = String(candidate.id);
    this.searchTarget.value = candidate.name;
    this.resultsTarget.replaceChildren();
    this.renderSelected(candidate);
  }

  clear() {
    this.valueTarget.value = '';
    this.searchTarget.value = '';
    this.selectedTarget.replaceChildren();
    this.searchTarget.focus();
  }

  private renderSelected(candidate:PrincipalCandidate) {
    this.selectedTarget.replaceChildren();

    const chip = document.createElement('span');
    chip.classList.add('op-global-team-planner--principal-picker-chip');
    chip.textContent = candidate.name;

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.setAttribute('aria-label', this.removeLabelValue);
    remove.textContent = '×';
    remove.addEventListener('click', () => this.clear());

    chip.append(remove);
    this.selectedTarget.append(chip);
  }
}
