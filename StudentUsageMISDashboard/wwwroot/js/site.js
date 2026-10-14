(() => {
    "use strict";
    const menu = document.querySelector(".menu-toggle");
    menu?.addEventListener("click", () => {
        const open = document.body.classList.toggle("nav-open");
        menu.setAttribute("aria-expanded", String(open));
    });
    document.addEventListener("keydown", event => {
        if (event.key === "Escape") {
            document.body.classList.remove("nav-open");
            menu?.setAttribute("aria-expanded", "false");
        }
    });
    const tabs = [...document.querySelectorAll("[data-tab]")];
    function activate(id, focus = false) {
        const target = tabs.find(tab => tab.dataset.tab === id);
        if (!target) return;
        tabs.forEach(tab => {
            const selected = tab === target;
            tab.setAttribute("aria-selected", String(selected));
            tab.tabIndex = selected ? 0 : -1;
            document.getElementById(tab.getAttribute("aria-controls")).hidden = !selected;
        });
        document.querySelectorAll(".side-nav a").forEach(link => {
            link.classList.toggle("selected", link.dataset.navTab === id || (!link.dataset.navTab && id === "bucket"));
        });
        if (focus) target.focus();
    }
    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => { activate(tab.dataset.tab); history.replaceState(null, "", `#${tab.dataset.tab}`); });
        tab.addEventListener("keydown", event => {
            let next;
            if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
            if (event.key === "ArrowLeft") next = (index + tabs.length - 1) % tabs.length;
            if (event.key === "Home") next = 0;
            if (event.key === "End") next = tabs.length - 1;
            if (next !== undefined) { event.preventDefault(); activate(tabs[next].dataset.tab, true); }
        });
    });
    document.querySelectorAll("[data-nav-tab]").forEach(link => link.addEventListener("click", event => {
        if (!tabs.length) return;
        event.preventDefault();
        activate(link.dataset.navTab);
        history.replaceState(null, "", `#${link.dataset.navTab}`);
        document.body.classList.remove("nav-open");
        menu?.setAttribute("aria-expanded", "false");
    }));
    window.addEventListener("hashchange", () => activate(location.hash.slice(1)));
    activate(location.hash.slice(1) || "bucket");
    const source = document.getElementById("dashboard-data");
    if (!source) return;
    const data = JSON.parse(source.textContent);
    const number = value => new Intl.NumberFormat("en-IN", { maximumFractionDigits: 2 }).format(value);
    const colors = ["#66b7d7", "#729ae5", "#827be5", "#9c6edd", "#d066b4", "#14b9ad"];
    const total = data.buckets.reduce((sum, item) => sum + item.value, 0);
    let angle = 0;
    const stops = data.buckets.map((item, index) => {
        const start = angle;
        angle += total ? item.value / total * 360 : 0;
        return `${colors[index]} ${start}deg ${angle}deg`;
    });
    const donut = document.createElement("div");
    donut.className = "donut";
    donut.style.background = total ? `conic-gradient(${stops.join(",")})` : "#e4eaf3";
    donut.setAttribute("role", "img");
    donut.setAttribute("aria-label", `Usage distribution: ${data.buckets.map(item => `${item.name}: ${item.value} students`).join(", ")}`);
    const label = document.createElement("div");
    label.className = "donut-label";
    const count = document.createElement("strong");
    count.textContent = number(total);
    label.append(count, "Registered students");
    donut.append(label);
    document.getElementById("bucket-chart").append(donut);
    document.querySelectorAll(".compact-table tbody th").forEach((cell, index) => {
        const swatch = document.createElement("span");
        swatch.className = "bucket-color";
        swatch.style.background = colors[index];
        swatch.setAttribute("aria-hidden", "true");
        cell.prepend(swatch);
    });
    const maxDistrict = Math.max(0, ...data.districts.map(item => item.value));
    data.districts.forEach(item => {
        const row = document.createElement("div"); row.className = "bar-row";
        const name = document.createElement("span"); name.textContent = item.name;
        const track = document.createElement("div"); track.className = "bar-track";
        const fill = document.createElement("div"); fill.className = "bar-fill";
        fill.style.width = `${maxDistrict ? item.value / maxDistrict * 100 : 0}%`;
        track.append(fill);
        const value = document.createElement("span"); value.className = "bar-value"; value.textContent = number(item.value);
        row.append(name, track, value);
        document.getElementById("district-chart").append(row);
    });
    function trend(id, field, title) {
        const container = document.getElementById(id);
        if (!data.daily.length) { container.textContent = "No usage records for this period."; return; }
        const ns = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(ns, "svg");
        svg.setAttribute("viewBox", "0 0 560 240"); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", title + ". Values are available in the daily table.");
        function element(tag, attributes, text) {
            const node = document.createElementNS(ns, tag);
            Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
            if (text !== undefined) node.textContent = text;
            svg.append(node); return node;
        }
        const max = Math.max(1, ...data.daily.map(item => item[field]));
        const time = item => Date.parse(`${item.date}T00:00:00Z`);
        const start = time(data.daily[0]), end = time(data.daily[data.daily.length - 1]);
        const x = item => end === start ? 300 : 62 + (time(item) - start) / (end - start) * 475;
        const y = item => 196 - item[field] / max * 170;
        for (let step = 0; step <= 4; step++) {
            const height = 196 - step / 4 * 170;
            element("line", { x1: 62, x2: 537, y1: height, y2: height, stroke: "#e0e8f3" });
            element("text", { x: 54, y: height + 4, "text-anchor": "end" }, number(max * step / 4));
        }
        let segment = [];
        function flush() {
            if (segment.length > 1) element("polyline", { points: segment.join(" "), fill: "none", stroke: field === "students" ? "#387be3" : "#13a99d", "stroke-width": 2.5 });
            segment = [];
        }
        data.daily.forEach((item, index) => {
            if (index && time(item) - time(data.daily[index - 1]) > 86400000) flush();
            segment.push(`${x(item)},${y(item)}`);
        });
        flush();
        data.daily.forEach(item => {
            const point = element("circle", { cx: x(item), cy: y(item), r: 3, fill: field === "students" ? "#387be3" : "#13a99d" });
            const tooltip = document.createElementNS(ns, "title"); tooltip.textContent = `${item.date}: ${number(item[field])}`; point.append(tooltip);
        });
        element("text", { x: 62, y: 222 }, data.daily[0].date);
        element("text", { x: 537, y: 222, "text-anchor": "end" }, data.daily[data.daily.length - 1].date);
        container.append(svg);
    }
    trend("daily-students-chart", "students", "Daily active students");
    trend("daily-usage-chart", "usage", `Daily usage in ${data.unit.toLowerCase()}`);
})();
