XS.Paths = (() => {
    const cache = new Map();
    const pending = new Set();
    const listeners = new Set();
    const reported = new Set();

    const key = (points) => points.map((p) => `${Math.round(p.x)},${Math.round(p.y)}`).join(';');

    function get(points) {
        if (!points || points.length < 2) return null;
        return cache.get(key(points)) || null;
    }

    function store(item) {
        if (!item || !item.key) return;
        pending.delete(item.key);
        const path = Array.isArray(item.path) && item.path.length > 1
            ? { line: item.path.map(([x, y]) => ({ x, y })), meters: Number(item.meters) || 0 }
            : false;
        cache.set(item.key, path);
        listeners.forEach((fn) => fn(item.key, path));
    }

    async function want(list) {
        const ask = [];
        for (const r of list) {
            if (!r.points || r.points.length < 2) continue;
            const k = key(r.points);
            const tag = r.report && r.route && r.spot ? `${r.route}:${r.spot}:${k}` : null;
            const report = !!tag && !reported.has(tag) && !!cache.get(k);
            if (pending.has(k) || (cache.has(k) && !report)) continue;
            if (tag && cache.get(k)) reported.add(tag);
            pending.add(k);
            ask.push({
                key: k, route: r.route, spot: r.spot, report: !!r.report, label: r.label,
                points: r.points.map((p) => ({ x: p.x, y: p.y, z: p.z })),
            });
        }
        if (!ask.length) return;
        const found = await XS.post('paths', { routes: ask });
        (Array.isArray(found) ? found : []).forEach(store);
    }

    function on(fn) {
        listeners.add(fn);
    }

    function reset() {
        pending.clear();
    }

    const minutes = (km) => Math.max(2, Math.floor(km / 55 * 60 + 2.5));

    return { key, get, store, want, on, reset, minutes };
})();
