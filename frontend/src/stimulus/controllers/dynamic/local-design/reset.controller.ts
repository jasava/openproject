/*
 * -- copyright
 * OpenProject Local Design
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

// Keeps the reset button's Turbo confirmation message in sync with the
// "also remove uploaded branding assets" checkbox (Phase 5: "Reset must
// require confirmation and must not delete uploaded branding assets unless
// the confirmation explicitly states that branding assets will also be
// removed").
export default class ResetController extends Controller {
  static targets = ['removeAssets', 'submitButton'];

  static values = { confirmDefault: String, confirmWithAssets: String };

  declare readonly removeAssetsTarget:HTMLInputElement;
  declare readonly submitButtonTarget:HTMLElement;
  declare readonly confirmDefaultValue:string;
  declare readonly confirmWithAssetsValue:string;

  connect() {
    this.syncConfirmMessage();
  }

  syncConfirmMessage() {
    const message = this.removeAssetsTarget.checked ? this.confirmWithAssetsValue : this.confirmDefaultValue;
    this.submitButtonTarget.setAttribute('data-turbo-confirm', message);
  }
}
