const XS = (() => {
    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'XS-Trucking';
    const state = { config: { currency: '$', unit: 'mi', maxLevel: 50 } };

    async function post(endpoint, data = {}) {
        try {
            const res = await fetch(`https://${RES}/${endpoint}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            const text = await res.text();
            return text ? JSON.parse(text) : null;
        } catch (err) {
            return null;
        }
    }

    function fix(value) {
        if (Array.isArray(value)) return value.map(fix);
        if (value && typeof value === 'object') {
            const keys = Object.keys(value);
            if (!keys.length) return [];
            for (const k of keys) value[k] = fix(value[k]);
        }
        return value;
    }

    async function rpc(fn, ...args) {
        const res = await post('rpc', { fn, args });
        if (!res || typeof res !== 'object') return { ok: false, error: 'No answer from the game.' };
        const data = fix(res.result === true ? res.extra : res.result);
        return { ok: res.ok === true, data, error: res.ok ? null : (typeof res.extra === 'string' ? res.extra : res.error || 'That did not work.') };
    }

    function esc(value) {
        return String(value ?? '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function money(amount) {
        const n = Math.round(Number(amount) || 0);
        return `${n < 0 ? '-' : ''}${state.config.currency || '$'}${Math.abs(n).toLocaleString('en-US')}`;
    }

    function num(value, digits = 0) {
        return (Number(value) || 0).toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
    }

    function dist(km) {
        const k = Number(km) || 0;
        if (state.config.unit === 'km') return `${k < 10 ? k.toFixed(1) : Math.round(k)} km`;
        const mi = k * 0.621371;
        return `${mi < 10 ? mi.toFixed(1) : Math.round(mi)} mi`;
    }

    function metres(m) {
        return dist((Number(m) || 0) / 1000);
    }

    function clock(seconds) {
        const s = Math.max(0, Math.floor(Number(seconds) || 0));
        const m = Math.floor(s / 60);
        return `${m}:${String(s % 60).padStart(2, '0')}`;
    }

    function ago(ts) {
        const s = Math.max(0, Math.floor(Date.now() / 1000 - (Number(ts) || 0)));
        if (s < 60) return 'just now';
        if (s < 3600) return `${Math.floor(s / 60)}m ago`;
        if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
        return `${Math.floor(s / 86400)}d ago`;
    }

    function h(html) {
        const t = document.createElement('template');
        t.innerHTML = html.trim();
        return t.content.firstElementChild;
    }

    function $(sel, root = document) { return root.querySelector(sel); }
    function $$(sel, root = document) { return [...root.querySelectorAll(sel)]; }

    function toast(message, kind = 'info') {
        const stack = $('#toasts');
        if (!stack || !message) return;
        const node = h(`<div class="toast ${esc(kind)}"><span class="dot"></span><span>${esc(message)}</span></div>`);
        stack.appendChild(node);
        requestAnimationFrame(() => node.classList.add('in'));
        setTimeout(() => {
            node.classList.remove('in');
            setTimeout(() => node.remove(), 320);
        }, kind === 'error' ? 4200 : 3000);
    }

    function result(res, success) {
        if (res.ok) {
            if (success) toast(typeof success === 'function' ? success(res.data) : success, 'success');
        } else {
            toast(res.error, 'error');
        }
        return res.ok;
    }

    function ask({ title, text, confirm = 'Confirm', danger = false, input = null }) {
        return new Promise((resolve) => {
            const layer = $('#modal');
            layer.innerHTML = `
                <div class="modal glass">
                    <h3>${esc(title)}</h3>
                    ${text ? `<p>${esc(text)}</p>` : ''}
                    ${input ? `<input class="field" id="modal-input" type="${esc(input.type || 'text')}" placeholder="${esc(input.placeholder || '')}" value="${esc(input.value ?? '')}">` : ''}
                    <div class="row end">
                        <button class="btn ghost" data-act="no">Cancel</button>
                        <button class="btn ${danger ? 'danger' : 'primary'}" data-act="yes">${esc(confirm)}</button>
                    </div>
                </div>`;
            layer.classList.add('open');
            const field = $('#modal-input', layer);
            if (field) setTimeout(() => field.focus(), 30);

            const done = (value) => {
                layer.classList.remove('open');
                layer.innerHTML = '';
                resolve(value);
            };
            layer.onclick = (e) => {
                const act = e.target.closest('[data-act]');
                if (e.target === layer) return done(null);
                if (!act) return;
                if (act.dataset.act === 'no') return done(null);
                done(input ? (field ? field.value : '') : true);
            };
            layer.onkeydown = (e) => {
                if (e.key === 'Enter') done(input ? (field ? field.value : '') : true);
                if (e.key === 'Escape') { e.stopPropagation(); done(null); }
            };
        });
    }

    function countUp(node, to, { duration = 900, format = (v) => money(v), from = 0 } = {}) {
        if (!node) return;
        const start = performance.now();
        const step = (now) => {
            const t = Math.min(1, (now - start) / duration);
            const eased = 1 - Math.pow(1 - t, 3);
            node.textContent = format(from + (to - from) * eased);
            if (t < 1) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
    }

    const ICONS = {
        loads: '<path d="M3 7h13v10H3z"/><path d="M16 10h3l2 3v4h-5"/><circle cx="7" cy="18" r="1.6"/><circle cx="17.5" cy="18" r="1.6"/>',
        run: '<path d="M12 21s-6-5.5-6-10a6 6 0 1 1 12 0c0 4.5-6 10-6 10z"/><circle cx="12" cy="11" r="2.2"/>',
        truck: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17l3 3 5.3-5.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z"/>',
        skills: '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="18" r="2"/><circle cx="12" cy="6" r="2"/><path d="M12 8v4M12 12l-5 4.5M12 12l5 4.5"/>',
        certs: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
        business: '<path d="M3 21V9l9-6 9 6v12"/><path d="M9 21v-6h6v6"/>',
        boards: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3a3 3 0 0 1-3 4M7 5H4a3 3 0 0 0 3 4"/>',
        close: '<path d="M6 6l12 12M18 6L6 18"/>',
        lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
        check: '<path d="M5 12l5 5L19 7"/>',
        target: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="1.6"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
        flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
        pin: '<path d="M12 21s-6-5.5-6-10a6 6 0 1 1 12 0c0 4.5-6 10-6 10z"/>',
        plus: '<path d="M12 5v14M5 12h14"/>',
        trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
        eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
        spark: '<path d="M12 3l2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        fuel: '<path d="M4 21V5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v16M4 11h11M15 8l3 3v7a2 2 0 0 0 4 0v-9l-3-3"/>',
        shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
        users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 21a7 7 0 0 1 14 0M16 11a3 3 0 1 0 0-6M22 21a6 6 0 0 0-5-6"/>',
        bank: '<path d="M3 10l9-6 9 6M5 10v8M9 10v8M15 10v8M19 10v8M3 21h18"/>',
        gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
        route: '<circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M8 19h7a3.5 3.5 0 0 0 0-7H9a3.5 3.5 0 0 1 0-7h7"/>',
        hot: '<path d="M12 22c4 0 7-3 7-7 0-5-5-7-5-12-3 2-6 5-6 9-1-1-2-2-2-4-2 2-3 4-3 7 0 4 4 7 9 7z"/>',
        warn: '<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18h.01"/>',
        refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
        chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
        map: '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
    };

    function icon(name, cls = '') {
        return `<svg class="ico ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`;
    }

    function bar(pct, cls = '') {
        const v = Math.max(0, Math.min(100, Number(pct) || 0));
        const tone = cls || (v < 25 ? 'bad' : v < 50 ? 'warn' : 'good');
        return `<span class="bar ${tone}"><i style="width:${v}%"></i></span>`;
    }

    function ring(pct, label, size = 48) {
        const r = size / 2 - 4;
        const c = 2 * Math.PI * r;
        const v = Math.max(0, Math.min(1, Number(pct) || 0));
        return `<span class="ring" style="width:${size}px;height:${size}px">
            <svg viewBox="0 0 ${size} ${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="track"/>
            <circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="fill" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - v)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>
            <b>${esc(label)}</b></span>`;
    }

    function spark(values, { w = 280, h = 64, cls = '' } = {}) {
        const list = values.length ? values : [0];
        const max = Math.max(1, ...list);
        const step = list.length > 1 ? w / (list.length - 1) : w;
        const pts = list.map((v, i) => `${(i * step).toFixed(1)},${(h - 4 - (v / max) * (h - 10)).toFixed(1)}`);
        const area = `0,${h} ${pts.join(' ')} ${((list.length - 1) * step).toFixed(1)},${h}`;
        return `<svg class="spark ${cls}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
            <polygon points="${area}" class="area"/><polyline points="${pts.join(' ')}" class="line"/></svg>`;
    }

    function days(rows, key, count = 14) {
        const map = new Map((rows || []).map((r) => [r.day, Number(r[key]) || 0]));
        const out = [];
        const now = new Date();
        for (let i = count - 1; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
            out.push({ day: k, value: map.get(k) || 0, label: d.toLocaleDateString('en-GB', { weekday: 'short' }) });
        }
        return out;
    }

    function columns(series, { h = 120 } = {}) {
        const max = Math.max(1, ...series.map((s) => s.value));
        return `<div class="columns" style="height:${h}px">${series.map((s) =>
            `<div class="col" title="${esc(s.day)}: ${esc(money(s.value))}"><i style="height:${Math.max(2, (s.value / max) * 100)}%"></i><span>${esc(s.label.slice(0, 2))}</span></div>`).join('')}</div>`;
    }

    return { RES, state, post, rpc, fix, esc, money, num, dist, metres, clock, ago, h, $, $$, toast, result, ask, countUp, icon, bar, ring, spark, days, columns };
})();
