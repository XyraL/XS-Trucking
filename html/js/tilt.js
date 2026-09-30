XS.Tilt = (() => {
    const WORLD = { minX: -4140, maxX: 4860, minY: -5100, maxY: 8400 };
    const IMG = { w: 2048, h: 3072, tile: 512, z: 3 };
    const PLANE = 1500;
    const NS = 'http://www.w3.org/2000/svg';
    const SPREAD_METRES = 70;
    const MIN_UNITS = 1800;
    const MAX_UNITS = 32000;
    const SPREAD_PX = 16;

    const toPx = (x, y) => [
        ((x - WORLD.minX) / (WORLD.maxX - WORLD.minX)) * IMG.w,
        ((WORLD.maxY - y) / (WORLD.maxY - WORLD.minY)) * IMG.h,
    ];

    function create(host, opts = {}) {
        host.innerHTML = `
            <div class="scene"><div class="plane"><div class="world"></div></div></div>
            <div class="mapfade"></div><div class="pins"></div>`;
        const world = host.querySelector('.world');
        const layer = host.querySelector('.pins');
        world.style.cssText = `position:absolute;left:0;top:0;width:${IMG.w}px;height:${IMG.h}px;transform-origin:0 0;transition:transform 1.1s cubic-bezier(.2,.8,.2,1);`;

        for (let x = 0; x < IMG.w / IMG.tile; x++) {
            for (let y = 0; y < IMG.h / IMG.tile; y++) {
                const img = new Image();
                img.src = `assets/maps/tiles/${IMG.z}_${x}_${y}.webp`;
                img.style.cssText = `left:${x * IMG.tile}px;top:${y * IMG.tile}px;`;
                world.appendChild(img);
            }
        }

        const svg = document.createElementNS(NS, 'svg');
        svg.setAttribute('viewBox', `0 0 ${IMG.w} ${IMG.h}`);
        svg.style.cssText = `position:absolute;left:0;top:0;width:${IMG.w}px;height:${IMG.h}px;overflow:visible;`;
        svg.innerHTML = '<g class="rings"></g><g class="anchors"></g><g class="probe"></g>';
        world.appendChild(svg);

        let scale = 1;
        let markers = [];
        let raf = 0;
        const cam = { cx: IMG.w / 2, cy: IMG.h / 2, units: 4200 };

        function view(cx, cy, unitsWide) {
            cam.cx = cx;
            cam.cy = cy;
            cam.units = unitsWide;
            const widthPx = (unitsWide / (WORLD.maxX - WORLD.minX)) * IMG.w;
            scale = PLANE / widthPx;
            world.style.transform = `translate(${PLANE / 2 - cx * scale}px, ${PLANE / 2 - cy * scale}px) scale(${scale})`;
        }

        function band() {
            const pad = { top: 140, bottom: 200, side: 120, ...(opts.pad || {}) };
            return { left: pad.side, right: host.offsetWidth - pad.side, top: pad.top, bottom: host.offsetHeight - pad.bottom };
        }

        function spot(nodes) {
            const box = host.getBoundingClientRect();
            const s = host.offsetWidth ? box.width / host.offsetWidth : 1;
            const out = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
            for (const node of nodes) {
                const r = node.getBoundingClientRect();
                const x = (r.left + r.width / 2 - box.left) / s;
                const y = (r.top + r.height / 2 - box.top) / s;
                out.minX = Math.min(out.minX, x); out.maxX = Math.max(out.maxX, x);
                out.minY = Math.min(out.minY, y); out.maxY = Math.max(out.maxY, y);
            }
            return out;
        }

        function el(tag, attrs) {
            const node = document.createElementNS(NS, tag);
            for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
            return node;
        }

        function frame(points) {
            let minX = Infinity; let minY = Infinity; let maxX = -Infinity; let maxY = -Infinity;
            for (const p of points) {
                const [x, y] = toPx(p.x, p.y);
                minX = Math.min(minX, x); maxX = Math.max(maxX, x);
                minY = Math.min(minY, y); maxY = Math.max(maxY, y);
            }
            const spanPx = Math.max(maxX - minX, (maxY - minY) * 0.9, 160);
            const unitsWide = Math.max(MIN_UNITS, (spanPx / IMG.w) * (WORLD.maxX - WORLD.minX) * 1.9);
            const from = world.style.transform;
            world.style.transition = 'none';
            view((minX + maxX) / 2, (minY + maxY) / 2, unitsWide);

            const probe = svg.querySelector('.probe');
            probe.innerHTML = '';
            const nodes = points.map((p) => {
                const [x, y] = toPx(p.x, p.y);
                const node = el('circle', { cx: x, cy: y, r: 0.5, fill: 'none' });
                probe.appendChild(node);
                return node;
            });

            for (let i = 0; i < 6; i++) {
                const seen = spot(nodes);
                const b = band();
                const wide = Math.max(1, seen.maxX - seen.minX);
                const tall = Math.max(1, seen.maxY - seen.minY);
                const fitBy = Math.min(Math.max(Math.min((b.right - b.left) / wide, (b.bottom - b.top) / tall), 0.6), 1.5);
                const units = Math.min(MAX_UNITS, Math.max(MIN_UNITS, cam.units / fitBy));
                const dx = (b.left + b.right) / 2 - (seen.minX + seen.maxX) / 2;
                const dy = (b.top + b.bottom) / 2 - (seen.minY + seen.maxY) / 2;
                view(cam.cx - dx / scale, cam.cy - dy / (scale * 0.6), units);
            }

            probe.innerHTML = '';
            const to = world.style.transform;
            world.style.transform = from;
            void world.offsetWidth;
            world.style.transition = 'transform 1.1s cubic-bezier(.2,.8,.2,1)';
            world.style.transform = to;
        }

        function spread(list) {
            const groups = [];
            for (const m of list) {
                const group = groups.find((g) => Math.hypot(g.x - m.x, g.y - m.y) < SPREAD_METRES);
                if (group) group.items.push(m);
                else groups.push({ x: m.x, y: m.y, items: [m] });
            }
            for (const group of groups) {
                const n = group.items.length;
                group.items.forEach((m, i) => {
                    const a = (i / n) * Math.PI * 2 - Math.PI / 2;
                    m.dx = n > 1 ? Math.cos(a) * SPREAD_PX : 0;
                    m.dy = n > 1 ? Math.sin(a) * SPREAD_PX : 0;
                });
            }
        }

        function face(m) {
            if (m.number != null) return `<b>${m.number}</b>`;
            if (m.icon) return `<em>${XS.icon(m.icon)}</em>`;
            return '<i></i>';
        }

        function render() {
            const rings = svg.querySelector('.rings');
            const anchors = svg.querySelector('.anchors');
            rings.innerHTML = '';
            anchors.innerHTML = '';
            layer.innerHTML = '';
            const w = (n) => (n / scale).toFixed(2);

            for (const m of markers) {
                const [x, y] = toPx(m.x, m.y);
                const tone = m.tone || 'cyan';
                if (m.active) rings.appendChild(el('circle', { cx: x, cy: y, r: w(30), class: `ring pulse ${tone}`, 'stroke-width': w(3) }));
                rings.appendChild(el('circle', { cx: x, cy: y, r: w(m.active ? 15 : 9), class: `ring ${tone}${m.done ? ' done' : ''}`, 'stroke-width': w(2) }));
                m.anchor = el('circle', { cx: x, cy: y, r: w(0.5), fill: 'none' });
                anchors.appendChild(m.anchor);

                const pin = document.createElement(m.pick != null ? 'button' : 'div');
                pin.className = ['pin', m.type || 'load', tone, m.active ? 'on' : '', m.done ? 'done' : '', m.bubble ? 'lead' : ''].filter(Boolean).join(' ');
                if (m.pick != null) pin.dataset.pin = m.pick;
                pin.innerHTML = `${face(m)}${m.label ? `<span class="tip">${XS.esc(m.label)}</span>` : ''}`;
                layer.appendChild(pin);
                m.pin = pin;
            }
            place();
        }

        function place() {
            const box = host.getBoundingClientRect();
            const s = host.offsetWidth ? box.width / host.offsetWidth : 1;
            const wide = host.offsetWidth;
            const tall = host.offsetHeight;
            for (const m of markers) {
                if (!m.anchor || !m.pin) continue;
                const r = m.anchor.getBoundingClientRect();
                const x = (r.left + r.width / 2 - box.left) / s + (m.dx || 0);
                const y = (r.top + r.height / 2 - box.top) / s + (m.dy || 0);
                m.at = { x, y };
                m.pin.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
                m.pin.classList.toggle('off', x < -30 || y < -30 || x > wide + 30 || y > tall + 30);
            }
            if (opts.onMove) opts.onMove();
        }

        function follow(ms = 1300) {
            cancelAnimationFrame(raf);
            const until = performance.now() + ms;
            const tick = () => {
                if (!host.isConnected) return;
                place();
                if (performance.now() < until) raf = requestAnimationFrame(tick);
            };
            tick();
        }

        function show(list, focus) {
            markers = list || [];
            spread(markers);
            const points = focus && focus.length ? focus : markers;
            if (points.length) frame(points);
            render();
            follow();
        }

        function update(list) {
            markers = list || [];
            spread(markers);
            render();
            follow(200);
        }

        function anchor() {
            const m = markers.find((x) => x.bubble) || markers.find((x) => x.active);
            if (!m || !m.at || (m.pin && m.pin.classList.contains('off'))) return null;
            return { x: m.at.x, y: m.at.y };
        }

        layer.addEventListener('click', (e) => {
            const pin = e.target.closest('[data-pin]');
            if (pin && opts.onPick) opts.onPick(Number(pin.dataset.pin));
        });

        return { show, update, anchor, world };
    }

    return { create };
})();
