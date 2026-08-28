// ─────────────────────────────────────────────────────────────
// Route Map — the real one.
//
// This used to be a hand-drawn SVG of the Los Santos basin. It looked the
// part, but it was an approximation: contracts landed in "visually plausible"
// districts rather than where they actually are, and anything outside the
// basin had nowhere to go at all.
//
// It is now the same satellite tile map the MDT and the admin panel use —
// one look across the whole line, real positions, and the full state instead
// of one corner of it. Leaflet is vendored (BSD-2) because NUI has no
// reliable internet; the tile pyramid ships in assets/maps/tiles.
//
// The public surface is unchanged on purpose: baseMarkup / update /
// updatePlayerOnly / resetView, exactly what app.js already calls. Everything
// behind those four names was replaced.
// ─────────────────────────────────────────────────────────────
const CipherMap = (() => {
    const MAP = {
        imageW: 4096,
        imageH: 6144,
        tileSize: 512,
        nativeZoom: 4,
        maxZoom: 6,
        // The GTA world rectangle the render covers — same calibration as the
        // MDT. If pins sit slightly off, nudge here.
        world: { minX: -3900, maxX: 4300, minY: -4500, maxY: 8100 },
    };

    let _map = null;
    let _routeLayer = null;
    let _pinLayer = null;
    let _playerMarker = null;
    let _fitted = false;

    // Some payloads carry a point directly ({x, y}), others nest it under
    // .coords — stations do, contracts do not. One accessor absorbs both, and
    // a missing point returns null rather than becoming LatLng(NaN, NaN) and
    // taking the whole tab down.
    function pt(o) {
        const c = o && (o.coords || o);
        return (c && typeof c.x === 'number' && typeof c.y === 'number') ? c : null;
    }

    function worldToLatLng(wx, wy) {
        const W = MAP.world;
        const px = ((wx - W.minX) / (W.maxX - W.minX)) * MAP.imageW;
        const py = ((W.maxY - wy) / (W.maxY - W.minY)) * MAP.imageH;
        return _map.unproject([px, py], MAP.nativeZoom);
    }

    function baseMarkup() {
        // One container Leaflet owns. Recreating it on every paint would
        // destroy the map, so update() initialises lazily and only once.
        return '<div id="map-leaflet" style="position:absolute;inset:0;border-radius:inherit;overflow:hidden;background:#0a0e14;"></div>';
    }

    function ensureMap(root) {
        const el = root.querySelector('#map-leaflet');
        if (!el) return false;
        if (_map && _map.getContainer() !== el) {
            // The panel was re-rendered and the old container is gone.
            _map.remove();
            _map = null;
            _fitted = false;
        }
        if (_map) return true;
        if (typeof L === 'undefined') {
            el.innerHTML = '<div style="padding:32px;text-align:center;color:var(--ink-dim,#889);">Map library missing — check vendor/leaflet is in the resource.</div>';
            return false;
        }

        _map = L.map(el, {
            crs: L.CRS.Simple,
            minZoom: 1,
            maxZoom: MAP.maxZoom,
            zoomControl: true,
            attributionControl: false,
            zoomSnap: 0.25,
            wheelPxPerZoomLevel: 90,
        });

        const sw = _map.unproject([0, MAP.imageH], MAP.nativeZoom);
        const ne = _map.unproject([MAP.imageW, 0], MAP.nativeZoom);
        const bounds = new L.LatLngBounds(sw, ne);

        L.tileLayer('assets/maps/tiles/{z}_{x}_{y}.webp', {
            tileSize: MAP.tileSize,
            minZoom: 0,
            maxZoom: MAP.maxZoom,
            maxNativeZoom: MAP.nativeZoom,
            noWrap: true,
            bounds,
        }).addTo(_map);

        _map.setMaxBounds(bounds.pad(0.1));
        _map.fitBounds(bounds);

        _routeLayer = L.layerGroup().addTo(_map);
        _pinLayer = L.layerGroup().addTo(_map);

        // The container is often display:none at init; measure again once
        // it is actually on screen.
        setTimeout(() => _map && _map.invalidateSize(), 60);
        return true;
    }

    // ── Markers ──────────────────────────────────────────────────────────────

    function pinIcon(kind, opts = {}) {
        const colors = {
            contract: 'var(--signal, #f5a524)',
            hot:      '#ff5a5f',
            locked:   '#5c626b',
            depot:    '#4c9aff',
            station:  '#30d158',
            start:    '#30d158',
            stop:     'var(--signal, #f5a524)',
            end:      '#4c9aff',
        };
        const c = colors[kind] || colors.contract;
        const size = kind === 'station' ? 10 : 16;
        const badge = opts.badge
            ? `<div style="position:absolute;top:-7px;right:-7px;background:${c};color:#0a0e14;` +
              `border-radius:50%;width:14px;height:14px;font:700 9px/14px Inter,sans-serif;text-align:center;">${opts.badge}</div>`
            : '';

        return L.divIcon({
            className: '',
            iconSize: [size + 4, size + 4],
            iconAnchor: [(size + 4) / 2, (size + 4) / 2],
            html: `<div style="position:relative;width:${size}px;height:${size}px;border-radius:50%;` +
                  `background:${c};border:2px solid rgba(255,255,255,.8);box-shadow:0 0 8px ${c};` +
                  `${opts.selected ? 'outline:2px solid #fff;outline-offset:2px;' : ''}` +
                  `${opts.dim ? 'opacity:.45;' : ''}">${badge}</div>`,
        });
    }

    function line(points, opts) {
        return L.polyline(points, Object.assign({
            color: 'var(--signal, #f5a524)', weight: 3, opacity: 0.85, dashArray: '6 8',
        }, opts));
    }

    // ── The public surface app.js already uses ───────────────────────────────

    function update(root, state) {
        if (!ensureMap(root)) return;

        _routeLayer.clearLayers();
        _pinLayer.clearLayers();

        const depot = state.depot;
        const selected = (state.contracts || []).find((c) => c.id === state.selectedId);
        const job = state.activeJob;

        const depotPt = pt(depot);
        if (depotPt) {
            L.marker(worldToLatLng(depotPt.x, depotPt.y), { icon: pinIcon('depot') })
                .bindTooltip('Depot', { direction: 'top' })
                .addTo(_pinLayer);
        }

        for (const s of state.stations || []) {
            const c = pt(s);
            if (!c) continue;
            L.marker(worldToLatLng(c.x, c.y), { icon: pinIcon('station') })
                .bindTooltip(s.label || 'Fuel', { direction: 'top' })
                .addTo(_pinLayer);
        }

        for (const c of state.contracts || []) {
            const kind = c.hot ? 'hot' : 'contract';
            (c.stops || []).forEach((stop, i) => {
                const sp = pt(stop);
                if (!sp) return;
                const m = L.marker(worldToLatLng(sp.x, sp.y), {
                    icon: pinIcon(kind, {
                        selected: c === selected,
                        dim: c.unlocked === false,
                        badge: (c.stops.length > 1) ? (i + 1) : null,
                    }),
                });
                m.bindTooltip(c.label || c.name || 'Contract', { direction: 'top' });
                m.on('click', () => state.onSelect && state.onSelect(c.id));
                m.addTo(_pinLayer);
            });
        }

        // While a run is live its route takes over — drawing the planning
        // route underneath it as well would be two lines saying different
        // things.
        if (job && job.stops && job.stops.length) {
            const pts = [];
            const ts = pt(job.trailerSpawn);
            if (ts) pts.push(worldToLatLng(ts.x, ts.y));
            job.stops.forEach((s) => { const c = pt(s); if (c) pts.push(worldToLatLng(c.x, c.y)); });
            const home = pt(job.truckSpawn) || depotPt;
            if (home) pts.push(worldToLatLng(home.x, home.y));
            line(pts, { dashArray: null }).addTo(_routeLayer);

            if (ts) {
                L.marker(worldToLatLng(ts.x, ts.y), { icon: pinIcon('start') })
                    .bindTooltip('Trailer', { direction: 'top' }).addTo(_routeLayer);
            }
        } else if (selected && selected.stops && selected.stops.length) {
            const pts = [];
            if (depotPt) pts.push(worldToLatLng(depotPt.x, depotPt.y));
            selected.stops.forEach((s) => { const c = pt(s); if (c) pts.push(worldToLatLng(c.x, c.y)); });
            if (depotPt) pts.push(worldToLatLng(depotPt.x, depotPt.y));
            line(pts).addTo(_routeLayer);
        }

        updatePlayerOnly(root, state.player);

        // First real paint frames the action rather than the whole state.
        if (!_fitted && _pinLayer.getLayers().length) {
            const group = L.featureGroup(_pinLayer.getLayers());
            _map.fitBounds(group.getBounds().pad(0.35), { maxZoom: 5 });
            _fitted = true;
        }
    }

    function updatePlayerOnly(root, player) {
        const c = pt(player);
        if (!_map || !c) return;
        const pos = worldToLatLng(c.x, c.y);

        if (_playerMarker && _map.hasLayer(_playerMarker)) {
            _playerMarker.setLatLng(pos);
        } else {
            _playerMarker = L.marker(pos, {
                icon: L.divIcon({
                    className: '',
                    iconSize: [16, 16],
                    iconAnchor: [8, 8],
                    html: '<div style="width:12px;height:12px;border-radius:50%;background:#fff;' +
                          'border:3px solid var(--signal, #f5a524);box-shadow:0 0 10px var(--signal, #f5a524);"></div>',
                }),
                zIndexOffset: 1000,
            }).bindTooltip('You', { direction: 'top' }).addTo(_map);
        }
    }

    function resetView() {
        if (!_map) return;
        const sw = _map.unproject([0, MAP.imageH], MAP.nativeZoom);
        const ne = _map.unproject([MAP.imageW, 0], MAP.nativeZoom);
        _map.fitBounds(new L.LatLngBounds(sw, ne));
    }

    // BOUNDS/W/H stay exported because app.js may reference them; they now
    // describe the world rectangle rather than SVG units.
    return {
        project: worldToLatLng,
        baseMarkup, update, updatePlayerOnly, resetView,
        BOUNDS: MAP.world, W: MAP.imageW, H: MAP.imageH,
    };
})();
