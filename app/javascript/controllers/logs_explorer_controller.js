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
  // Closes an expanded log message.
  //
  // Native `<details>` only toggles from its <summary>, and the summary's text is hidden while
  // open, leaving an empty strip as the only pointer target. The message body carries this
  // action so clicking what you are reading puts the row back. The <summary> is untouched, so
  // keyboard and assistive tech still drive the disclosure the way the element intends.
  //
  collapseMessage(event) {
    const details = event.currentTarget.closest("details");
    if (details) details.open = false;
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
    // `rowsTarget` is the <tbody>, so this inserts into the row container. Prepending to a
    // <table> instead would place the row before the header row, and the browser's table
    // parsing would hoist it out of the table entirely.
    this.rowsTarget.prepend(tr);
  }

  //
  // The row markup, built from the server's cell descriptors.
  //
  // The server sends one descriptor per visible column (`log_row_cells`), so the column
  // list and all formatting live in Ruby only. Do NOT hardcode columns here: an earlier
  // version did, and silently dropped every column it did not know about (host, severity,
  // priority), so live rows had fewer cells than loaded ones.
  //
  // The cell classes come from the server too (`row.classes`), because the row template
  // composes them from the table's column definition plus the hover marker. Restating them
  // here is what made an appended severity cell miss the width class a loaded one had.
  //
  // `kind` must stay in step with `logs/_cell.html.haml`; the two are the paired halves.
  // Values arrive ready to render, including the placeholder text for empty cells and the
  // column's label, so nothing is translated or derived on this side.
  //
  rowHtml(row) {
    return (row.cells || [])
      .map((cell, index) => this.cellHtml(cell, row.classes?.[index]))
      .join("");
  }

  cellHtml(cell, classes = "") {
    const value = this.escape(cell.value);
    const classAttr = classes ? ` class="${this.escape(classes)}"` : "";

    switch (cell.kind) {
      case "severity":
        // The colour goes on the <td> itself so it fills the whole cell with no padding; an
        // inner element would sit inside the cell padding. The level rides in the title so it
        // is still discoverable, and an unknown level falls back to the neutral colour so
        // column widths stay even. The width class arrives with the other cell classes.
        return `<td${classAttr} title="${value}" data-bs-toggle="tooltip"><span class="d-none"></span></td>`;
      case "time":
        return `<td${classAttr}><span class="text-nowrap">${value}</span></td>`;
      case "message":
        // The message is its own disclosure: the summary is the one-line preview and the body
        // is the whole record. `<details>` gives click-to-expand with no JS and no state, so an
        // appended row behaves exactly like a loaded one.
        //
        // The body leads with the full message, unlabelled and at the table's normal font
        // size, then the remaining fields as a list. The summary text is wrapped in a span so
        // the stylesheet can hide just the text while open (the body repeats it in full).
        //
        // The body carries `collapseMessage`: with the summary text hidden, the summary is an
        // empty strip, so the visible content is what the pointer should close the row with.
        // Matching `logs/_cell.html.haml`.
        const collapse = ' data-action="click->logs-explorer#collapseMessage"';
        return `<td${classAttr}><details class="log-message"><summary class="text-truncate"><span class="log-message-summary-text">${value}</span></summary><div class="mb-3"${collapse}>${this.escape(cell.message)}</div>${this.fieldsHtml(cell.fields, collapse)}</details></td>`;
      case "context":
        // The Context column: what KIND of thing logged this. Light because it is the
        // low-variance half and should not compete with the identifier beside it.
        return `<td${classAttr}><span class="badge text-bg-light">${value}</span></td>`;
      case "source":
        // The Source column, with a per-string colour computed server-side (see
        // `source_label_color`) so the same daemon or container is always the same colour.
        // Dark text because those colours are light; a label with no text gets no colour, so
        // an empty badge is not drawn as a confident one. Matching `LogsTableHelper`.
        return cell.color
          ? `<td${classAttr}><span class="badge text-dark" style="background-color: ${this.escape(cell.color)}">${value}</span></td>`
          : `<td${classAttr}><span class="badge text-bg-light">${value}</span></td>`;
      case "badge":
        return `<td${classAttr}><span class="badge text-bg-light">${value}</span></td>`;
      default:
        // "none" (and anything unrecognized) renders a muted placeholder, matching the
        // server, so a cell kind the client does not know still lines up.
        return `<td${classAttr}><span class="text-muted">${value}</span></td>`;
    }
  }

  //
  // The metadata list: one "key: value" item per record field, excluding the message, which
  // the caller renders on its own above this list.
  //
  // The key is italic and the value plain, which is the visual separator between them -- no
  // colon run together with the value, and no punctuation to misread. Both come from the
  // server ready to render, so nothing is derived here.
  //
  // Only the list is `small`: it is supporting metadata, while the message above it keeps the
  // table's normal font size.
  //
  fieldsHtml(fields = [], attrs = "") {
    const items = fields
      .map(
        (field) =>
          `<li><i>${this.escape(field.key)}</i>: ${this.escape(field.value)}</li>`,
      )
      .join("");
    return `<ul class="list-unstyled small mb-0"${attrs}>${items}</ul>`;
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
  // Toggles the `d-none` class -- the same mechanism the server uses (`hide: true`). A
  // class works for both CSS and JS, so there is one way to hide things rather than a
  // JS-only attribute competing with stylesheets.
  //
  renderPausedState() {
    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.classList.toggle("d-none", this.paused);
    }
    if (this.hasResumeButtonTarget) {
      this.resumeButtonTarget.classList.toggle("d-none", !this.paused);
    }
  }

  markFailed() {
    this.failed = true;
    if (this.hasStatusTarget) {
      this.statusTarget.classList.remove("d-none");
      this.statusTarget.textContent =
        this.statusTarget.dataset.errorText || "Disconnected";
    }
  }

  clearFailed() {
    if (!this.failed) return;
    this.failed = false;
    if (this.hasStatusTarget) this.statusTarget.classList.add("d-none");
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
