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

// Minimal multi-project picker backing GlobalTeamPlannerViews::Forms::ProjectScopeForm
// (project_scope_mode "selected"). Deliberately plain fetch + DOM
// manipulation rather than the Angular `ProjectAutocompleterComponent` this
// module has no dependency on — see
// modules/global_team_planner/app/forms/global_team_planner_views/forms/project_scope_form.html.erb.
//
// The candidates endpoint (`candidatesUrlValue`, i.e.
// `global_team_planner_project_candidates_path`) already applies
// `Project.visible(current_user)` server-side, so every candidate this
// controller can ever render or add is already authorization-filtered — see
// feature/04_team_planner_rework.md, "Project scope selector": "avoid
// exposing unauthorized project names through autocomplete results".
//
// The actual submitted value lives entirely in the (hidden) `select`
// target's `<option>`s — this controller only ever adds/removes `<option>`
// elements there; `chips`/`results` are pure display, regenerated from the
// select's current options.
interface ProjectCandidate {
  id:number;
  identifier:string;
  name:string;
}

export default class ProjectPickerController extends Controller {
  static targets = ['search', 'results', 'chips', 'select'];

  static values = {
    candidatesUrl: String,
    noResultsMessage: String,
    removeLabel: String,
  };

  declare readonly searchTarget:HTMLInputElement;
  declare readonly resultsTarget:HTMLElement;
  declare readonly chipsTarget:HTMLElement;
  declare readonly selectTarget:HTMLSelectElement;
  declare readonly candidatesUrlValue:string;
  declare readonly noResultsMessageValue:string;
  declare readonly removeLabelValue:string;

  private debounceTimeout:number|undefined;
  private requestId = 0;

  connect() {
    this.renderChips();
  }

  disconnect() {
    window.clearTimeout(this.debounceTimeout);
  }

  search() {
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

    const url = `${this.candidatesUrlValue}?q=${encodeURIComponent(query)}`;
    const response = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!response.ok || currentRequest !== this.requestId) return;

    const candidates = await response.json() as ProjectCandidate[];
    this.renderResults(candidates);
  }

  private renderResults(candidates:ProjectCandidate[]) {
    this.resultsTarget.replaceChildren();

    const selectedIds = this.selectedIds();
    const available = candidates.filter((candidate) => !selectedIds.includes(candidate.id));

    if (available.length === 0) {
      const empty = document.createElement('li');
      empty.classList.add('op-global-team-planner--project-picker-empty');
      empty.textContent = this.noResultsMessageValue;
      this.resultsTarget.append(empty);
      return;
    }

    available.forEach((candidate) => {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = `${candidate.identifier} ${candidate.name}`;
      button.addEventListener('click', () => this.addProject(candidate));
      item.append(button);
      this.resultsTarget.append(item);
    });
  }

  private addProject(candidate:ProjectCandidate) {
    if (this.selectedIds().includes(candidate.id)) return;

    const option = document.createElement('option');
    option.value = String(candidate.id);
    option.selected = true;
    option.dataset.identifier = candidate.identifier;
    option.dataset.name = candidate.name;
    option.textContent = `${candidate.identifier} ${candidate.name}`;
    this.selectTarget.append(option);

    this.searchTarget.value = '';
    this.resultsTarget.replaceChildren();
    this.renderChips();
  }

  private removeProject(id:string) {
    Array.from(this.selectTarget.options)
      .find((option) => option.value === id)
      ?.remove();

    this.renderChips();
  }

  private renderChips() {
    this.chipsTarget.replaceChildren();

    Array.from(this.selectTarget.options).forEach((option) => {
      const chip = document.createElement('span');
      chip.classList.add('op-global-team-planner--project-picker-chip');
      chip.textContent = `${option.dataset.identifier ?? ''} ${option.dataset.name ?? option.textContent ?? ''}`.trim();

      const remove = document.createElement('button');
      remove.type = 'button';
      remove.setAttribute('aria-label', this.removeLabelValue);
      remove.textContent = '×';
      remove.addEventListener('click', () => this.removeProject(option.value));

      chip.append(remove);
      this.chipsTarget.append(chip);
    });
  }

  private selectedIds():number[] {
    return Array.from(this.selectTarget.options).map((option) => Number(option.value));
  }
}
