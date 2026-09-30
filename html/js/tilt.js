XS.Tilt = (() => {
    const WORLD = { minX: -4140, maxX: 4860, minY: -5100, maxY: 8400 };
    const IMG = { w: 2048, h: 3072, tile: 512, z: 3 };
    const PLANE = 1500;
    const NS = 'http://www.w3.org/2000/svg';

    const toPx = (x, y) => [
        ((x - WORLD.minX) / (WORLD.maxX - WORLD.minX)) * IMG.w,
        ((WORLD.maxY - y) / (WORLD.maxY - WORLD.minY)) * IMG.h,
    ];

    function create(host) {
        host.innerHTML = `
            <div class="scene"><div class="plane"><div class="world"></div></div></div>
            <div class="mapfade"></div>`;
        const plane = host.querySelector('.plane');
        const world = host.querySelector('.world');
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
        svg.innerHTML = `<defs>
            <linearGradient id="routeGrad" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#38d9ff"/><stop offset="1" stop-color="#8f7dff"/></linearGradient>
            <filter id="routeGlow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter></defs>
            <g class="others"></g><g class="chosen"></g><g class="marks"></g>`;
        world.appendChild(svg);

        let scale = 1;
        let routes = [];
        let selected = null;
        const anchors = {};

        function view(cx, cy, unitsWide) {
            const widthPx = (unitsWide / (WORLD.maxX - WORLD.minX)) * IMG.w;
            scale = PLANE / widthPx;
            world.style.transform = `translate(${PLANE / 2 - cx * scale}px, ${PLANE / 2 - cy * scale}px) scale(${scale})`;
        }

        function path(points) {
            return points.map((p, i) => {
                const [x, y] = toPx(p.x, p.y);
                return `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`;
            }).join(' ');
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
            const unitsWide = Math.max(2600, (spanPx / IMG.w) * (WORLD.maxX - WORLD.minX) * 1.9);
            view((minX + maxX) / 2, (minY + maxY) / 2 + spanPx * 0.08, unitsWide);
        }

        function draw(still) {
            const others = svg.querySelector('.others');
            const chosen = svg.querySelector('.chosen');
            const marks = svg.querySelector('.marks');
            others.innerHTML = '';
            chosen.innerHTML = '';
            marks.innerHTML = '';

            const w = (n) => (n / scale).toFixed(2);

            for (const route of routes) {
                if (route.id === selected) continue;
                others.appendChild(el('path', { d: path(route.line || route.points), class: 'other', 'stroke-width': w(4), 'stroke-dasharray': `${w(12)} ${w(10)}` }));
            }

            const pick = routes.find((r) => r.id === selected);
            if (pick) {
                const d = path(pick.line || pick.points);
                chosen.appendChild(el('path', { d, class: 'glow', 'stroke-width': w(22) }));
                const main = el('path', { d, class: `main${pick.illegal ? ' illegal' : ''}`, 'stroke-width': w(10) });
                chosen.appendChild(main);
                const len = main.getTotalLength();
                main.style.setProperty('--len', len);
                if (still) {
                    main.style.animation = 'none';
                    main.style.strokeDashoffset = '0';
                }

                const first = pick.points[0];
                const last = pick.points[pick.points.length - 1];
                const [sx, sy] = toPx(first.x, first.y);
                const [ex, ey] = toPx(last.x, last.y);
                marks.appendChild(el('circle', { cx: sx, cy: sy, r: w(22), fill: '#38d9ff', opacity: '.25' }));
                marks.appendChild(el('circle', { cx: sx, cy: sy, r: w(11), fill: '#e9fbff', stroke: '#38d9ff', 'stroke-width': w(5) }));
                pick.points.slice(1, -1).forEach((p) => {
                    const [mx, my] = toPx(p.x, p.y);
                    marks.appendChild(el('circle', { cx: mx, cy: my, r: w(8), fill: '#0b1220', stroke: '#e9eefb', 'stroke-width': w(4) }));
                });
                const end = el('circle', { cx: ex, cy: ey, r: w(14), fill: pick.illegal ? '#ff5d6c' : '#8f7dff', stroke: '#fff', 'stroke-width': w(5) });
                marks.appendChild(end);
                anchors.end = end;
            } else {
                anchors.end = null;
            }
        }

        function show(list, id, fallback) {
            routes = (list || []).filter((r) => r.points && r.points.length > 1);
            selected = id;
            const pick = routes.find((r) => r.id === id);
            if (pick) frame(pick.line || pick.points);
            else if (fallback) {
                const [cx, cy] = toPx(fallback.x, fallback.y);
                view(cx, cy, 4200);
            }
            draw();
        }

        function select(id) {
            selected = id;
            const pick = routes.find((r) => r.id === id);
            if (pick) frame(pick.line || pick.points);
            draw();
        }

        function update(list) {
            const before = routes.find((r) => r.id === selected);
            routes = (list || []).filter((r) => r.points && r.points.length > 1);
            const after = routes.find((r) => r.id === selected);
            draw(!!before && !!after && before.line === after.line);
        }

        function anchor() {
            const node = anchors.end;
            if (!node) return null;
            const r = node.getBoundingClientRect();
            const h = host.getBoundingClientRect();
            const s = host.offsetWidth ? h.width / host.offsetWidth : 1;
            return { x: (r.left + r.width / 2 - h.left) / s, y: (r.top - h.top) / s };
        }

        return { show, select, update, anchor, world };
    }

    return { create };
})();
