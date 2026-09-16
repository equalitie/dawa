import { Controller } from "@hotwired/stimulus";

//
// Live refresh for the log explorer (logs-plan Step 4).
//
// Deliberately THIN and STATE-ONLY. This controller owns:
//   - the current filter state (echoed back to the server as params)
//   - the cursor (the newest _time it has displayed)
//   - paused/running, and the poll timer
//
// It does NOT build LogsQL, and it does not format records. Every row it appends comes
// pre-formatted from the server (`log_row` in LogsHelper), so live rows look identical to
// the ones the initial page render produced. Building LogsQL here would give quoting and
// escaping a second home, which is the specific mistake Step 4 warns about.
//
// usage:
//   <div data-controller="logs-explorer"
//        data-logs-explorer-url-value="/logs/data"
//        data-logs-explorer-interval-value="1500"
//        data-logs-explorer-cursor-value="2026-09-08T00:59:12.000000Z">
//     <table>
//       <tbody data-logs-explorer-target="rows"> ...initial rows... </tbody>
//     </table>
//     <button data-action="logs-explorer#togglePause"
//             data-logs-explorer-target="pauseButton">Pause</button>
//     <button data-action="logs-explorer#resume"
//             data-logs-explorer-target="resumeButton">Resume</button>
//   </div>
//
// The URL carries the filter state as a query string, and filter changes perform a *full
// page navigation* (the filter controls are ordinary links/forms). That keeps filter state
// in one place -- the URL, which the server parses -- instead of duplicating it in JS.
//
export default class extends Controller {
  static targets = ["rows", "pauseButton", "resumeButton", "status"];

  static values = {
    url: String,
    interval: { type: Number, default: 1500 },
    cursor: String,
    // How many rows to keep in the DOM. Logs arrive continuously, so without a cap the
    // table grows until the tab dies.
    maxRows: { type: Number, default: 500 },
  };

  connect() {
    this.paused = false;
    this.polling = false;
    this.failed = false;
    // Keys already rendered, so a batch overlapping at the cursor boundary cannot
    // double-insert. Seeded from the server-rendered rows.
    this.seen = new Set(
      this.rowTargets.map((el) => el.dataset.rowKey).filter(Boolean),
    );

    this.poller = setInterval(() => this.poll(), this.intervalValue);
  }

  disconnect() {
    if (this.poller) clearInterval(this.poller);
    this.poller = null;
    this.polling = false;
  }

  //
  // Fetches the next batch and merges it.
  //
  async poll() {
    if (this.paused || this.polling) return;
    this.polling = true;

    try {
      const res = await fetch(this.buildUrl(), {
        headers: { Accept: "application/json" },
      });

      // A non-2xx means the backend failed. Surface it rather than showing an empty
      // batch, which would be indistinguishable from "no new logs".
      if (!res.ok) {
        this.markFailed();
        return;
      }

      const data = await res.json();
      this.clearFailed();
      this.append(data.rows || []);
      this.advanceCursor(data.cursor);
    } catch (_e) {
      // Transient network error; keep what we have and retry on the next tick.
      this.markFailed();
    } finally {
      this.polling = false;
    }
  }

  togglePause() {
    this.paused = !this.paused;
    this.renderPausedState();
  }

  //
  // Resume and immediately catch up on whatever arrived while paused. The cursor was not
  // advanced while paused, so this single poll fetches the whole gap.
  //
  resume() {
    this.paused = false;
    this.renderPausedState();
    this.poll();
  }

  //
  // Merges a batch into the table, newest-first.
  //
  append(rows) {
    if (!this.hasRowsTarget || rows.length === 0) return;

    const fresh = this.newRows(rows);
    // The server returns newest-first; prepending preserves that at the top of the list.
    fresh.reverse().forEach((row) => this.prependRow(row));
    this.trimToMaxRows();
  }

  // Only rows whose key we have not rendered yet, in server order (newest first).
  newRows(rows) {
    return rows.filter((row) => {
      const key = row.key;
      // A row with no key cannot be deduped, so treat it as new rather than dropping a
      // real log line.
      if (!key) return true;
      if (this.seen.has(key)) return false;
      this.seen.add(key);
      return true;
    });
  }

  prependRow(row) {
    const tr = document.createElement("tr");
    tr.dataset.rowKey = row.key || "";
    tr.innerHTML = this.rowHtml(row);
    this.rowsTarget.prepend(tr);
  }

  //
  // The row markup, built from the server's pre-formatted fields.
  //
  // Kept in the same column order as the server-rendered table (LogsFieldCatalog order:
  // time, source, message) plus the JSON disclosure, so appended rows line up with the
  // ones already on the page.
  //
  rowHtml(row) {
    return [
      `<td class="fit"><span class="text-nowrap">${this.escape(row.time_display)}</span></td>`,
      `<td class="fit"><span class="badge text-bg-light">${this.escape(row.source)}</span></td>`,
      `<td class="truncate-auto"><code>${this.escape(row.message)}</code></td>`,
      `<td class="fit"><details><summary>JSON</summary><pre class="small mb-0">${this.escape(row.json)}</pre></details></td>`,
    ].join("");
  }

  trimToMaxRows() {
    const rows = this.rowTargets;
    const excess = rows.length - this.maxRowsValue;
    if (excess <= 0) return;

    // Drop the oldest rows (the end of a newest-first table).
    for (let i = 0; i < excess; i += 1) {
      const last = rows[rows.length - 1 - i];
      if (!last) break;
      if (last.dataset.rowKey) this.seen.delete(last.dataset.rowKey);
      last.remove();
    }
  }

  advanceCursor(cursor) {
    if (!cursor) return;
    // Never move the cursor backwards: an out-of-order response would otherwise cause the
    // next poll to re-request (and re-dedupe) an already-seen interval.
    if (this.cursorValue && cursor <= this.cursorValue) return;
    this.cursorValue = cursor;
  }

  buildUrl() {
    const url = new URL(this.urlValue, window.location.origin);
    // Carry the page's current filters through, then narrow to the cursor window.
    const page = new URLSearchParams(window.location.search);
    page.forEach((value, key) => {
      if (!url.searchParams.has(key)) url.searchParams.set(key, value);
    });
    if (this.cursorValue) url.searchParams.set("cursor", this.cursorValue);
    return url.toString();
  }

  //
  // Swaps the pause/resume control.
  //
  // Uses the `hidden` property, which toggles the `hidden` attribute. The server marks the
  // initial state the same way (`html: {hidden: true}`); if it used an inline
  // `display: none` instead, setting `.hidden = false` here would clear the attribute but
  // leave the style, and Resume would never reappear.
  //
  renderPausedState() {
    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.hidden = this.paused;
    }
    if (this.hasResumeButtonTarget) {
      this.resumeButtonTarget.hidden = !this.paused;
    }
  }

  markFailed() {
    this.failed = true;
    if (this.hasStatusTarget) {
      this.statusTarget.hidden = false;
      this.statusTarget.textContent =
        this.statusTarget.dataset.errorText || "Disconnected";
    }
  }

  clearFailed() {
    if (!this.failed) return;
    this.failed = false;
    if (this.hasStatusTarget) this.statusTarget.hidden = true;
  }

  get rowTargets() {
    if (!this.hasRowsTarget) return [];
    return Array.from(this.rowsTarget.querySelectorAll("tr[data-row-key]"));
  }

  escape(value) {
    const div = document.createElement("div");
    div.textContent = value == null ? "" : String(value);
    return div.innerHTML;
  }
}
