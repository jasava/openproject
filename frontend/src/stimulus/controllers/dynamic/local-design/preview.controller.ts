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

// Live-updates the self-contained preview mockup (Phase 9) as an
// administrator edits a color field, without ever writing to
// `document.documentElement` — every CSS custom property this controller
// sets lives on `previewRoot` (a small <div>, see _preview_panel.html.erb),
// so it only ever affects the mockup markup inside it. Canceling or leaving
// the page therefore cannot "leak" an unsaved color anywhere real.
//
// Also implements Phase 6's per-field "reset to theme default" action and
// Phase 7's client-side contrast warning (a convenience mirror of the
// server-side check — the server is always the final authority; see
// LocalDesignSettingContract).
const HEX_RE = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
const WHITE = '#FFFFFF';

interface ContrastCheck {
  keys:[string, string];
  fixedForeground?:string;
}

// Pairs whose contrast should be checked together whenever either side
// changes. `primary_button_background` has no configurable text color (see
// lib/local_design/design.rb) so it is checked against a fixed white
// foreground, matching this codebase's Primer button styling.
const CONTRAST_CHECKS:ContrastCheck[] = [
  { keys: ['primary_button_background', 'primary_button_background'], fixedForeground: WHITE },
  { keys: ['header_background', 'header_foreground'] },
  { keys: ['main_menu_background', 'main_menu_foreground'] },
  { keys: ['main_menu_selected_background', 'main_menu_selected_foreground'] },
];

export default class PreviewController extends Controller {
  static targets = ['previewRoot', 'hexInput', 'nativeInput', 'swatch', 'resetButton', 'feedback'];

  static values = {
    minContrast: { type: Number, default: 4.5 },
    invalidFormatMessage: String,
    contrastWarningTemplate: String,
  };

  declare readonly previewRootTarget:HTMLElement;
  declare readonly hexInputTargets:HTMLInputElement[];
  declare readonly nativeInputTargets:HTMLInputElement[];
  declare readonly swatchTargets:HTMLElement[];
  declare readonly resetButtonTargets:HTMLElement[];
  declare readonly feedbackTargets:HTMLElement[];
  declare readonly minContrastValue:number;
  declare readonly invalidFormatMessageValue:string;
  declare readonly contrastWarningTemplateValue:string;

  connect() {
    this.hexInputTargets.forEach((input) => this.applyValue(input.dataset.key!, input.value, { silent: true }));
    this.hexInputTargets.forEach((input) => this.checkContrastFor(input.dataset.key!));
  }

  hexInputChanged(event:Event) {
    const input = event.currentTarget as HTMLInputElement;
    const key = input.dataset.key!;
    const raw = input.value.trim();

    if (!HEX_RE.test(raw)) {
      this.setFeedback(key, this.invalidFormatMessage());
      return;
    }

    this.applyValue(key, raw);
  }

  nativeInputChanged(event:Event) {
    const input = event.currentTarget as HTMLInputElement;
    const key = input.dataset.key!;

    this.applyValue(key, input.value);
  }

  resetField(event:Event) {
    const button = event.currentTarget as HTMLElement;
    const key = button.dataset.key!;
    const fallback = button.dataset.default;
    if (!fallback) return;

    this.applyValue(key, fallback);
  }

  private applyValue(key:string, rawValue:string, options:{ silent?:boolean } = {}) {
    const normalized = this.normalize(rawValue);
    if (!normalized) return;

    this.hexInputTargets
      .filter((el) => el.dataset.key === key)
      .forEach((el) => { el.value = normalized; });

    this.nativeInputTargets
      .filter((el) => el.dataset.key === key)
      .forEach((el) => { el.value = normalized; });

    this.swatchTargets
      .filter((el) => el.dataset.key === key)
      .forEach((el) => {
        el.style.backgroundColor = normalized;
      });

    const cssVar = this.hexInputTargets.find((el) => el.dataset.key === key)?.dataset.cssVar;
    if (cssVar) {
      this.previewRootTarget.style.setProperty(cssVar, normalized);
    }

    if (!options.silent) {
      this.clearFeedback(key);
    }

    this.checkContrastFor(key);
  }

  private checkContrastFor(changedKey:string) {
    CONTRAST_CHECKS
      .filter((check) => check.keys.includes(changedKey))
      .forEach((check) => {
        const [backgroundKey, foregroundKey] = check.keys;
        const background = this.currentValue(backgroundKey);
        const foreground = check.fixedForeground ?? this.currentValue(foregroundKey);
        if (!background || !foreground) return;

        const ratio = contrastRatio(background, foreground);
        const feedbackKey = foregroundKey === backgroundKey ? backgroundKey : foregroundKey;

        if (ratio < this.minContrastValue) {
          this.setFeedback(feedbackKey, this.contrastWarningMessage(ratio));
        } else {
          this.clearFeedback(feedbackKey);
        }
      });
  }

  private currentValue(key:string):string|null {
    const input = this.hexInputTargets.find((el) => el.dataset.key === key);
    return input ? this.normalize(input.value) : null;
  }

  private normalize(value:string):string|null {
    const trimmed = value.trim();
    if (!HEX_RE.test(trimmed)) return null;

    if (trimmed.length === 4) {
      const [, r, g, b] = trimmed;
      return `#${r}${r}${g}${g}${b}${b}`.toUpperCase();
    }

    return trimmed.toUpperCase();
  }

  private setFeedback(key:string, message:string) {
    this.feedbackTargets
      .filter((el) => el.id === `local_design_color_${key}_feedback`)
      .forEach((el) => { el.textContent = message; });
  }

  private clearFeedback(key:string) {
    this.feedbackTargets
      .filter((el) => el.id === `local_design_color_${key}_feedback`)
      .forEach((el) => { el.textContent = ''; });
  }

  private invalidFormatMessage():string {
    return this.invalidFormatMessageValue;
  }

  private contrastWarningMessage(ratio:number):string {
    return this.contrastWarningTemplateValue
      .replace('%<ratio>s', ratio.toFixed(1))
      .replace('%<minimum>s', this.minContrastValue.toString());
  }
}

// WCAG 2.x relative luminance / contrast ratio, operating on plain #RRGGBB
// hex strings (both inputs are already normalized by `normalize()` above).
function relativeLuminance(hex:string):number {
  const channel = (value:number) => {
    const srgb = value / 255;
    return srgb <= 0.03928 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
  };

  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);

  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

function contrastRatio(hexA:string, hexB:string):number {
  const luminanceA = relativeLuminance(hexA) + 0.05;
  const luminanceB = relativeLuminance(hexB) + 0.05;

  return luminanceA > luminanceB ? luminanceA / luminanceB : luminanceB / luminanceA;
}
