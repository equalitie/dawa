import { Controller } from "@hotwired/stimulus";

//
// Polls the container stats JSON endpoint and renders current CPU/memory
// utilization plus a simple HTML bar chart of CPU over time.
//
// usage:
//   <div data-controller="container-stats"
//        data-container-stats-url-value="/containers/abc/stats.json"
//        data-container-stats-interval-value="1500">
//   </div>
//
export default class extends Controller {
  static targets = [
    "cpuBar",
    "cpuText",
    "memBar",
    "memText",
    "netText",
    "ioText",
    "chart",
  ];

  static values = {
    url: String,
    interval: { type: Number, default: 1500 },
    maxPoints: { type: Number, default: 60 },
  };

  connect() {
    this.points = []; // [{ cpu, memPct, time }]
    this.poller = setInterval(() => this.poll(), this.intervalValue);
    this.poll(); // immediate first load
  }

  disconnect() {
    if (this.poller) clearInterval(this.poller);
  }

  async poll() {
    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
      });
      if (!res.ok) return;
      const data = await res.json();
      this.render(data);
    } catch (_e) {
      // ignore transient errors; keep last known values
    }
  }

  render(data) {
    if (typeof data.cpu_pct === "number") {
      this.setBar(this.cpuBarTarget, data.cpu_pct);
      this.cpuTextTarget.textContent = `${data.cpu_pct.toFixed(1)}%`;
    }
    if (typeof data.mem_pct === "number" && typeof data.mem_used === "number") {
      this.setBar(this.memBarTarget, data.mem_pct);
      this.memTextTarget.textContent = `${this.humanSize(data.mem_used)} / ${this.humanSize(data.mem_limit || 0)} (${data.mem_pct.toFixed(1)}%)`;
    }

    if (typeof data.net_rx === "number" || typeof data.net_tx === "number") {
      const rx = this.humanRate(data.net_rx);
      const tx = this.humanRate(data.net_tx);
      this.netTextTarget.textContent = `⇣ ${rx}/s · ⇡ ${tx}/s`;
    }
    if (
      typeof data.blk_read === "number" ||
      typeof data.blk_write === "number"
    ) {
      const rd = this.humanRate(data.blk_read);
      const wr = this.humanRate(data.blk_write);
      this.ioTextTarget.textContent = `read ${rd}/s · write ${wr}/s`;
    }

    if (typeof data.cpu_pct === "number") {
      this.points.push({
        cpu: data.cpu_pct,
        memPct: data.mem_pct,
        time: data.timestamp,
      });
      if (this.points.length > this.maxPointsValue) this.points.shift();
      this.renderChart();
    }
  }

  humanRate(value) {
    if (typeof value !== "number") return "—";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let v = value;
    let unit = 0;
    while (v >= 1024 && unit < units.length - 1) {
      v /= 1024;
      unit += 1;
    }
    return `${v.toFixed(v >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
  }

  setBar(bar, pct) {
    const clamped = Math.max(0, Math.min(100, pct));
    bar.style.width = `${clamped}%`;
    bar.setAttribute("aria-valuenow", clamped.toFixed(1));
  }

  renderChart() {
    const container = this.chartTarget.firstElementChild;
    container.textContent = "";
    const max = Math.max(...this.points.map((p) => p.cpu), 1);
    for (const point of this.points) {
      const height = Math.max(2, Math.round((point.cpu / max) * 100));
      const bar = document.createElement("div");
      bar.className = "bg-info rounded";
      bar.style.height = `${height}%`;
      bar.style.width = `${Math.max(3, 100 / this.points.length)}%`;
      bar.title = `CPU ${point.cpu.toFixed(1)}%`;
      container.appendChild(bar);
    }
  }

  humanSize(bytes) {
    if (!bytes) return "—";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
  }
}
