XS.Admin = (() => {
    let root = null;
    let tab = 'overview';
    let cache = {};
    let map = null;
    let player = null;
    let business = null;
    let fleetFilter = 'all';

    const TABS = [
        ['overview', 'Overview', 'chart'], ['runs', 'Live runs', 'run'], ['players', 'Players', 'users'],
        ['businesses', 'Businesses', 'business'], ['fleet', 'Fleet', 'truck'], ['settings', 'Settings', 'gear'], ['logs', 'Logs', 'certs'],
    ];

    function stage(s) {
        return { hookup: '<span class="chip amber">Hitching</span>', enroute: '<span class="chip cyan">On the road</span>', return: '<span class="chip green">Heading back</span>', escort: '<span class="chip violet">Escorting</span>' }[s] || s;
    }

    function runsTable(runs) {
        if (!runs.length) return '<div class="dim">Nobody is on a load right now.</div>';
        return `<table class="grid"><thead><tr><th>Driver</th><th>Load</th><th>Stage</th><th>From</th><th>Plate</th><th class="r">Time</th><th></th></tr></thead><tbody>
            ${runs.map((r) => `<tr><td>${XS.esc(r.name)}${r.role === 'escort' ? ' <span class="chip violet">Escort</span>' : ''}${r.convoy ? ` <span class="chip cyan">Convoy ${r.convoy}</span>` : ''}${r.codriver ? `<div class="dim" style="font-size:11px">Co-driver: ${XS.esc(r.codriver)}</div>` : ''}</td><td>${XS.esc(r.route)}${r.illegal ? ' <span class="chip red">Illegal</span>' : ''}${r.tipped ? ' <span class="chip red">Reported</span>' : ''}</td>
                <td>${stage(r.stage)}${r.stage === 'enroute' && r.stops > 1 ? ` <span class="dim">${r.stop}/${r.stops}</span>` : ''}</td><td class="dim">${XS.esc(r.spot)}</td>
                <td class="mono">${XS.esc(r.plate)}</td><td class="r mono">${XS.clock(Date.now() / 1000 - r.startedAt)}</td>
                <td class="r"><button class="btn xs" data-clear="${XS.esc(r.citizenid)}">Clear</button></td></tr>`).join('')}</tbody></table>`;
    }

    function overview(o) {
        const series = XS.days(o.daily, 'paid');
        return `<div class="tiles">
                <div class="tile"><small>Drivers</small><b>${XS.num(o.drivers)}</b></div><div class="tile"><small>Loads ever</small><b>${XS.num(o.loads)}</b></div>
                <div class="tile"><small>Paid out ever</small><b class="good">${XS.money(o.earned)}</b></div><div class="tile"><small>Loads today</small><b>${XS.num(o.todayLoads)}</b></div>
                <div class="tile"><small>Paid today</small><b class="good">${XS.money(o.todayPaid)}</b></div><div class="tile"><small>Illegal today</small><b class="${o.todayIllegal ? 'bad' : ''}">${XS.num(o.todayIllegal)}</b></div></div>
            <div class="tiles">
                <div class="tile"><small>On a load now</small><b class="accent">${o.active.length}</b></div><div class="tile"><small>Businesses</small><b>${XS.num(o.businesses)}</b></div>
                <div class="tile"><small>Business money</small><b>${XS.money(o.businessBank)}</b></div><div class="tile"><small>Owned vehicles</small><b>${XS.num(o.vehicles)}</b></div>
                <div class="tile"><small>Average body</small><b>${o.condition}%</b></div><div class="tile"><small>Spots · routes</small><b>${o.spots} · ${o.routes}</b></div></div>
            <div class="glass panel col" style="background:var(--glass-2)"><div class="row between"><h3>Paid out, 14 days</h3><span class="dim">${XS.money(series.reduce((s, d) => s + d.value, 0))}</span></div>${XS.columns(series, { h: 110 })}</div>
            <h3>On a load right now</h3>${runsTable(o.active)}`;
    }

    function runs(list) {
        return `<div class="row between"><h2>Live runs</h2><button class="btn sm" data-refresh>${XS.icon('refresh')}Refresh</button></div>
            <div style="height:360px;border-radius:18px;overflow:hidden;border:1px solid var(--edge);flex:none" class="runmap"></div>${runsTable(list)}`;
    }

    function players(list) {
        const rows = list.map((p) => `<div class="item click${player && player.citizenid === p.citizenid ? ' on' : ''}" data-player="${XS.esc(p.citizenid)}">
            <div class="grow"><div class="ttl">${XS.esc(p.name || p.citizenid)} ${p.online ? '<span class="chip green">Online</span>' : ''}</div>
            <div class="sub">Level ${p.level} · ${XS.num(p.total_completed)} loads · rating ${p.rating}${p.heat ? ` · heat ${p.heat}` : ''}</div></div>
            <b class="mono good">${XS.money(p.total_earned)}</b></div>`).join('');

        let detail = '<div class="empty">Pick a driver.</div>';
        if (player) {
            const certs = player.certList.map((c) => `<span class="perm${player.certs[c.id] ? ' on' : ''}" data-cert="${c.id}">${XS.esc(c.label)}</span>`).join('');
            detail = `<div class="col" style="gap:14px"><div><div class="kicker">${XS.esc(player.citizenid)}</div><h2>${XS.esc(player.name)}</h2>
                ${player.business ? `<div class="dim">${XS.esc(player.business.name)}</div>` : ''}</div>
                <div class="tiles"><div class="tile"><small>Level</small><b>${player.level}</b></div><div class="tile"><small>XP</small><b>${XS.num(player.xp)}</b></div>
                    <div class="tile"><small>Loads</small><b>${XS.num(player.loads)}</b></div><div class="tile"><small>Rating</small><b>${player.rating}</b></div></div>
                <div class="col" style="gap:6px"><div class="row between"><span class="label">Heat</span><span class="mono">${player.heat}/100 · ${player.illegalRuns} illegal runs</span></div>${XS.bar(player.heat, 'heat')}</div>
                <div class="fgrid">
                    <div class="row"><input class="field sm" type="number" id="a-level" value="${player.level}" min="1" max="${player.maxLevel}"><button class="btn sm" data-pa="level">Set level</button></div>
                    <div class="row"><input class="field sm" type="number" id="a-xp" placeholder="XP, can be negative"><button class="btn sm" data-pa="xp">Add XP</button></div>
                    <div class="row"><input class="field sm" type="number" id="a-heat" value="${player.heat}" min="0" max="100"><button class="btn sm" data-pa="heat">Set heat</button></div>
                    <div class="row"><button class="btn sm" data-pa="rating">Reset rating</button><button class="btn sm" data-pa="resetSkills">Reset skills (${player.spent})</button></div></div>
                <div class="label">Certificates · click to give or take</div><div class="row wrap">${certs}</div>
                <button class="btn ghost bad" data-pa="clearRun">Clear their current load</button>
                <div class="label">Recent loads</div><div class="list">${player.recent.map((r) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(r.label)}</div><div class="sub">${XS.ago(r.ts)} · score ${r.trip_rating}${r.illegal ? ' · illegal' : ''}</div></div><b class="mono good">${XS.money(r.driver_cut)}</b></div>`).join('') || '<div class="dim">None.</div>'}</div></div>`;
        }

        return `<div class="fgrid" style="grid-template-columns:1fr 1.1fr;align-items:start;min-height:0">
            <div class="col" style="min-height:0"><input class="field" id="a-search" placeholder="Search by name or citizen ID" value="${XS.esc(cache.query || '')}"><div class="list">${rows || '<div class="dim">No drivers found.</div>'}</div></div>
            <div class="glass panel" style="background:var(--glass-2)">${detail}</div></div>`;
    }

    function businesses(list) {
        const wall = list.map((b) => `<div class="lw${b.logoHidden ? ' hidden-logo' : ''}" data-biz="${b.id}">
            <div class="pic" style="${b.logo ? `background-image:url('${XS.esc(b.logo)}')` : ''}">${b.logo ? '' : XS.esc(b.name.slice(0, 2).toUpperCase())}</div>
            <b style="font:700 14px var(--display)">${XS.esc(b.name)}</b><div class="dim" style="font-size:12px">${b.members} members · ${b.trucks} trucks · ${XS.money(b.bank)}</div>
            ${b.logoHidden ? '<span class="chip red">Logo hidden</span>' : ''}</div>`).join('');

        let detail = '';
        if (business) {
            detail = `<div class="glass panel col" style="background:var(--glass-2);gap:12px">
                <div class="row"><div class="bizlogo" style="width:110px;height:110px;${business.logo ? `background-image:url('${XS.esc(business.logo)}')` : ''}"></div>
                    <div class="grow"><div class="kicker">Level ${business.level.level} · ${XS.esc(business.level.title)}</div><h2>${XS.esc(business.name)}</h2><p>${XS.esc(business.motto)}</p>
                    ${business.logo ? `<div class="mono dim" style="font-size:11px;word-break:break-all">${XS.esc(business.logo)}</div>` : ''}</div></div>
                <div class="row wrap">
                    ${business.logo ? `<button class="btn sm" data-ba="${business.logoHidden ? 'showLogo' : 'hideLogo'}">${business.logoHidden ? 'Show logo' : 'Hide logo'}</button><button class="btn sm" data-ba="removeLogo">Remove logo</button>` : ''}
                    <input class="field sm" style="width:140px" type="number" id="a-bank" value="${business.bank}"><button class="btn sm" data-ba="bank">Set bank</button>
                    <input class="field sm" style="width:200px" id="a-rename" value="${XS.esc(business.name)}"><button class="btn sm" data-ba="rename">Rename</button>
                    <button class="btn sm danger" data-ba="disband">Close it</button></div>
                <div class="fgrid"><div class="col"><div class="label">Members</div><div class="list">${business.members.map((m) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(m.name)}</div><div class="sub">${XS.esc(m.rank)} · ${m.deliveries} loads</div></div></div>`).join('')}</div></div>
                <div class="col"><div class="label">Ledger</div><div class="list">${business.ledger.slice(0, 10).map((l) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(l.note || l.kind)}</div><div class="sub">${XS.esc(l.name)} · ${XS.ago(l.ts)}</div></div>${l.amount ? `<b class="mono ${l.amount < 0 ? 'bad' : 'good'}">${XS.money(l.amount)}</b>` : ''}</div>`).join('')}</div></div></div></div>`;
        }
        return `<h2>Businesses</h2><p>Every logo is shown here so anything unfriendly is easy to spot and hide.</p>${detail}<div class="logowall">${wall || '<div class="dim">No businesses yet.</div>'}</div>`;
    }

    function fleet(list) {
        return `<div class="row between"><h2>Fleet</h2><div class="seg">${[['all', 'All'], ['damaged', 'Damaged'], ['out', 'On runs'], ['business', 'Business']].map(([id, l]) => `<button class="${fleetFilter === id ? 'on' : ''}" data-ff="${id}">${l}</button>`).join('')}</div></div>
            <table class="grid"><thead><tr><th>Vehicle</th><th>Owner</th><th>Plate</th><th class="r">Body</th><th></th></tr></thead><tbody>
            ${list.map((v) => `<tr><td>${XS.esc(v.nickname || v.label)} <span class="dim">${XS.esc(v.model)}</span>${v.out ? ' <span class="chip cyan">On a run</span>' : ''}</td>
                <td>${XS.esc(v.businessName || v.ownerName)}</td><td class="mono">${XS.esc(v.plate || '')}</td><td class="r mono">${v.condition}%</td>
                <td class="r"><button class="btn xs" data-va="repair:${v.id}">Repair</button>${v.out ? `<button class="btn xs" data-va="recall:${v.id}">Recall</button>` : ''}<button class="btn xs" data-va="delete:${v.id}">${XS.icon('trash')}</button></td></tr>`).join('')}</tbody></table>`;
    }

    function settings(groups) {
        return `<h2>Settings</h2><p>Changes here apply straight away and override config.lua. Reset puts the config value back.</p>
            ${groups.map((g) => `<div class="section"><h3>${XS.esc(g.group)}</h3>${g.items.map((s) => `<div class="row" style="padding:6px 0">
                <div class="grow"><b style="font:600 13px var(--ui)">${XS.esc(s.label)}</b>${s.changed ? ' <span class="chip violet">Changed</span>' : ''}${s.help ? `<div class="dim" style="font-size:12px">${XS.esc(s.help)}</div>` : ''}</div>
                ${s.type === 'bool'
                    ? `<label class="check"><input type="checkbox" data-set="${s.key}" ${s.value ? 'checked' : ''}><i></i></label>`
                    : `<span class="dim">${XS.esc(s.prefix || '')}</span><input class="field sm" style="width:110px" type="number" data-set="${s.key}" value="${s.value}" min="${s.min}" max="${s.max}"><span class="dim">${XS.esc(s.suffix || '')}</span>`}
                ${s.changed ? `<button class="btn xs" data-reset="${s.key}">Reset</button>` : ''}</div>`).join('')}</div>`).join('')}`;
    }

    function logs(data) {
        return `<div class="fgrid" style="align-items:start"><div class="col"><h3>Loads</h3><div class="list">${data.loads.map((l) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(l.label)}${l.illegal ? ' <span class="chip red">Illegal</span>' : ''}</div>
            <div class="sub">${XS.esc(l.name)} · ${XS.ago(l.ts)} · score ${l.trip_rating}${l.company_cut ? ` · business ${XS.money(l.company_cut)}` : ''}</div></div><b class="mono good">${XS.money(l.final_payout)}</b></div>`).join('')}</div></div>
            <div class="col"><h3>Admin actions</h3><div class="list">${data.admin.map((a) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(a.action)}</div><div class="sub">${XS.esc(a.name)} · ${XS.ago(a.ts)}</div><div class="sub mono">${XS.esc(a.detail)}</div></div></div>`).join('') || '<div class="dim">Nothing yet.</div>'}</div></div></div>`;
    }

    async function load(name) {
        const calls = {
            overview: () => XS.rpc('adminOverview'),
            runs: () => XS.rpc('adminRuns'),
            players: () => XS.rpc('adminPlayers', cache.query || ''),
            businesses: () => XS.rpc('adminBusinesses'),
            fleet: () => XS.rpc('adminFleet', fleetFilter),
            settings: () => XS.rpc('adminSettings'),
            logs: () => XS.rpc('adminLogs'),
        };
        const res = await calls[name]();
        cache[name] = res.ok ? res.data : null;
        return res;
    }

    function paint() {
        const body = root.querySelector('.adbody');
        const data = cache[tab];
        if (map) { map.map.remove(); map = null; }
        if (data == null) { body.innerHTML = '<div class="skel" style="height:300px"></div>'; return; }
        const views = { overview, runs, players, businesses, fleet, settings, logs };
        body.innerHTML = views[tab](data);

        if (tab === 'runs') {
            map = XS.SatMap.create(body.querySelector('.runmap'));
            if (map) {
                const pts = [];
                data.forEach((r) => { if (r.coords) { map.marker(r.coords, r.illegal ? '#ff5d6c' : '#38d9ff', `${r.name} · ${r.route}`, 16); pts.push(r.coords); } });
                if (pts.length) map.fit(pts);
            }
        }
    }

    async function show(name) {
        tab = name;
        root.querySelectorAll('[data-tab]').forEach((n) => n.classList.toggle('on', n.dataset.tab === name));
        cache[name] = null;
        paint();
        await load(name);
        paint();
    }

    async function onClick(e) {
        const t = e.target.closest('button, .item, .lw, .perm');
        if (!t) return;
        const d = t.dataset;
        if (d.close !== undefined) return XS.close();
        if (d.tab) return show(d.tab);
        if (d.builder !== undefined) return XS.post('openBuilder');
        if (d.refresh !== undefined) return show(tab);

        if (d.clear) {
            if (!(await XS.ask({ title: 'Clear this load?', text: 'Their truck and trailer are removed. No pay.', confirm: 'Clear', danger: true }))) return;
            if (XS.result(await XS.rpc('adminPlayerAction', d.clear, 'clearRun'), 'Cleared.')) show(tab);
            return;
        }
        if (d.player) {
            const res = await XS.rpc('adminPlayer', d.player);
            player = res.ok ? res.data : null;
            return paint();
        }
        if (d.pa && player) {
            const values = { level: () => Number(root.querySelector('#a-level').value), xp: () => Number(root.querySelector('#a-xp').value), heat: () => Number(root.querySelector('#a-heat').value) };
            if (['clearRun', 'resetSkills'].includes(d.pa) && !(await XS.ask({ title: 'Are you sure?', confirm: 'Yes', danger: true }))) return;
            const res = await XS.rpc('adminPlayerAction', player.citizenid, d.pa, values[d.pa] ? values[d.pa]() : null);
            if (XS.result(res, 'Done.')) {
                const again = await XS.rpc('adminPlayer', player.citizenid);
                player = again.ok ? again.data : null;
                await load('players');
                paint();
            }
            return;
        }
        if (d.cert && player) {
            const grant = !player.certs[d.cert];
            const res = await XS.rpc('adminPlayerAction', player.citizenid, 'cert', { id: d.cert, grant });
            if (XS.result(res, grant ? 'Certificate given.' : 'Certificate taken.')) {
                const again = await XS.rpc('adminPlayer', player.citizenid);
                player = again.ok ? again.data : player;
                paint();
            }
            return;
        }
        if (d.biz) {
            const res = await XS.rpc('adminBusiness', Number(d.biz));
            business = res.ok ? res.data : null;
            return paint();
        }
        if (d.ba && business) {
            if (d.ba === 'disband' && !(await XS.ask({ title: `Close ${business.name}?`, text: 'This cannot be undone.', confirm: 'Close it', danger: true }))) return;
            const value = d.ba === 'bank' ? Number(root.querySelector('#a-bank').value) : d.ba === 'rename' ? root.querySelector('#a-rename').value : null;
            const res = await XS.rpc('adminBusinessAction', business.id, d.ba, value);
            if (XS.result(res, 'Done.')) {
                const again = d.ba === 'disband' ? { ok: false } : await XS.rpc('adminBusiness', business.id);
                business = again.ok ? again.data : null;
                await load('businesses');
                paint();
            }
            return;
        }
        if (d.ff) { fleetFilter = d.ff; return show('fleet'); }
        if (d.va) {
            const [action, id] = d.va.split(':');
            if (action === 'delete' && !(await XS.ask({ title: 'Delete this vehicle?', text: 'It is gone for good.', confirm: 'Delete', danger: true }))) return;
            if (XS.result(await XS.rpc('adminVehicleAction', Number(id), action), 'Done.')) show('fleet');
            return;
        }
        if (d.reset) {
            if (XS.result(await XS.rpc('adminResetSetting', d.reset), 'Back to the config value.')) show('settings');
        }
    }

    async function onChange(e) {
        const t = e.target;
        if (t.dataset.set) {
            const value = t.type === 'checkbox' ? t.checked : Number(t.value);
            if (XS.result(await XS.rpc('adminSetSetting', t.dataset.set, value), 'Saved.')) show('settings');
        }
    }

    let searchTimer = null;
    function onInput(e) {
        if (e.target.id !== 'a-search') return;
        clearTimeout(searchTimer);
        searchTimer = setTimeout(async () => {
            cache.query = e.target.value;
            await load('players');
            paint();
            const box = root.querySelector('#a-search');
            if (box) { box.focus(); box.setSelectionRange(box.value.length, box.value.length); }
        }, 350);
    }

    function open(data) {
        root = XS.$('#admin');
        cache = { overview: data.overview };
        document.documentElement.style.setProperty('--s', Math.max(0.5, Math.min(window.innerWidth / 1680, window.innerHeight / 945)).toFixed(4));
        root.innerHTML = `<div class="stage"><div class="shell">
            <div class="topbar"><div class="brand"><div class="logo"><div>${XS.icon('shield')}</div></div>
                <div><b>Trucking admin</b><span><i></i>Everything happening on the job</span></div></div>
                <div class="me"><button class="btn sm" data-builder>${XS.icon('map')}Open the builder</button><button class="closer" data-close>${XS.icon('close')}</button></div></div>
            <div class="pages" style="bottom:22px"><div class="admin">
                <nav class="glass biznav">${TABS.map(([id, label, icon]) => `<button data-tab="${id}" class="${tab === id ? 'on' : ''}">${XS.icon(icon)}${label}</button>`).join('')}</nav>
                <div class="glass bizbody adbody"></div></div></div></div></div>`;
        root.classList.add('open');
        root.onclick = onClick;
        root.onchange = onChange;
        root.oninput = onInput;
        tab = 'overview';
        paint();
    }

    function close() {
        if (!root) return;
        root.classList.remove('open');
        if (map) { map.map.remove(); map = null; }
    }

    return { open, close };
})();
