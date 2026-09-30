XS.Pages.truck = (() => {
    let host = null;
    let g = null;
    let tab = 'mine';
    let pick = null;
    let paint = null;
    let routes = null;

    const IMG = (model) => `https://docs.fivem.net/vehicles/${model}.webp`;

    function all() {
        return [...(g.personal || []), ...(g.business || [])];
    }

    function vehicle(id) {
        return all().find((v) => v.id === id);
    }

    function row(v) {
        const using = (v.kind === 'truck' && g.truck === v.id) || (v.kind === 'trailer' && g.trailer === v.id);
        const sub = v.kind === 'truck'
            ? `${XS.esc(v.model)} · body ${v.condition}%${v.run ? ' · on a fleet run' : ''}`
            : `${XS.esc(v.trailerType || 'trailer')} trailer · +${v.bonus}%`;
        return `<div class="item click${pick === v.id ? ' on' : ''}" data-pick="${v.id}">
            <div class="grow"><div class="ttl">${XS.esc(v.nickname || v.label)}</div><div class="sub">${sub}</div></div>
            ${using ? '<span class="chip green">In use</span>' : ''}${v.reservedFor && v.business ? '<span class="chip violet">Reserved</span>' : ''}</div>`;
    }

    function listHtml() {
        const tabs = `<div class="seg" style="justify-content:space-between">
            <button class="${tab === 'mine' ? 'on' : ''}" data-tab="mine">My garage</button>
            ${g.business && g.business.length || g.canFleet ? `<button class="${tab === 'biz' ? 'on' : ''}" data-tab="biz">Business</button>` : ''}
            <button class="${tab === 'shop' ? 'on' : ''}" data-tab="shop">Shop</button></div>`;

        if (tab === 'shop') {
            return `${tabs}<div class="dim" style="padding:6px 4px">Trucks pay more on every load. Trailers pay a bonus on loads of their type.</div>
                <div class="item"><div class="grow"><div class="ttl">Your money</div><div class="sub">${XS.money(g.cash)}${g.businessBank != null ? ` · business bank ${XS.money(g.businessBank)}` : ''}</div></div></div>`;
        }

        const source = tab === 'biz' ? g.business || [] : g.personal || [];
        const trucks = source.filter((v) => v.kind === 'truck');
        const trailers = source.filter((v) => v.kind === 'trailer');
        const depot = tab === 'mine' ? `<div class="item click${pick === 'depot' ? ' on' : ''}" data-pick="depot">
            <div class="grow"><div class="ttl">${XS.esc(g.catalog.depot.label)}</div><div class="sub">Free · always there</div></div>${!g.truck ? '<span class="chip green">In use</span>' : ''}</div>` : '';

        return `${tabs}<div class="label">Trucks</div><div class="list">${depot}${trucks.map(row).join('') || (tab === 'biz' ? '<div class="dim">No business trucks yet.</div>' : '')}</div>
            <div class="label">Trailers</div><div class="list">${trailers.map(row).join('') || '<div class="dim">None. The load always comes on a trailer anyway.</div>'}</div>`;
    }

    function partCard(label, value, cost, act) {
        const v = Math.round(value ?? 100);
        return `<div class="part"><div class="row between"><span class="label">${XS.esc(label)}</span><b class="${v < 25 ? 'bad' : v < 50 ? 'warn' : ''}">${v}%</b></div>${XS.bar(v)}
            ${cost > 0 ? `<button class="btn xs" data-act="${act}">Fix for ${XS.money(cost)}</button>` : '<span class="dim" style="font-size:11px">In good order</span>'}</div>`;
    }

    function truckPanel(v) {
        const c = g.catalog;
        const parts = v.parts || {};
        const body = (100 - v.condition) * c.bodyCost;
        const fuel = Math.ceil((100 - (parts.fuel ?? 100)) * c.fuelPrice);
        const serviceAll = c.parts.reduce((s, p) => s + p.cost * (100 - (parts[p.id] ?? 100)) / 100, 0);
        const up = v.upgrades || {};
        const liv = v.livery || {};
        const using = g.truck === v.id;
        paint = paint && paint.id === v.id ? paint : { id: v.id, primary: liv.primary ?? null, secondary: liv.secondary ?? null };

        const perf = c.upgrades.performance.map((u) => {
            const lvl = Number(up[u.id] || 0);
            const pips = Array.from({ length: u.levels }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('');
            return `<div class="upg"><div><b>${XS.esc(u.label)}</b><div class="pips">${pips}</div></div>
                ${lvl < u.levels ? `<button class="btn sm" data-up="${u.id}">${u.toggle ? 'Fit' : `Level ${lvl + 1}`} · ${XS.money(u.cost * (lvl + 1))}</button>` : '<span class="chip green">Maxed</span>'}</div>`;
        }).join('');

        const sw = (key) => c.upgrades.paint.colours.map((col) =>
            `<span class="sw${paint[key] === col.id ? ' on' : ''}" style="background:${col.hex}" title="${XS.esc(col.label)}" data-sw="${key}:${col.id}"></span>`).join('');
        const paintChanged = paint.primary != null && paint.secondary != null && (paint.primary !== liv.primary || paint.secondary !== liv.secondary);

        const runBlock = v.run
            ? `<div class="banner"><div class="pulse-dot"></div><div class="grow"><b>Out on a fleet run</b><div class="dim" style="font-size:12px">${v.run.readyAt * 1000 <= Date.now() ? 'Back now.' : `Back ${new Date(v.run.readyAt * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`} · pays ${XS.money(v.run.pay)}</div></div>
                <button class="btn sm good" data-act="collect">Collect</button></div>`
            : `<div class="row"><select class="field sm grow" data-route>${(routes || []).map((r) => `<option value="${r.id}">${XS.esc(r.label)} · ${XS.money(r.pay)}</option>`).join('')}</select>
                <button class="btn sm" data-act="send">Send it on a run</button></div>`;

        return `
            <div class="row between"><div><div class="kicker">${v.business ? 'Business truck' : 'Your truck'} · ${XS.esc(v.plate || '')}</div>
                <h1>${XS.esc(v.nickname || v.label)}</h1><div class="dim">${XS.esc(v.model)} · +${v.bonus}% pay on every load · ${XS.num((parts.odometer || 0) * 0.621371, 0)} mi driven</div></div>
                <div class="row"><button class="btn sm" data-act="rename">Rename</button>
                <button class="btn ${using ? 'good' : 'primary'}" data-act="use">${using ? `${XS.icon('check')}Driving this` : 'Drive this next'}</button></div></div>
            ${XS.Rig.svg(parts, { body: v.condition, engineNote: `Oil ${Math.round(parts.oil ?? 100)}%` })}
            <div class="parts">
                ${partCard('Body', v.condition, body, 'repair')}
                ${c.parts.map((p) => partCard(p.label, parts[p.id], Math.ceil(p.cost * (100 - (parts[p.id] ?? 100)) / 100), `service:${p.id}`)).join('')}
                ${partCard('Fuel', parts.fuel ?? 100, fuel, 'refuel')}
            </div>
            ${serviceAll > 1 ? `<button class="btn" data-act="service:all">${XS.icon('truck')}Service everything · ${XS.money(Math.ceil(serviceAll))}</button>` : ''}
            <div class="section"><h3>Performance</h3><div class="col" style="gap:8px">${perf}</div></div>
            <div class="section"><div class="row between"><h3>Paint</h3>${paintChanged ? `<button class="btn sm primary" data-act="paint">Spray it · ${XS.money(c.upgrades.paint.cost)}</button>` : ''}</div>
                <div class="label">Main colour</div><div class="swatches">${sw('primary')}</div>
                <div class="label">Second colour</div><div class="swatches">${sw('secondary')}</div></div>
            <div class="section"><h3>Extras</h3><div class="fgrid three">
                <div class="fcell"><span class="label">Xenon lights · ${XS.money(c.upgrades.lights.cost)}</span><select class="field sm" data-style="xenon">
                    <option value="off" ${liv.xenon === false || liv.xenon == null ? 'selected' : ''}>Stock</option>
                    ${['White', 'Blue', 'Electric blue', 'Mint', 'Lime', 'Yellow', 'Gold', 'Orange', 'Red', 'Pink', 'Hot pink', 'Purple', 'Blacklight'].map((n, i) => `<option value="${i}" ${liv.xenon === i ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
                <div class="fcell"><span class="label">Window tint · ${XS.money(c.upgrades.tint.cost)}</span><select class="field sm" data-style="tint">
                    ${['None', 'Light', 'Dark', 'Limo'].map((n, i) => `<option value="${i}" ${(liv.tint || 0) === i ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
                <div class="fcell"><span class="label">Horn · ${XS.money(c.upgrades.horns.cost)}</span><select class="field sm" data-style="horn">
                    <option value="-1">Stock</option>${c.upgrades.horns.list.map((n, i) => `<option value="${i}" ${liv.horn === i ? 'selected' : ''}>${XS.esc(n)}</option>`).join('')}</select></div>
            </div></div>
            <div class="section"><h3>Fleet run</h3><p style="font-size:13px">An idle truck can haul a route on its own. It pays less than driving and is back later.</p>${runBlock}</div>
            <div class="section"><div class="row between"><span class="dim">Sells for ${XS.money(v.value)}</span><button class="btn ghost bad" data-act="sell">${XS.icon('trash')}Sell</button></div></div>`;
    }

    function trailerPanel(v) {
        const using = g.trailer === v.id;
        return `<div class="row between"><div><div class="kicker">${v.business ? 'Business trailer' : 'Your trailer'}</div>
                <h1>${XS.esc(v.nickname || v.label)}</h1><div class="dim">${XS.esc(v.trailerType)} · +${v.bonus}% on ${XS.esc(v.trailerType)} loads</div></div>
                <button class="btn ${using ? 'good' : 'primary'}" data-act="use">${using ? 'Using it' : 'Use it on matching loads'}</button></div>
            <img src="${IMG(v.model)}" style="width:100%;height:220px;object-fit:contain;filter:drop-shadow(0 20px 30px rgba(0,0,0,.6))" onerror="this.remove()">
            <p>Loads of this type come out on your own trailer and pay the bonus. Other loads use the spot's trailer as normal.</p>
            <div class="section"><div class="row between"><span class="dim">Sells for ${XS.money(v.value)}</span><button class="btn ghost bad" data-act="sell">${XS.icon('trash')}Sell</button></div></div>`;
    }

    function depotPanel() {
        return `<div class="kicker">Depot truck</div><h1>${XS.esc(g.catalog.depot.label)}</h1>
            <p>Free, always fuelled and never wears out. It pays the base rate.</p>
            ${XS.Rig.svg({ fuel: 100 }, { engineNote: 'Depot truck, always ready' })}
            <button class="btn ${g.truck ? 'primary' : 'good'}" data-act="depot">${g.truck ? 'Drive the depot truck next' : `${XS.icon('check')}Driving it`}</button>
            <div class="banner">${XS.icon('spark')}<div>Own trucks pay more on every load and keep their upgrades. Have a look in the Shop.</div></div>`;
    }

    function shopPanel() {
        const c = g.catalog;
        const buy = (kind, e) => `<div class="row"><button class="btn sm primary grow" data-buy="${kind}:${e.model}">Buy · ${XS.money(e.price)}</button>
            ${g.canFleet ? `<button class="btn sm" data-buy="${kind}:${e.model}:biz">For the business</button>` : ''}</div>`;
        return `<h2>Trucks</h2><div class="shopgrid">${c.trucks.map((t) => `<div class="shopcard">
                <img src="${IMG(t.model)}" onerror="this.style.visibility='hidden'">
                <div class="row between"><b style="font:700 16px var(--display)">${XS.esc(t.label)}</b><span class="chip green">+${t.bonus}% pay</span></div>
                <div class="dim" style="font-size:12px">${t.level > 1 ? `Needs level ${t.level}` : 'Any level'}</div>${buy('truck', t)}</div>`).join('')}</div>
            <h2>Trailers</h2><div class="shopgrid">${c.trailers.map((t) => `<div class="shopcard">
                <img src="${IMG(t.model)}" onerror="this.style.visibility='hidden'">
                <div class="row between"><b style="font:700 16px var(--display)">${XS.esc(t.label)}</b><span class="chip cyan">+${t.bonus}% on ${XS.esc(t.typeLabel)}</span></div>${buy('trailer', t)}</div>`).join('')}</div>`;
    }

    function paintAll() {
        host.querySelector('.vlist').innerHTML = listHtml();
        const panel = host.querySelector('.vpanel');
        const key = `${tab}:${pick}`;
        if (panel.dataset.key !== key) { panel.scrollTop = 0; panel.dataset.key = key; }
        if (tab === 'shop') panel.innerHTML = shopPanel();
        else if (pick === 'depot' || !pick) panel.innerHTML = depotPanel();
        else {
            const v = vehicle(pick);
            panel.innerHTML = v ? (v.kind === 'truck' ? truckPanel(v) : trailerPanel(v)) : depotPanel();
        }
    }

    async function load() {
        const res = await XS.rpc('garage');
        if (!res.ok) { host.querySelector('.vpanel').innerHTML = `<div class="empty">${XS.esc(res.error)}</div>`; return false; }
        g = res.data;
        if (!routes) {
            const r = await XS.rpc('runRoutes');
            routes = r.ok ? r.data : [];
        }
        if (pick && pick !== 'depot' && !vehicle(pick)) pick = null;
        if (!pick) pick = g.truck || 'depot';
        return true;
    }

    async function act(name, v) {
        let res;
        if (name === 'use') {
            res = await XS.rpc('selectVehicle', v.id, v.kind);
        } else if (name === 'depot') {
            res = await XS.rpc('selectVehicle', null, 'truck');
        } else if (name === 'repair') {
            res = await XS.rpc('repair', v.id);
        } else if (name.startsWith('service:')) {
            res = await XS.rpc('service', v.id, name.split(':')[1]);
        } else if (name === 'refuel') {
            res = await XS.rpc('refuel', v.id);
        } else if (name === 'paint') {
            res = await XS.rpc('style', v.id, { primary: paint.primary, secondary: paint.secondary });
        } else if (name === 'rename') {
            const nick = await XS.ask({ title: 'Rename it', confirm: 'Save', input: { value: v.nickname || '', placeholder: v.label } });
            if (nick === null) return;
            res = await XS.rpc('rename', v.id, nick);
        } else if (name === 'send') {
            const route = Number(host.querySelector('[data-route]').value);
            res = await XS.rpc('sendRun', v.id, route);
            if (res.ok) XS.toast(`Out on the run for ${res.data} minutes.`, 'success');
        } else if (name === 'collect') {
            res = await XS.rpc('collectRun', v.id);
            if (res.ok) XS.toast(`Collected ${XS.money(res.data)}.`, 'success');
        } else if (name === 'sell') {
            const sure = await XS.ask({ title: `Sell ${v.nickname || v.label}?`, text: `You get ${XS.money(v.value)}. Upgrades are not refunded.`, confirm: 'Sell', danger: true });
            if (!sure) return;
            res = await XS.rpc('sellVehicle', v.id);
            if (res.ok) pick = null;
        }
        if (!res) return;
        if (!res.ok) return XS.toast(res.error, 'error');
        if (typeof res.data === 'number' && !['send', 'collect'].includes(name) && res.data > 0) XS.toast(`Done. ${XS.money(res.data)}.`, 'success');
        else if (!['send', 'collect'].includes(name)) XS.toast('Done.', 'success');
        await load();
        paintAll();
        XS.Laptop.refresh(false);
    }

    async function render(el) {
        host = el;
        el.innerHTML = `<div class="garage"><div class="glass vlist"><div class="skel" style="height:240px"></div></div><div class="glass vpanel"><div class="skel" style="height:100%"></div></div></div>`;
        if (!(await load())) return;
        paintAll();

        el.onclick = async (e) => {
            const t = e.target.closest('[data-tab],[data-pick],[data-act],[data-up],[data-sw],[data-buy]');
            if (!t) return;
            if (t.dataset.tab) { tab = t.dataset.tab; if (tab !== 'shop' && pick === null) pick = 'depot'; return paintAll(); }
            if (t.dataset.pick) { pick = t.dataset.pick === 'depot' ? 'depot' : Number(t.dataset.pick); return paintAll(); }
            if (t.dataset.sw) {
                const [key, id] = t.dataset.sw.split(':');
                paint[key] = Number(id);
                if (paint.primary == null) paint.primary = Number(id);
                if (paint.secondary == null) paint.secondary = Number(id);
                return paintAll();
            }
            if (t.dataset.up) {
                const res = await XS.rpc('upgrade', pick, t.dataset.up);
                if (XS.result(res, (cost) => `Fitted for ${XS.money(cost)}.`)) { await load(); paintAll(); }
                return;
            }
            if (t.dataset.buy) {
                const [kind, model, biz] = t.dataset.buy.split(':');
                const res = await XS.rpc('buyVehicle', kind, model, biz === 'biz');
                if (XS.result(res, 'Bought. It is in your garage.')) {
                    await load();
                    tab = biz ? 'biz' : 'mine';
                    pick = res.data;
                    paintAll();
                }
                return;
            }
            if (t.dataset.act) {
                const v = pick && pick !== 'depot' ? vehicle(pick) : null;
                if (t.dataset.act === 'depot') return act('depot');
                if (v) act(t.dataset.act, v);
            }
        };

        el.onchange = async (e) => {
            const key = e.target.dataset.style;
            if (!key || !pick || pick === 'depot') return;
            let value = e.target.value;
            value = value === 'off' ? false : Number(value);
            const res = await XS.rpc('style', pick, { [key]: value });
            if (XS.result(res, (cost) => (cost ? `Done for ${XS.money(cost)}.` : 'Done.'))) { await load(); paintAll(); }
        };
    }

    return { render };
})();
