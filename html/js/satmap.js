XS.SatMap = (() => {
    const MAP = {
        imageW: 4096,
        imageH: 6144,
        tileSize: 512,
        nativeZoom: 4,
        maxZoom: 6,
        world: { minX: -4140, maxX: 4860, minY: -5100, maxY: 8400 },
    };

    function create(el) {
        if (typeof L === 'undefined') {
            el.innerHTML = '<div class="empty">The map library is missing from html/vendor/leaflet.</div>';
            return null;
        }

        const map = L.map(el, {
            crs: L.CRS.Simple,
            minZoom: 1,
            maxZoom: MAP.maxZoom,
            zoomControl: true,
            attributionControl: false,
            zoomSnap: 0.25,
            wheelPxPerZoomLevel: 90,
        });

        const sw = map.unproject([0, MAP.imageH], MAP.nativeZoom);
        const ne = map.unproject([MAP.imageW, 0], MAP.nativeZoom);
        const bounds = new L.LatLngBounds(sw, ne);

        L.tileLayer('assets/maps/tiles/{z}_{x}_{y}.webp', {
            tileSize: MAP.tileSize,
            minZoom: 0,
            maxZoom: MAP.maxZoom,
            maxNativeZoom: MAP.nativeZoom,
            noWrap: true,
            bounds,
        }).addTo(map);

        map.setMaxBounds(bounds.pad(0.1));
        map.fitBounds(bounds);

        const layer = L.layerGroup().addTo(map);

        function toLatLng(x, y) {
            const W = MAP.world;
            const px = ((x - W.minX) / (W.maxX - W.minX)) * MAP.imageW;
            const py = ((W.maxY - y) / (W.maxY - W.minY)) * MAP.imageH;
            return map.unproject([px, py], MAP.nativeZoom);
        }

        function marker(p, colour, label, size = 14) {
            if (!p) return null;
            const icon = L.divIcon({
                className: '',
                html: `<div class="mk" style="width:${size}px;height:${size}px;background:${colour}"></div>`,
                iconSize: [size, size],
                iconAnchor: [size / 2, size / 2],
            });
            const m = L.marker(toLatLng(p.x, p.y), { icon, keyboard: false });
            if (label) m.bindTooltip(label, { direction: 'top', offset: [0, -8] });
            m.addTo(layer);
            return m;
        }

        function line(points, colour, dashed) {
            const list = (points || []).filter(Boolean);
            if (list.length < 2) return null;
            return L.polyline(list.map((p) => toLatLng(p.x, p.y)), {
                color: colour, weight: 4, opacity: 0.9, dashArray: dashed ? '8 8' : null,
            }).addTo(layer);
        }

        function fit(points) {
            const list = (points || []).filter(Boolean);
            if (!list.length) return;
            if (list.length === 1) {
                map.setView(toLatLng(list[0].x, list[0].y), 4);
                return;
            }
            map.fitBounds(L.latLngBounds(list.map((p) => toLatLng(p.x, p.y))).pad(0.35), { maxZoom: 5 });
        }

        function clear() { layer.clearLayers(); }

        setTimeout(() => map.invalidateSize(), 80);
        return { map, marker, line, fit, clear, invalidate: () => map.invalidateSize() };
    }

    return { create };
})();
