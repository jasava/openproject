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
import { FetchRequest } from '@rails/request.js';

// Drags a Team Schedule card horizontally (reschedule), vertically (reassign),
// or both at once, and resizes it from either edge. There is no existing
// drag-and-drop component in this codebase suited to free 2-axis positioning
// with resize (the shared `generic-drag-and-drop` controller wraps dragula,
// which only reorders/reparents DOM nodes), so this is a small,
// purpose-built pointer-events controller instead.
//
// The grid's day cells (see grid_component.html.erb) each carry the real
// calendar date and assignee id they represent as data attributes. Rather
// than computing dates from pixel deltas and column widths, every drag/resize
// resolves the day cell under the pointer via `elementFromPoint` and reads
// its date/assignee directly — immune to column-width rounding drift, and
// correct even where `work_week` mode skips non-working-day columns.
//
// The submit URL itself (`urlValue`) carries no view/schedule id at all —
// see GlobalTeamPlanner::CardsController's class comment — so `view_id` is
// read off the grid surface (if the grid was opened as a saved view) and
// sent as a plain body field alongside `anchor`/`mode`, purely so the
// re-rendered card the server sends back links to the right saved view.
export default class CardController extends Controller {
  static values = {
    url: String,
    startDate: String,
    dueDate: String,
  };

  declare readonly urlValue:string;
  declare readonly startDateValue:string;
  declare readonly dueDateValue:string;

  private startHandle:HTMLElement|null = null;
  private endHandle:HTMLElement|null = null;

  private dragging = false;
  private moved = false;
  private originCell:HTMLElement|null = null;
  private lastTargetCell:HTMLElement|null = null;
  private originColumnStart = 0;
  private originColumnEnd = 0;
  private originRow = 0;
  private mode:'move'|'resize-start'|'resize-end'|null = null;

  connect() {
    this.startHandle = this.element.querySelector('[data-global-team-planner--card-target="startHandle"]');
    this.endHandle = this.element.querySelector('[data-global-team-planner--card-target="endHandle"]');

    this.element.addEventListener('pointerdown', this.onCardPointerDown);
    this.startHandle?.addEventListener('pointerdown', this.onStartHandlePointerDown);
    this.endHandle?.addEventListener('pointerdown', this.onEndHandlePointerDown);
  }

  disconnect() {
    this.element.removeEventListener('pointerdown', this.onCardPointerDown);
    this.startHandle?.removeEventListener('pointerdown', this.onStartHandlePointerDown);
    this.endHandle?.removeEventListener('pointerdown', this.onEndHandlePointerDown);
  }

  private onCardPointerDown = (event:PointerEvent) => this.beginDrag(event, 'move');

  private onStartHandlePointerDown = (event:PointerEvent) => this.beginDrag(event, 'resize-start');

  private onEndHandlePointerDown = (event:PointerEvent) => this.beginDrag(event, 'resize-end');

  private beginDrag(event:PointerEvent, mode:'move'|'resize-start'|'resize-end') {
    // Only the primary mouse button / a single touch point starts a drag; a
    // plain click still falls through to the subject link underneath.
    if (event.button !== undefined && event.button !== 0) return;

    const cell = this.dayCellAt(event.clientX, event.clientY);
    if (!cell) return;

    event.preventDefault();
    this.mode = mode;
    this.dragging = true;
    this.moved = false;
    this.originCell = cell;
    this.lastTargetCell = cell;

    const style = (this.element as HTMLElement).style;
    this.originColumnStart = this.gridLineOf(style.gridColumnStart);
    this.originColumnEnd = this.gridLineOf(style.gridColumnEnd);
    this.originRow = this.gridLineOf(style.gridRow);

    const target = event.target as HTMLElement;
    target.setPointerCapture(event.pointerId);
    target.addEventListener('pointermove', this.onPointerMove);
    target.addEventListener('pointerup', this.onPointerUp);
    target.addEventListener('pointercancel', this.onPointerCancel);

    document.body.setAttribute('data-global-team-planner-dragging', 'true');
  }

  private onPointerMove = (event:PointerEvent) => {
    if (!this.dragging) return;

    const cell = this.dayCellAt(event.clientX, event.clientY);
    if (!cell || cell === this.lastTargetCell) return;

    this.moved = true;
    this.lastTargetCell = cell;
    this.applyLivePreview(cell);
  };

  private onPointerUp = (event:PointerEvent) => {
    this.endDrag(event.target as HTMLElement, event.pointerId);

    if (this.moved && this.lastTargetCell && this.originCell) {
      void this.submit(this.originCell, this.lastTargetCell);
    }
  };

  private onPointerCancel = (event:PointerEvent) => {
    this.endDrag(event.target as HTMLElement, event.pointerId);
    this.resetLivePreview();
  };

  private endDrag(target:HTMLElement, pointerId:number) {
    this.dragging = false;
    document.body.removeAttribute('data-global-team-planner-dragging');
    target.releasePointerCapture(pointerId);
    target.removeEventListener('pointermove', this.onPointerMove);
    target.removeEventListener('pointerup', this.onPointerUp);
    target.removeEventListener('pointercancel', this.onPointerCancel);
  }

  // Live-updates the card's own grid position/span so the proposed date
  // range (and, for a move, the proposed assignee row) is visible while
  // dragging — this is reset the moment the server responds, whether the
  // update succeeds or not, since the response always replaces this element.
  private applyLivePreview(targetCell:HTMLElement) {
    if (!this.originCell) return;

    const columnDelta = this.columnIndexOf(targetCell) - this.columnIndexOf(this.originCell);
    const style = (this.element as HTMLElement).style;

    if (this.mode === 'move') {
      style.gridColumnStart = String(this.originColumnStart + columnDelta);
      style.gridColumnEnd = String(this.originColumnEnd + columnDelta);
      style.gridRow = String(this.rowIndexOf(targetCell));
    } else if (this.mode === 'resize-start') {
      const newStart = Math.min(this.originColumnStart + columnDelta, this.originColumnEnd - 1);
      style.gridColumnStart = String(Math.max(newStart, 1));
    } else if (this.mode === 'resize-end') {
      const newEnd = Math.max(this.originColumnEnd + columnDelta, this.originColumnStart + 1);
      style.gridColumnEnd = String(newEnd);
    }
  }

  private resetLivePreview() {
    const style = (this.element as HTMLElement).style;
    style.gridColumnStart = String(this.originColumnStart);
    style.gridColumnEnd = String(this.originColumnEnd);
    style.gridRow = String(this.originRow);
  }

  private async submit(originCell:HTMLElement, targetCell:HTMLElement) {
    const deltaDays = this.daysBetween(originCell.dataset.date!, targetCell.dataset.date!);
    const data = new FormData();

    if (this.mode === 'move') {
      data.append('start_date', this.shiftDate(this.startDateValue, deltaDays));
      data.append('due_date', this.shiftDate(this.dueDateValue, deltaDays));
      data.append('assigned_to_id', targetCell.dataset.principalId ?? '');
    } else if (this.mode === 'resize-start') {
      data.append('start_date', this.shiftDate(this.startDateValue, deltaDays));
    } else if (this.mode === 'resize-end') {
      data.append('due_date', this.shiftDate(this.dueDateValue, deltaDays));
    }

    const surface = (this.element as HTMLElement).closest<HTMLElement>('.op-global-team-planner--surface');
    // `anchor_date`, not `anchor`: GridComponent reads this param name
    // because Rails' url_for treats `anchor` as the URL fragment.
    data.append('anchor_date', surface?.dataset.anchorDate ?? '');
    data.append('mode', surface?.dataset.displayMode ?? '');
    data.append('view_id', surface?.dataset.viewId ?? '');

    try {
      const request = new FetchRequest('put', this.urlValue, { body: data, responseKind: 'turbo-stream' });
      const response = await request.perform();
      if (!response.ok) this.resetLivePreview();
    } catch {
      this.resetLivePreview();
    }
  }

  private dayCellAt(x:number, y:number):HTMLElement|null {
    return document.elementsFromPoint(x, y)
      .find((el):el is HTMLElement => el instanceof HTMLElement && el.classList.contains('op-global-team-planner--day-cell'))
      ?? null;
  }

  private columnIndexOf(cell:HTMLElement):number {
    return Number(cell.dataset.columnIndex);
  }

  private rowIndexOf(cell:HTMLElement):number {
    return Number(cell.dataset.rowIndex);
  }

  private gridLineOf(value:string):number {
    const parsed = parseInt(value, 10);
    return Number.isNaN(parsed) ? 1 : parsed;
  }

  private daysBetween(fromIso:string, toIso:string):number {
    const from = Date.parse(`${fromIso}T00:00:00Z`);
    const to = Date.parse(`${toIso}T00:00:00Z`);
    return Math.round((to - from) / 86_400_000);
  }

  private shiftDate(iso:string, days:number):string {
    const date = new Date(`${iso}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
  }
}
