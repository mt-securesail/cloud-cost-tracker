// Keeps the dashboard current without full page reloads (PRD R1, F5, F9).
//
// - Shows every <time data-local> in the browser's time zone.
// - Updates the "(… ago)" text every 30 seconds, with no request.
// - Every 5 minutes, and when the tab becomes visible again, fetches
//   /summary.json (served from the app's memory; never calls AWS) and rebuilds
//   the page sections in place, matching app/views/home/index.html.erb.
// - If that fetch fails, keeps the last data on screen with a warning.
// - Reloads the whole page once after a deploy, so new markup and this script
//   take effect.
//
// Builds every element with textContent (via append), never innerHTML, so
// text from AWS such as service names can't become HTML. Loaded from the same
// origin, as the Content-Security-Policy (script-src 'self') requires.
(() => {
  "use strict";

  const AGE_TICK_MS = 30 * 1000;
  const MIN_VISIBLE_REFETCH_MS = 60 * 1000;

  const timeFormat = new Intl.DateTimeFormat(undefined, {
    weekday: "short", month: "short", day: "numeric", year: "numeric",
    hour: "numeric", minute: "2-digit", timeZoneName: "short"
  });

  // Must match CostFormatHelper#age.
  function age(iso, now = Date.now()) {
    const seconds = Math.max(0, Math.floor((now - Date.parse(iso)) / 1000));
    if (seconds < 60) return "just now";
    if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
    if (seconds < 48 * 3600) return `${Math.floor(seconds / 3600)} h ago`;
    return `${Math.floor(seconds / 86400)} days ago`;
  }

  // el("p", { class: "x" }, "text", childNode, [more, children])
  // Strings become text nodes. null, undefined, and false are skipped.
  function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attrs || {})) {
      if (value === null || value === undefined || value === false) continue;
      node.setAttribute(name, value === true ? "" : String(value));
    }
    for (const child of children.flat(2)) {
      if (child === null || child === undefined || child === false) continue;
      node.append(child);
    }
    return node;
  }

  const timeEl = (iso) => el("time", { datetime: iso, "data-local": true }, iso);
  const ageEl = (iso) => el("span", { class: "muted", "data-since": iso });

  function localize(root) {
    root.querySelectorAll("time[data-local]").forEach((t) => {
      const ms = Date.parse(t.dateTime);
      if (!Number.isNaN(ms)) t.textContent = timeFormat.format(ms);
    });
    tickAges(root);
  }

  function tickAges(root) {
    root.querySelectorAll("[data-since]").forEach((span) => {
      span.textContent = `(${age(span.dataset.since)})`;
    });
  }

  // --- One function per section; each returns a replacement element. ---

  function headline(p) {
    const node = el("p", { class: "headline", id: "headline" });
    if (p.last_updated_at) {
      node.append("Costs last updated at ", el("strong", {}, timeEl(p.last_updated_at)), " ", ageEl(p.last_updated_at));
    } else {
      node.append(p.not_loaded_text);
    }
    return node;
  }

  function sources(p) {
    return el("ul", { class: "as-of", id: "sources" }, p.sources.map((s) =>
      el("li", {}, `${s.label}: `,
        s.as_of ? [timeEl(s.as_of), " ", ageEl(s.as_of)] : s.placeholder,
        s.stale && [" ", el("span", { class: "stale" }, s.stale)])));
  }

  function figures(p) {
    const c = p.current_charges;
    const e = p.estimated_total;
    return el("section", { class: "figures", id: "figures" },
      el("div", { class: "figure" },
        el("h2", {}, "Current charges"),
        el("p", { class: "amount", id: "current-charges" }, c.amount),
        el("p", { class: "detail" }, "Month to date, CloudWatch estimate"),
        c.warning && el("p", { class: "warning" }, c.warning)),
      el("div", { class: "figure" },
        el("h2", {}, e.title),
        el("p", { class: "amount", id: "estimated-total" }, e.amount),
        e.details.map((d) => el("p", { class: "detail" }, d)),
        e.warning && el("p", { class: "warning" }, e.warning)));
  }

  const num = (text) => el("td", { class: "num" }, text);
  const rowClass = (row) => (row.bedrock ? "bedrock" : null);

  function byService(b) {
    return el("section", {},
      el("h2", { class: "section-title" }, "This month by service"),
      el("table", { class: "costs", id: "by-service" },
        el("thead", {}, el("tr", {},
          el("th", { scope: "col" }, "Service"),
          el("th", { scope: "col", class: "num" }, "Cost"),
          el("th", { scope: "col", class: "num" }, "Share"))),
        el("tbody", {}, b.rows.map((row) => el("tr", { class: rowClass(row) },
          el("th", { scope: "row" }, row.name, row.bedrock && [" ", el("span", { class: "tag" }, "Bedrock model")]),
          num(row.current),
          num(row.share)))),
        el("tfoot", {}, el("tr", {}, el("th", { scope: "row" }, "Total"), num(b.total.current), el("td")))));
  }

  function comparison(b) {
    const title = el("h2", { class: "section-title" }, "Previous 3 months");
    if (b.history_message) return el("section", {}, title, el("p", { class: "detail" }, b.history_message));

    return el("section", {}, title,
      el("div", { class: "scroll" },
        el("table", { class: "costs", id: "comparison" },
          el("thead", {}, el("tr", {},
            el("th", { scope: "col" }, "Service"),
            b.months.map((m) => el("th", { scope: "col", class: "num" }, m)),
            el("th", { scope: "col", class: "num" }, `${b.current_month}*`))),
          el("tbody", {}, b.rows.map((row) => el("tr", { class: rowClass(row) },
            el("th", { scope: "row" }, row.name),
            row.months.map(num),
            num(row.current)))),
          el("tfoot", {}, el("tr", {},
            el("th", { scope: "row" }, "Total"),
            b.total.months.map(num),
            num(b.total.current))))),
      el("p", { class: "detail" }, b.footnote),
      b.history_warning && el("p", { class: "warning" }, b.history_warning));
  }

  function breakdown(p) {
    const b = p.breakdown;
    return el("div", { id: "breakdown" }, b && [byService(b), comparison(b)]);
  }

  function period(p) {
    return el("dl", { class: "period", id: "period" },
      el("dt", {}, "Today (UTC)"), el("dd", {}, p.period.today),
      el("dt", {}, "Billing period"), el("dd", {}, p.period.range),
      el("dt", {}, "Day"), el("dd", { id: "day-of-period" }, p.period.day));
  }

  function render(dashboard, p) {
    [headline, sources, figures, breakdown, period].forEach((build) => {
      const node = build(p);
      const current = document.getElementById(node.id);
      if (current) current.replaceWith(node);
    });
    localize(dashboard);
  }

  // Shown when the app can't be reached (app switched off, network down,
  // IP no longer allowed). The figures stay as last received.
  function showConnectionProblem(lastSuccessIso, pollSeconds) {
    const banner = document.getElementById("connection");
    if (!banner) return;
    if (!lastSuccessIso) {
      banner.hidden = true;
      banner.replaceChildren();
      return;
    }
    banner.replaceChildren(
      "Can't reach the app. Showing data received at ", timeEl(lastSuccessIso), " ", ageEl(lastSuccessIso),
      `; trying again every ${Math.round(pollSeconds / 60)} minutes.`);
    banner.hidden = false;
    localize(banner);
  }

  // After a deploy, reload once to get the new page. Remembers the version it
  // reloaded for, so a page and summary that keep disagreeing (for example
  // while old and new tasks both serve during a deploy) can't cause repeated
  // reloads. Returns true when a reload has started.
  function reloadOnceFor(version) {
    const key = "dashboard-reloaded-for";
    try {
      if (sessionStorage.getItem(key) === version) return false;
      sessionStorage.setItem(key, version);
    } catch (_error) {
      return false; // storage blocked: never reload automatically
    }
    window.location.reload();
    return true;
  }

  function start() {
    const dashboard = document.getElementById("dashboard");
    if (!dashboard) return;

    const pollSeconds = Number(dashboard.dataset.pollSeconds) || 300;
    let lastAttempt = Date.now();
    let lastSuccessIso = new Date().toISOString();

    async function poll() {
      lastAttempt = Date.now();
      try {
        const response = await fetch("/summary.json", {
          headers: { Accept: "application/json" }, cache: "no-store", credentials: "same-origin", redirect: "error"
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const payload = await response.json();
        if (payload.version !== dashboard.dataset.version && reloadOnceFor(payload.version)) return;
        render(dashboard, payload);
        lastSuccessIso = new Date().toISOString();
        showConnectionProblem(null, pollSeconds);
      } catch (_error) {
        showConnectionProblem(lastSuccessIso, pollSeconds);
      }
    }

    localize(dashboard);
    setInterval(poll, pollSeconds * 1000);
    setInterval(() => tickAges(dashboard), AGE_TICK_MS);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && Date.now() - lastAttempt > MIN_VISIBLE_REFETCH_MS) poll();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
