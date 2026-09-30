XS.Builder = (() => {
    let root = null;
    let data = null;
    let sel = null;
    let draft = null;
    let dirty = false;
    let map = null;
    let player = null;

    const clone = (v) => JSON.parse(JSON.stringify(v ?? null));
    const pt = (p) => (p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : '—');

    function spotName(id) {
        const s = data.spots.find((x) => x.id === id);
        return s ? s.name : 'Any spot';
    }

    function typeInfo(id) {
        return data.meta.types.find((t) => t.id === id) || data.meta.types[0];
    }

    function blankSpot() {
        return {
            name: 'New trucking spot', enabled: true, blip: { show: true, sprite: 477, colour: 5, scale: 0.8 },
            laptop: null, truckBays: [], trailerBays: [], returns: [], truckModel: '',
        };
    }

    function blankRoute(spotId) {
        return {
            spot: spotId ?? (data.spots[0] ? data.spots[0].id : 0), label: 'New route', cargo: '', type: 'dryvan', model: '',
            weight: 12, pickup: null, stops: [], pay: 400, xp: 50, level: 1, cert: null, timer: 0, convoy: null,
            escorts: 0, illegal: false, fragile: false, enabled: true,
        };
    }

    function list() {
        const spots = data.spots.map((s) => {
            const routes = data.routes.filter((r) => r.spot === s.id).length;
            const on = sel && sel.kind === 'spot' && sel.id === s.id;
            return `<div class="item click${on ? ' on' : ''}" data-sel="spot:${s.id}">
                <div class="grow"><div class="ttl">${XS.esc(s.name)}</div><div class="sub">${s.truckBays.length} truck bays · ${s.trailerBays.length} trailer bays · ${routes} routes</div></div>
                ${s.enabled ? '' : '<span class="chip">Off</span>'}</div>`;
        }).join('');

        const routes = data.routes.map((r) => {
            const on = sel && sel.kind === 'route' && sel.id === r.id;
            const kind = typeInfo(r.type);
            return `<div class="item click${on ? ' on' : ''}" data-sel="route:${r.id}">
                <div class="grow"><div class="ttl">${XS.esc(r.label)}</div><div class="sub">${XS.esc(kind.label)} · ${XS.money(r.pay)} · ${XS.esc(spotName(r.spot))}</div></div>
                ${r.illegal ? '<span class="chip red">Illegal</span>' : ''}${r.enabled ? '' : '<span class="chip">Off</span>'}</div>`;
        }).join('');

        return `
            <div class="row between"><div class="kicker">Trucking spots</div><button class="btn xs" data-new="spot">${XS.icon('plus')}New</button></div>
            <div class="list">${spots || '<div class="dim">No spots yet.</div>'}</div>
            <div class="row between" style="margin-top:6px"><div class="kicker">Routes</div>
                <div class="row" style="gap:6px"><button class="btn xs" data-quick>${XS.icon('spark')}Quick</button><button class="btn xs" data-new="route">${XS.icon('plus')}New</button></div></div>
            <div class="list">${routes || '<div class="dim">No routes yet.</div>'}</div>`;
    }

    function points(key, label, max = 12) {
        const arr = draft[key] || [];
        return `<div class="section">
            <div class="row between"><h3>${label}</h3><span class="dim">${arr.length}/${max}</span></div>
            <div class="points">${arr.map((p, i) => `<div class="pt"><span class="n">${i + 1}</span><span class="mono grow">${pt(p)}</span>
                <button class="btn xs" data-tp="${key}:${i}" title="Go there">${XS.icon('pin')}</button>
                <button class="btn xs" data-move="${key}:${i}">Move</button>
                <button class="btn xs" data-del="${key}:${i}">${XS.icon('trash')}</button></div>`).join('') || '<div class="dim">None yet.</div>'}</div>
            ${arr.length < max ? `<button class="btn sm" data-add="${key}">${XS.icon('plus')}Add one where you place it</button>` : ''}
        </div>`;
    }

    function spotForm() {
        const d = draft;
        const prop = d.laptop && d.laptop.prop;
        return `
            <div class="section"><div class="row between"><h2>${d.id ? 'Edit spot' : 'New spot'}</h2>
                <label class="check"><input type="checkbox" data-f="enabled" ${d.enabled ? 'checked' : ''}><i></i>Open</label></div>
                <div class="fgrid">
                    <div class="fcell"><span class="label">Name</span><input class="field" data-f="name" value="${XS.esc(d.name)}" maxlength="48"></div>
                    <div class="fcell"><span class="label">Depot truck</span><input class="field" data-f="truckModel" value="${XS.esc(d.truckModel || '')}" placeholder="${XS.esc(data.meta.depotTruck)}"></div>
                </div>
                <div class="fgrid three">
                    <div class="fcell"><span class="label">Blip sprite</span><input class="field" type="number" data-f="blip.sprite" value="${d.blip.sprite}"></div>
                    <div class="fcell"><span class="label">Blip colour</span><input class="field" type="number" data-f="blip.colour" value="${d.blip.colour}"></div>
                    <div class="fcell"><span class="label">Blip size</span><input class="field" type="number" step="0.1" data-f="blip.scale" value="${d.blip.scale}"></div>
                </div>
                <label class="check"><input type="checkbox" data-f="blip.show" ${d.blip.show !== false ? 'checked' : ''}><i></i>Show on the map</label>
            </div>
            <div class="section"><div class="row between"><h3>Laptop</h3><span class="mono dim">${pt(d.laptop)}</span></div>
                <div class="row"><button class="btn sm" data-place="laptop">${XS.icon('pin')}${d.laptop ? 'Move the laptop' : 'Place the laptop'}</button>
                    <label class="check"><input type="checkbox" data-f="laptopProp" ${prop ? 'checked' : ''}><i></i>Put a laptop prop down</label></div>
                ${prop ? `<input class="field sm" data-f="laptop.prop" value="${XS.esc(prop)}">` : '<div class="dim" style="font-size:12px">Use this when the spot already has a computer in the map.</div>'}
            </div>
            ${points('truckBays', 'Truck bays')}
            ${points('trailerBays', 'Trailer bays')}
            ${points('returns', 'Return bays')}
            <div class="dim" style="font-size:12px">Leave return bays empty and trucks come back to the truck bays.</div>`;
    }

    function routeForm() {
        const d = draft;
        const kind = typeInfo(d.type);
        const certDefault = kind.cert ? (data.meta.certs.find((c) => c.id === kind.cert) || {}).label : 'none';
        const certValue = d.cert === false ? 'none' : d.cert || '';
        return `
            <div class="section"><div class="row between"><h2>${d.id ? 'Edit route' : 'New route'}</h2>
                <label class="check"><input type="checkbox" data-f="enabled" ${d.enabled ? 'checked' : ''}><i></i>On the board</label></div>
                <div class="fgrid">
                    <div class="fcell"><span class="label">Name</span><input class="field" data-f="label" value="${XS.esc(d.label)}" maxlength="48"></div>
                    <div class="fcell"><span class="label">Cargo</span><input class="field" data-f="cargo" value="${XS.esc(d.cargo || '')}" placeholder="Steel beams" maxlength="48"></div>
                </div>
                <div class="fgrid three">
                    <div class="fcell"><span class="label">Trailer</span><select class="field" data-f="type">${data.meta.types.map((t) => `<option value="${t.id}" ${t.id === d.type ? 'selected' : ''}>${XS.esc(t.label)}</option>`).join('')}</select></div>
                    <div class="fcell"><span class="label">Trailer model</span><select class="field" data-f="model"><option value="">Any ${XS.esc(kind.label.toLowerCase())}</option>${kind.models.map((m) => `<option value="${m}" ${m === d.model ? 'selected' : ''}>${m}</option>`).join('')}${d.model && !kind.models.includes(d.model) ? `<option value="${XS.esc(d.model)}" selected>${XS.esc(d.model)}</option>` : ''}</select></div>
                    <div class="fcell"><span class="label">Weight (t)</span><input class="field" type="number" data-f="weight" value="${d.weight}"></div>
                </div>
                <div class="fcell"><span class="label">Trucking spot</span><select class="field" data-f="spot"><option value="0" ${d.spot === 0 ? 'selected' : ''}>Every spot</option>${data.spots.map((s) => `<option value="${s.id}" ${s.id === d.spot ? 'selected' : ''}>${XS.esc(s.name)}</option>`).join('')}</select></div>
            </div>
            <div class="section"><div class="row between"><h3>Pickup</h3><label class="check"><input type="checkbox" data-f="hasPickup" ${d.pickup ? 'checked' : ''}><i></i>The trailer waits somewhere else</label></div>
                ${d.pickup ? `<div class="pt"><span class="n">P</span><span class="mono grow">${pt(d.pickup)}</span><button class="btn xs" data-tp="pickup:0">${XS.icon('pin')}</button><button class="btn xs" data-place="pickup">Move</button></div>`
                    : '<div class="dim" style="font-size:12px">Off: the trailer comes out at one of the spot\'s trailer bays.</div>'}
            </div>
            ${points('stops', 'Drop points', 8)}
            <div class="dim" style="font-size:12px">The ghost trailer shows which way it should be parked. Drivers who back in straight get the Dock Master bonus.</div>
            <div class="section"><div class="row between"><h3>Pay</h3><button class="btn sm" data-suggest>${XS.icon('spark')}Suggest from the distance</button></div>
                <div class="fgrid three">
                    <div class="fcell"><span class="label">Pay</span><input class="field" type="number" data-f="pay" value="${d.pay}"></div>
                    <div class="fcell"><span class="label">XP</span><input class="field" type="number" data-f="xp" value="${d.xp}"></div>
                    <div class="fcell"><span class="label">Level</span><input class="field" type="number" min="1" max="${data.meta.maxLevel}" data-f="level" value="${d.level}"></div>
                </div>
                <div class="dim" data-km style="font-size:12px"></div>
            </div>
            <div class="section"><h3>Rules</h3>
                <div class="fgrid">
                    <div class="fcell"><span class="label">Certificate</span><select class="field" data-f="cert">
                        <option value="" ${certValue === '' ? 'selected' : ''}>Trailer default (${XS.esc(certDefault)})</option>
                        <option value="none" ${certValue === 'none' ? 'selected' : ''}>None</option>
                        ${data.meta.certs.map((c) => `<option value="${c.id}" ${certValue === c.id ? 'selected' : ''}>${XS.esc(c.label)}</option>`).join('')}</select></div>
                    <div class="fcell"><span class="label">Timer (seconds, 0 for none)</span><input class="field" type="number" data-f="timer" value="${d.timer}"></div>
                </div>
                <div class="row wrap" style="gap:18px">
                    <label class="check"><input type="checkbox" data-f="fragile" ${d.fragile ? 'checked' : ''}><i></i>Fragile</label>
                    ${data.meta.illegal ? `<label class="check"><input type="checkbox" data-f="illegal" ${d.illegal ? 'checked' : ''}><i></i>Illegal</label>` : ''}
                    ${data.meta.convoy ? `<label class="check"><input type="checkbox" data-f="hasConvoy" ${d.convoy ? 'checked' : ''}><i></i>Convoy</label>` : ''}
                </div>
                <div class="fgrid">
                    ${d.convoy ? `<div class="fcell"><span class="label">Most trucks</span><select class="field" data-f="convoy.max">${[2, 3, 4].filter((n) => n <= data.meta.convoy).map((n) => `<option ${n === d.convoy.max ? 'selected' : ''}>${n}</option>`).join('')}</select></div>` : ''}
                    ${data.meta.escorts ? `<div class="fcell"><span class="label">Escorts</span><select class="field" data-f="escorts">${[0, 1, 2, 3].map((n) => `<option ${n === d.escorts ? 'selected' : ''}>${n}</option>`).join('')}</select></div>` : ''}
                </div>
            </div>`;
    }

    function actions() {
        if (!draft) return '';
        return `<div class="bactions">
            ${draft.id ? `<button class="btn ghost bad" data-remove>${XS.icon('trash')}Delete</button>` : ''}
            ${sel.kind === 'route' && draft.id ? '<button class="btn ghost" data-copy>Duplicate</button>' : ''}
            <span class="grow dim" style="text-align:right">${dirty ? 'Unsaved changes' : ''}</span>
            <button class="btn primary" data-save>${XS.icon('check')}Save</button></div>`;
    }

    function routePoints() {
        if (!draft || sel.kind !== 'route' || !draft.stops.length) return null;
        const spot = data.spots.find((s) => s.id === draft.spot) || data.spots[0];
        const origin = draft.pickup || (spot && spot.trailerBays[0]);
        return origin ? [origin, ...draft.stops] : null;
    }

    function drawMap() {
        if (!map || !draft) return;
        map.clear();
        const all = [];
        if (sel.kind === 'spot') {
            if (draft.laptop) { map.marker(draft.laptop, '#38d9ff', 'Laptop', 16); all.push(draft.laptop); }
            draft.truckBays.forEach((p, i) => { map.marker(p, '#3fe08f', `Truck bay ${i + 1}`); all.push(p); });
            draft.trailerBays.forEach((p, i) => { map.marker(p, '#ffb547', `Trailer bay ${i + 1}`); all.push(p); });
            draft.returns.forEach((p, i) => { map.marker(p, '#8f7dff', `Return bay ${i + 1}`); all.push(p); });
        } else {
            const spot = data.spots.find((s) => s.id === draft.spot) || data.spots[0];
            const origin = draft.pickup || (spot && spot.trailerBays[0]);
            if (spot) {
                map.marker(spot.laptop, '#38d9ff', spot.name, 16);
                all.push(spot.laptop);
            }
            if (draft.pickup) map.marker(draft.pickup, '#ffb547', 'Pickup', 16);
            if (origin) all.push(origin);
            const points = routePoints();
            const known = points && XS.Paths.get(points);
            map.line(known ? known.line : [origin, ...draft.stops], draft.illegal ? '#ff5d6c' : '#38d9ff', false);
            if (points) XS.Paths.want([{ points, route: draft.id, spot: spot && spot.id, report: !!draft.id && !dirty }]);
            draft.stops.forEach((p, i) => { map.marker(p, '#8f7dff', `Drop ${i + 1}`, 16); all.push(p); });
        }
        map.fit(all.length ? all : [player]);
    }

    function paint() {
        root.querySelector('.blist').innerHTML = list();
        const form = root.querySelector('.bform');
        if (!draft) {
            form.innerHTML = `<div class="empty">${XS.icon('map')}<h3>Pick a spot or a route</h3><p>Or make a new one. Quick builds a route from where you place its drop.</p></div>`;
        } else {
            form.innerHTML = (sel.kind === 'spot' ? spotForm() : routeForm()) + actions();
        }
        drawMap();
    }

    function select(kind, id) {
        sel = { kind, id };
        const source = kind === 'spot' ? data.spots.find((s) => s.id === id) : data.routes.find((r) => r.id === id);
        draft = source ? clone(source) : null;
        if (draft && kind === 'spot') draft.truckModel = draft.truckModel || '';
        dirty = false;
        paint();
    }

    function setField(path, value) {
        const parts = path.split('.');
        let node = draft;
        for (let i = 0; i < parts.length - 1; i++) node = node[parts[i]];
        node[parts[parts.length - 1]] = value;
        dirty = true;
    }

    function othersFor(skipKey, skipIndex) {
        const out = [];
        const add = (p, model, label) => { if (p) out.push({ x: p.x, y: p.y, z: p.z, h: p.h, model, label }); };
        if (sel.kind === 'spot') {
            const truck = draft.truckModel || data.meta.depotTruck;
            if (skipKey !== 'laptop') add(draft.laptop, null, 'Laptop');
            draft.truckBays.forEach((p, i) => { if (!(skipKey === 'truckBays' && i === skipIndex)) add(p, truck, `Truck bay ${i + 1}`); });
            draft.trailerBays.forEach((p, i) => { if (!(skipKey === 'trailerBays' && i === skipIndex)) add(p, 'trailers3', `Trailer bay ${i + 1}`); });
            draft.returns.forEach((p, i) => { if (!(skipKey === 'returns' && i === skipIndex)) add(p, truck, `Return ${i + 1}`); });
        } else {
            const model = draft.model || typeInfo(draft.type).models[0];
            draft.stops.forEach((p, i) => { if (!(skipKey === 'stops' && i === skipIndex)) add(p, model, `Drop ${i + 1}`); });
            if (skipKey !== 'pickup') add(draft.pickup, model, 'Pickup');
        }
        return out;
    }

    function previewFor(key) {
        if (key === 'laptop') return draft.laptop && draft.laptop.prop ? draft.laptop.prop : null;
        if (key === 'truckBays' || key === 'returns') return draft.truckModel || data.meta.depotTruck;
        if (key === 'trailerBays') return 'trailers3';
        return draft.model || typeInfo(draft.type).models[0];
    }

    const LABELS = { laptop: 'The laptop', truckBays: 'A truck bay', trailerBays: 'A trailer bay', returns: 'A return bay', stops: 'A drop point', pickup: 'The pickup' };

    async function place(key, index) {
        const current = key === 'laptop' ? draft.laptop : key === 'pickup' ? draft.pickup : index != null ? draft[key][index] : null;
        const origin = current || (await XS.post('here'));
        const point = await XS.post('place', {
            label: LABELS[key] || 'A point', preview: previewFor(key), origin, others: othersFor(key, index),
        });
        if (!point) return false;
        if (key === 'laptop') {
            draft.laptop = { ...point, prop: draft.laptop ? draft.laptop.prop : false };
        } else if (key === 'pickup') {
            draft.pickup = point;
        } else if (index != null) {
            draft[key][index] = point;
        } else {
            draft[key].push(point);
        }
        dirty = true;
        paint();
        return true;
    }

    async function suggest() {
        const points = routePoints();
        const known = points && XS.Paths.get(points);
        const res = await XS.rpc('suggestPay', draft, known ? known.meters : null);
        if (!res.ok || !res.data) return XS.toast('Place a drop point first.', 'error');
        draft.pay = res.data.pay;
        draft.xp = res.data.xp;
        dirty = true;
        paint();
        const km = root.querySelector('[data-km]');
        if (km) km.textContent = `About ${XS.dist(res.data.km)} of driving.`;
    }

    function payload() {
        const d = clone(draft);
        if (sel.kind === 'spot') {
            if (!d.truckModel) delete d.truckModel;
        } else {
            if (d.cert === 'none') d.cert = false;
            if (d.cert === '' || d.cert === null) delete d.cert;
            d.spot = Number(d.spot) || 0;
        }
        return d;
    }

    async function save() {
        const res = await XS.rpc(sel.kind === 'spot' ? 'saveSpot' : 'saveRoute', payload());
        if (!res.ok) return XS.toast(res.error, 'error');
        data = res.data.data;
        XS.toast('Saved.', 'success');
        select(sel.kind, res.data.id);
    }

    async function remove() {
        const what = sel.kind === 'spot' ? 'this trucking spot and all of its routes' : 'this route';
        const sure = await XS.ask({ title: 'Delete it?', text: `This removes ${what}.`, confirm: 'Delete', danger: true });
        if (!sure) return;
        const res = await XS.rpc(sel.kind === 'spot' ? 'deleteSpot' : 'deleteRoute', draft.id);
        if (!res.ok) return XS.toast(res.error, 'error');
        data = res.data;
        sel = null;
        draft = null;
        paint();
    }

    async function quick() {
        if (!data.spots.length) return XS.toast('Make a trucking spot first.', 'error');
        const name = await XS.ask({ title: 'Quick route', text: 'Name it, then place where the load gets dropped.', confirm: 'Place the drop', input: { placeholder: 'Harbour run' } });
        if (!name) return;
        const fromSpot = sel && sel.kind === 'spot' && data.spots.find((s) => s.id === sel.id);
        sel = { kind: 'route', id: 'new' };
        draft = blankRoute((fromSpot || data.spots[0]).id);
        draft.label = name;
        dirty = true;
        paint();
        if (await place('stops')) await suggest();
    }

    function onInput(e) {
        const f = e.target.dataset.f;
        if (!f || !draft) return;
        const t = e.target;
        let value = t.type === 'checkbox' ? t.checked : t.value;

        if (f === 'laptopProp') {
            if (!draft.laptop) { XS.toast('Place the laptop first.', 'error'); t.checked = false; return; }
            draft.laptop.prop = value ? 'prop_laptop_01a' : false;
            dirty = true;
            return paint();
        }
        if (f === 'hasPickup') {
            if (value) return place('pickup');
            draft.pickup = null;
            dirty = true;
            return paint();
        }
        if (f === 'hasConvoy') {
            draft.convoy = value ? { min: 1, max: Math.min(3, data.meta.convoy || 2) } : null;
            dirty = true;
            return paint();
        }

        if (t.type === 'number' || ['convoy.max', 'escorts', 'spot'].includes(f)) value = Number(value) || 0;
        setField(f, value);
        if (f === 'type') draft.model = '';
        if (['type', 'spot', 'illegal'].includes(f)) paint();
        else {
            const flag = root.querySelector('.bform .grow.dim');
            if (flag) flag.textContent = 'Unsaved changes';
            if (f.startsWith('blip') || f === 'name' || f === 'label') root.querySelector('.blist').innerHTML = list();
        }
    }

    async function onClick(e) {
        const t = e.target.closest('button, .item');
        if (!t) return;
        if (t.dataset.close !== undefined) return XS.close();

        if (t.dataset.sel) {
            if (dirty && !(await XS.ask({ title: 'Leave without saving?', text: 'Your changes here will be lost.', confirm: 'Leave', danger: true }))) return;
            const [kind, id] = t.dataset.sel.split(':');
            return select(kind, Number(id));
        }
        if (t.dataset.new) {
            sel = { kind: t.dataset.new, id: 'new' };
            draft = t.dataset.new === 'spot' ? blankSpot() : blankRoute();
            dirty = true;
            return paint();
        }
        if (t.dataset.quick !== undefined) return quick();
        if (t.dataset.place) return place(t.dataset.place);
        if (t.dataset.add) return place(t.dataset.add);
        if (t.dataset.move) { const [k, i] = t.dataset.move.split(':'); return place(k, Number(i)); }
        if (t.dataset.del) {
            const [k, i] = t.dataset.del.split(':');
            draft[k].splice(Number(i), 1);
            dirty = true;
            return paint();
        }
        if (t.dataset.tp) {
            const [k, i] = t.dataset.tp.split(':');
            const p = k === 'pickup' ? draft.pickup : draft[k][Number(i)];
            if (p) XS.post('teleport', { point: p });
            return;
        }
        if (t.dataset.suggest !== undefined) return suggest();
        if (t.dataset.save !== undefined) return save();
        if (t.dataset.remove !== undefined) return remove();
        if (t.dataset.copy !== undefined) {
            draft = clone(draft);
            delete draft.id;
            draft.label = `${draft.label} (copy)`;
            sel = { kind: 'route', id: 'new' };
            dirty = true;
            return paint();
        }
    }

    function open(payload) {
        root = XS.$('#builder');
        data = { spots: payload.spots || [], routes: payload.routes || [], meta: payload.meta };
        player = payload.player;

        if (sel && sel.id !== 'new') {
            const exists = sel.kind === 'spot' ? data.spots.some((s) => s.id === sel.id) : data.routes.some((r) => r.id === sel.id);
            if (!exists) { sel = null; draft = null; dirty = false; }
        }

        document.documentElement.style.setProperty('--s', Math.max(0.5, Math.min(window.innerWidth / 1680, window.innerHeight / 945)).toFixed(4));
        root.innerHTML = `<div class="stage"><div class="shell">
            <div class="topbar"><div class="brand"><div class="logo"><div>${XS.icon('map')}</div></div>
                <div><b>Trucking builder</b><span><i></i>Spots, bays and routes</span></div></div>
                <div class="me"><button class="closer" data-close>${XS.icon('close')}</button></div></div>
            <div class="pages" style="bottom:22px"><div class="builder">
                <div class="glass blist"></div>
                <div class="bedit"><div class="glass bform"></div><div class="bmap"></div></div>
            </div></div></div></div>`;

        root.classList.add('open');
        map = XS.SatMap.create(root.querySelector('.bmap'));
        if (!draft && data.spots[0]) select('spot', data.spots[0].id);
        else paint();

        root.onclick = onClick;
        root.onchange = onInput;
        root.oninput = (e) => { if (e.target.matches('input[type=text], input:not([type])')) onInput(e); };
    }

    XS.Paths.on(() => {
        if (root && root.classList.contains('open') && sel && sel.kind === 'route') drawMap();
    });

    function close() {
        if (!root) return;
        root.classList.remove('open');
        if (map) { map.map.remove(); map = null; }
    }

    return { open, close };
})();
