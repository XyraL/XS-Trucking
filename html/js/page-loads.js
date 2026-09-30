XS.Pages.loads = (() => {
    let tilt = null;
    let host = null;
    let current = null;
    let filter = 'all';
    let selected = null;
    let etaTimer = null;
    let poll = null;
    let busy = false;

    const NEARBY = 4500;
    const isCoop = (l) => !!(l.convoy || l.escorts > 0);
    const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

    function loads(ctx) {
        const all = ctx.board.loads || [];
        return all.filter((l) => {
            if (filter === 'coop') return isCoop(l);
            if (filter === 'hot') return l.hot;
            if (filter === 'illegal') return l.illegal;
            return !l.illegal || filter === 'all';
        });
    }

    function crewsFor(ctx, id) {
        return (ctx.board.crews || []).filter((c) => c.route === id);
    }

    function myCrew(ctx) {
        return (ctx.board.crews || []).find((c) => c.mine) || null;
    }

    function chip(ctx, l) {
        const crews = crewsFor(ctx, l.id);
        if (crews.length) return `<span class="chip green">${XS.icon('users')}${crews.reduce((s, c) => s + c.members.length, 0)} in crew</span>`;
        if (l.locked) return `<span class="chip">${XS.icon('lock')}Locked</span>`;
        if (l.guards) return `<span class="chip red">${XS.icon('target')}Armed</span>`;
        if (l.illegal) return '<span class="chip red">Illegal</span>';
        if (l.hot) return `<span class="chip amber">${XS.icon('hot')}Hot</span>`;
        if (l.convoy) return `<span class="chip violet">Convoy ${l.convoy.max}</span>`;
        if (l.escorts > 0) return '<span class="chip violet">Escort</span>';
        if (l.timer > 0) return `<span class="chip cyan">${XS.clock(l.timer)}</span>`;
        if (l.stops.length > 1) return `<span class="chip cyan">${l.stops.length} drops</span>`;
        return '';
    }

    function card(ctx, l) {
        const cls = ['lc', 'glass', l.id === selected ? 'on' : '', l.locked ? 'lock' : '', l.illegal ? 'illegal' : ''].join(' ');
        return `<button class="${cls}" data-load="${l.id}">
            <div class="k"><span>${XS.esc(l.typeLabel.toUpperCase())} · ${XS.esc(l.weight)} T</span>${chip(ctx, l)}</div>
            <div class="d">${XS.esc(l.label)}</div>
            <div class="f"><span>${XS.dist(l.km)} · ${l.minutes} min</span><b>${XS.money(l.pay)}</b></div>
        </button>`;
    }

    function truckCard(ctx, slim) {
        const t = ctx.board.truck;
        const parts = t ? t.parts : { fuel: 100 };
        const label = t ? t.label : 'Depot Hauler';
        const status = t ? (t.condition <= 0 ? '<span class="chip red">Needs repair</span>' : '<span class="chip green">Ready</span>') : '<span class="chip cyan">Free</span>';
        const trailer = ctx.board.trailer;
        if (slim) {
            return `<div class="glass truckcard slim"><div class="row between">
                <div class="row" style="gap:12px;min-width:0"><span class="si">${XS.icon('truck')}</span>
                    <div style="min-width:0"><b>${XS.esc(label)}</b><div class="dim" style="font-size:12px">${t ? (t.business ? 'Business truck' : 'Your truck') : 'Depot truck'} · fuel ${Math.round(parts.fuel ?? 100)}%${trailer ? ` · own ${XS.esc(trailer.label)}` : ''}</div></div></div>
                <div class="row">${status}<button class="btn sm" data-goto="truck">Change</button></div>
            </div></div>`;
        }
        return `<div class="glass truckcard">
            <div class="row between"><div><b style="font:700 18px var(--display)">${XS.esc(label)}</b>
                <span class="dim"> · ${t ? (t.business ? 'business truck' : 'your truck') : 'depot truck'}${trailer ? ` · own ${XS.esc(trailer.label)}` : ''}</span></div>${status}</div>
            ${XS.Rig.svg(t ? parts : { fuel: 100 }, { body: t ? t.condition : null, engineNote: t ? null : 'Depot truck, always ready' })}
            <div class="row between"><span class="dim" style="font-size:12px">${t ? 'Upgrades and paint travel with it.' : 'Buy a truck for more pay on every load.'}</span>
                <button class="btn sm" data-goto="truck">${XS.icon('truck')}Change</button></div>
        </div>`;
    }

    function heatBar(heat) {
        return `<div class="col" style="gap:6px"><div class="row between"><span class="label">Heat</span><span class="mono ${heat > 60 ? 'bad' : 'warn'}">${heat}/100</span></div>${XS.bar(heat, 'heat')}</div>`;
    }

    function need(ctx, c) {
        const out = [];
        if (c.drivers < c.minDrivers) out.push(plural(c.minDrivers - c.drivers, 'more truck'));
        if (c.escorts < c.needEscorts) out.push(plural(c.needEscorts - c.escorts, 'escort'));
        if (out.length) return `Needs ${out.join(' and ')} before it can roll out.`;
        return c.lead === ctx.board.me ? 'Everyone in? Roll out when you are ready.' : 'Waiting on the lead to roll out.';
    }

    function seat(m, lead, word = 'Escort') {
        const role = m.lead ? 'Lead driver' : m.role === 'escort' ? word : 'Driver';
        const kick = lead && !m.me ? `<button class="btn xs ghost" data-crew-kick="${m.source}">${XS.icon('close')}</button>` : '';
        return `<div class="seat on ${m.role}${m.me ? ' self' : ''}"><span class="si">${XS.icon(m.role === 'escort' ? 'shield' : 'truck')}</span>
            <div class="grow"><b>${XS.esc(m.name)}</b><small>${role}${m.me ? ' · you' : ''}</small></div>${kick}</div>`;
    }

    function openSeat(role, word = 'Escort') {
        return `<div class="seat ${role}"><span class="si">${XS.icon('plus')}</span><div class="grow"><b>Open</b><small>${role === 'escort' ? word : 'Truck'}</small></div></div>`;
    }

    function crewCard(ctx, c, l) {
        const word = l.guards ? 'Gunner' : 'Escort';
        const lead = c.lead === ctx.board.me;
        const drivers = c.members.filter((m) => m.role === 'driver');
        const escorts = c.members.filter((m) => m.role === 'escort');
        const seats = [
            ...drivers.map((m) => seat(m, lead)),
            ...Array.from({ length: Math.max(0, c.maxDrivers - drivers.length) }, () => openSeat('driver')),
            ...escorts.map((m) => seat(m, lead, word)),
            ...Array.from({ length: Math.max(0, c.maxEscorts - escorts.length) }, () => openSeat('escort', word)),
        ].join('');

        let foot = '';
        if (c.mine) {
            foot = `<span class="dim grow" style="font-size:12px">${XS.esc(need(ctx, c))}</span>`;
        } else if (!myCrew(ctx) && !ctx.board.run) {
            const drive = c.drivers < c.maxDrivers;
            const escort = c.escorts < c.maxEscorts;
            if (drive && !l.locked) foot += `<button class="btn sm primary" data-crew-join="${c.id}" data-role="driver">${XS.icon('truck')}Join as driver</button>`;
            if (escort) foot += `<button class="btn sm" data-crew-join="${c.id}" data-role="escort">${XS.icon(l.guards ? 'target' : 'shield')}Join as ${word.toLowerCase()}</button>`;
            if (drive && l.locked) foot += `<span class="dim" style="font-size:12px">Driving it needs ${XS.esc(l.locked)}.</span>`;
            if (!drive && !escort) foot = '<span class="dim" style="font-size:12px">This crew is full.</span>';
        }

        return `<div class="crew${c.mine ? ' mine' : ''}${c.ready ? ' ready' : ''}">
            <div class="row between"><div><div class="label">${c.mine ? 'Your crew' : 'Open crew'}</div>
                <b>${XS.esc(c.leadName)}'s ${c.maxDrivers > 1 ? 'convoy' : 'crew'}</b></div>
                <span class="chip ${c.ready ? 'green' : 'violet'}">${c.ready ? 'Ready' : 'Filling up'} · ${Math.max(1, Math.ceil(c.expiresIn / 60))} min</span></div>
            <div class="seats">${seats}</div>
            ${foot ? `<div class="row wrap">${foot}</div>` : ''}
        </div>`;
    }

    function coopTerms(ctx, l) {
        const t = ctx.board.coop || {};
        const out = [];
        if (l.convoy) out.push(`+${t.convoyBonus}% per extra truck`);
        if (l.escorts > 0) out.push(`${l.guards ? 'gunners' : 'escorts'} earn ${t.escortCut}%`);
        return out.join(' · ');
    }

    function crewSection(ctx, l) {
        if (!isCoop(l)) return '';
        const mine = myCrew(ctx);
        const here = crewsFor(ctx, l.id);
        let body;
        if (mine && mine.route !== l.id) {
            const other = (ctx.board.loads || []).find((x) => x.id === mine.route);
            body = `<div class="banner">${XS.icon('users')}<div class="grow"><b>You are in a crew already</b>
                <div class="dim" style="font-size:12px">It is hauling ${XS.esc(other ? other.label : 'another load')}.</div></div>
                <button class="btn sm" data-load="${mine.route}">Show it</button></div>`;
        } else if (here.length) {
            body = here.map((c) => crewCard(ctx, c, l)).join('');
        } else {
            const how = l.convoy ? `up to ${l.convoy.max} trucks roll out together` : l.guards ? 'your gunners roll out with you' : 'your escort rolls out with you';
            body = `<div class="crew none"><span class="dim">No crew yet. Start one and ${how}. Anyone joining has to be at this laptop.</span></div>`;
        }
        return `<div class="col" style="gap:8px"><div class="row between"><span class="kicker">Co-op</span><span class="dim" style="font-size:12px">${XS.esc(coopTerms(ctx, l))}</span></div>${body}</div>`;
    }

    function actions(ctx, l) {
        const mine = myCrew(ctx);
        if (ctx.board.run) return `<button class="btn primary" data-goto="run" style="flex:2">${XS.icon('run')}You are on a load. Open it.</button>`;

        if (mine && mine.route === l.id) {
            if (mine.lead === ctx.board.me) {
                return `<button class="btn ghost bad" data-crew-leave>Call it off</button>
                    <button class="btn primary${mine.ready ? '' : ' off'}" data-crew-start style="flex:2">${XS.icon('truck')}Roll out</button>`;
            }
            return `<button class="btn ghost bad" data-crew-leave>Leave crew</button>
                <button class="btn off" style="flex:2">${XS.icon('clock')}Waiting on the lead</button>`;
        }
        if (mine) return `<button class="btn primary" data-load="${mine.route}" style="flex:2">${XS.icon('users')}Back to your crew</button>`;
        if (l.locked) return `<button class="btn off" style="flex:2">${XS.icon('lock')}${XS.esc(l.locked)}</button>`;

        const solo = l.needsEscort
            ? ''
            : `<button class="btn ${l.illegal ? 'danger' : 'primary'}" data-take="${l.id}" style="flex:2">${l.illegal ? 'Take it anyway' : 'Take this load'}</button>`;
        if (!isCoop(l)) return solo;
        return `<button class="btn${l.needsEscort ? ' primary' : ''}" data-crew-open="${l.id}"${l.needsEscort ? ' style="flex:2"' : ''}>${XS.icon('users')}Start a crew</button>${solo}`;
    }

    function detail(ctx) {
        const l = (ctx.board.loads || []).find((x) => x.id === selected);
        if (!l) {
            return `<div class="glass loaddetail"><div class="empty">${XS.icon('route')}<h3>No loads here yet</h3><p>An admin can add routes to this spot in /truckingbuilder.</p></div></div>`;
        }

        const p = ctx.board.profile || {};
        const truck = ctx.board.truck;
        const trailer = ctx.board.trailer;
        const bonuses = [];
        if (l.hot) bonuses.push(['Hot load', ctx.board.hotBonus]);
        if (truck && truck.bonus) bonuses.push(['Your truck', truck.bonus]);
        if (trailer && trailer.type === l.type && trailer.bonus) bonuses.push(['Your trailer', trailer.bonus]);
        if (l.stops.length > 1) bonuses.push(['Multi-drop', 25]);
        const pct = bonuses.reduce((s, b) => s + (Number(b[1]) || 0), 0);
        const estimate = Math.round(l.pay * (1 + pct / 100));

        const reqs = [
            `<span class="req${p.level >= l.level ? '' : ' no'}">${XS.icon(p.level >= l.level ? 'check' : 'lock')}Level ${l.level}</span>`,
        ];
        if (l.cert) reqs.push(`<span class="req${p.certs && p.certs[l.cert] ? '' : ' no'}">${XS.icon(p.certs && p.certs[l.cert] ? 'check' : 'lock')}${XS.esc(l.certLabel)}</span>`);
        if (l.escorts > 0) reqs.push(`<span class="req${l.needsEscort ? ' no' : ''}">${XS.icon('shield')}${plural(l.escorts, 'escort')} ${l.needsEscort ? 'needed' : 'welcome'}</span>`);

        const notes = [];
        if (l.timer > 0) notes.push(`<div class="row dim">${XS.icon('clock')}Has to arrive within ${XS.clock(l.timer)} or it pays less.</div>`);
        if (l.fragile) notes.push(`<div class="row dim">${XS.icon('warn')}Fragile. Every knock costs pay.</div>`);
        if (l.remotePickup) notes.push(`<div class="row dim">${XS.icon('pin')}The trailer waits at its own pickup point${l.convoy ? ' when you haul it alone' : ''}.</div>`);

        return `<div class="glass loaddetail"><div class="ld-body">
            <div><div class="kicker" style="${l.illegal ? 'color:var(--red)' : ''}">Load ${l.id} · ${XS.esc(l.typeLabel)}${l.hot ? ' · hot' : ''}${l.illegal ? ' · illegal' : ''}</div>
                <div class="ttl">${XS.esc(l.label)}</div>
                <div class="dim" style="margin-top:4px">${XS.esc(l.cargo || l.typeLabel)} · ${l.weight} tonnes${l.stops.length > 1 ? ` · ${l.stops.length} drops` : ''}</div></div>
            <div class="tiles"><div class="tile"><small>Distance</small><b>${XS.dist(l.km)}</b></div>
                <div class="tile"><small>About</small><b>${l.minutes} min</b></div>
                <div class="tile"><small>XP</small><b>+${XS.num(l.xp)}</b></div></div>
            <div class="reqs">${reqs.join('')}</div>
            ${l.guards ? `<div class="banner red">${XS.icon('target')}<div class="grow"><b>${l.guards.count} armed guard${l.guards.count === 1 ? '' : 's'} at the pickup</b><div class="dim" style="font-size:12px">${XS.esc(l.guards.weapon)} · ${XS.esc(l.guards.armour)} armour · ${XS.esc(l.guards.accuracy)} aim. Take them out, then hitch the trailer. Shots bring the police.</div></div></div>${heatBar(p.heat || 0)}` : ''}
            ${l.illegal && !l.guards ? `<div class="banner red">${XS.icon('warn')}<div class="grow"><b>Someone might call it in.</b><div class="dim" style="font-size:12px">Each run adds heat, and heat makes a tip-off more likely.</div></div></div>${heatBar(p.heat || 0)}` : ''}
            ${crewSection(ctx, l)}
            ${notes.join('')}
            <div class="money">
                <div class="lines">Base pay<b>${XS.money(l.pay)}</b>${bonuses.map(([n, v]) => `<br>${XS.esc(n)} +${v}%<b></b>`).join('')}<br><span class="mute">Skills and rating add more at the drop.</span></div>
                <div class="big"><span class="label">About</span><b>${XS.money(estimate)}</b></div>
            </div>
            </div><div class="row"><button class="btn" data-waypoint="${l.id}">${XS.icon('pin')}GPS</button>${actions(ctx, l)}</div>
        </div>`;
    }

    function toneFor(l) {
        if (l.locked) return 'grey';
        if (l.illegal) return 'red';
        if (l.hot) return 'amber';
        if (isCoop(l)) return 'violet';
        return 'cyan';
    }

    function markersFor(ctx) {
        const laptop = ctx.board.spot.laptop;
        const out = [{ type: 'depot', x: laptop.x, y: laptop.y, icon: 'loads', tone: 'white', label: ctx.board.spot.name }];
        for (const l of loads(ctx)) {
            const tone = toneFor(l);
            const label = `${l.label} · ${XS.money(l.pay)}`;
            if (l.id !== selected) {
                out.push({ type: 'load', x: l.stops[0].x, y: l.stops[0].y, tone, label, pick: l.id, icon: l.guards ? 'target' : null });
                continue;
            }
            if (l.remotePickup && l.origin) out.push({ type: 'pickup', x: l.origin.x, y: l.origin.y, tone, icon: l.guards ? 'target' : 'pin', label: l.guards ? 'Guarded trailer' : 'Trailer pickup', pick: l.id });
            l.stops.forEach((s, i) => out.push({
                type: 'drop', x: s.x, y: s.y, tone, active: true, pick: l.id, bubble: i === 0,
                number: l.stops.length > 1 ? i + 1 : null, label: `Drop ${i + 1}`,
            }));
        }
        return out;
    }

    function nearby(ctx, l) {
        const depot = ctx.board.spot.laptop;
        return Math.hypot(l.stops[0].x - depot.x, l.stops[0].y - depot.y) <= NEARBY;
    }

    function focusFor(ctx) {
        const points = [ctx.board.spot.laptop];
        for (const l of loads(ctx)) {
            if (l.id !== selected && !nearby(ctx, l)) continue;
            points.push(...l.stops);
            if (l.remotePickup && l.origin) points.push(l.origin);
        }
        return points;
    }

    function moveEta() {
        const bubble = host && host.querySelector('.eta');
        if (!bubble || !bubble.dataset.ready) return;
        const at = tilt && tilt.anchor();
        if (!at || at.y < 70) {
            bubble.style.opacity = 0;
            return;
        }
        const half = bubble.offsetWidth / 2;
        const room = host.querySelector('.mapcard').offsetWidth;
        const x = Math.min(Math.max(at.x, half + 14), room - half - 14);
        bubble.style.left = `${x}px`;
        bubble.style.top = `${at.y}px`;
        bubble.style.setProperty('--arrow', `${Math.max(-half + 18, Math.min(half - 18, at.x - x))}px`);
        bubble.style.opacity = 1;
    }

    function choose(ctx, id) {
        selected = id;
        if (!loads(ctx).find((l) => l.id === selected)) filter = 'all';
        tilt.show(markersFor(ctx), focusFor(ctx));
        paint(ctx);
        placeEta(ctx);
    }

    function placeEta(ctx) {
        clearTimeout(etaTimer);
        const bubble = host.querySelector('.eta');
        if (!bubble) return;
        const l = (ctx.board.loads || []).find((x) => x.id === selected);
        delete bubble.dataset.ready;
        bubble.style.opacity = 0;
        if (!l) return;
        bubble.innerHTML = `<b>${XS.esc(l.label)}</b><span>${XS.dist(l.km)} · ${l.minutes} min · ${XS.money(l.pay)}</span>`;
        etaTimer = setTimeout(() => {
            bubble.dataset.ready = '1';
            moveEta();
        }, 350);
    }

    function paint(ctx, keep) {
        const list = loads(ctx);
        const count = (ctx.board.loads || []).filter((l) => !l.locked).length;
        const hasIllegal = (ctx.board.loads || []).some((l) => l.illegal);
        const carousel = host.querySelector('.carousel');
        const oldBody = host.querySelector('.ld-body');
        const scrollX = carousel.scrollLeft;
        const scrollY = oldBody ? oldBody.scrollTop : 0;

        carousel.innerHTML = list.length
            ? list.map((l) => card(ctx, l)).join('')
            : `<div class="glass lc" style="flex:1;cursor:default">No loads match this filter.</div>`;
        host.querySelector('.maphead').innerHTML = `
            <div><h1>${count} load${count === 1 ? '' : 's'} ready</h1>
                <p>${XS.esc(ctx.board.spot.name)}${ctx.board.hotLeft ? ` · hot loads swap in ${Math.ceil(ctx.board.hotLeft / 60)} min` : ''}</p></div>
            <div class="seg">
                ${[['all', 'All'], ['coop', 'Co-op'], ['hot', 'Hot']].map(([id, label]) => `<button class="${filter === id ? 'on' : ''}" data-filter="${id}">${label}</button>`).join('')}
                ${hasIllegal ? `<button class="${filter === 'illegal' ? 'on' : ''}" data-filter="illegal">${XS.icon('warn')}Illegal</button>` : ''}
            </div>`;
        const pick = (ctx.board.loads || []).find((l) => l.id === selected);
        host.querySelector('.side').innerHTML = truckCard(ctx, pick && isCoop(pick)) + detail(ctx);

        if (keep) {
            carousel.style.scrollBehavior = 'auto';
            carousel.scrollLeft = scrollX;
            carousel.style.scrollBehavior = '';
            const body = host.querySelector('.ld-body');
            if (body) body.scrollTop = scrollY;
            return;
        }
        const on = host.querySelector('.lc.on');
        if (on) on.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    }

    function signature(list) {
        return JSON.stringify((list || []).map((c) => ({ ...c, expiresIn: Math.ceil((c.expiresIn || 0) / 60) })));
    }

    async function refreshCrews(force) {
        if (!host || !current || !XS.Laptop.ctx.open || XS.Laptop.ctx.page !== 'loads') return;
        const res = await XS.rpc('crews', current.board.spot.id);
        if (!res.ok || !Array.isArray(res.data) || !host) return;
        const changed = force || signature(res.data) !== signature(current.board.crews);
        current.board.crews = res.data;
        if (changed && XS.Laptop.ctx.page === 'loads') paint(current, true);
    }

    async function crewAction(button, call, done) {
        if (busy) return;
        busy = true;
        button.classList.add('off');
        const res = await call();
        busy = false;
        if (!XS.result(res, done)) {
            button.classList.remove('off');
            return;
        }
        await refreshCrews(true);
    }

    function render(el, ctx, opts) {
        host = el;
        current = ctx;
        const list = ctx.board.loads || [];
        const mine = myCrew(ctx);
        if (!selected || !list.find((l) => l.id === selected)) {
            const first = (mine && list.find((l) => l.id === mine.route)) || list.find((l) => !l.locked && !l.illegal) || list[0];
            selected = first ? first.id : null;
        }
        if (opts.load) selected = opts.load;

        el.innerHTML = `<div class="loads">
            <div class="mapcard"><div class="tiltbox"></div>
                <div class="maphead"></div><div class="glass eta" style="opacity:0"></div><div class="carousel"></div></div>
            <div class="side"></div></div>`;

        tilt = XS.Tilt.create(el.querySelector('.tiltbox'), { onPick: (id) => choose(ctx, id), onMove: moveEta });
        const carousel = el.querySelector('.carousel');
        carousel.addEventListener('wheel', (e) => {
            if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
            carousel.scrollLeft += e.deltaY;
            e.preventDefault();
        }, { passive: false });
        tilt.show(markersFor(ctx), focusFor(ctx));
        paint(ctx);
        placeEta(ctx);

        clearInterval(poll);
        poll = setInterval(() => refreshCrews(false), 3000);

        el.onclick = async (e) => {
            const f = e.target.closest('[data-filter]');
            if (f) {
                filter = f.dataset.filter;
                const visible = loads(ctx);
                if (!visible.find((l) => l.id === selected) && visible[0]) selected = visible[0].id;
                tilt.show(markersFor(ctx), focusFor(ctx));
                paint(ctx);
                placeEta(ctx);
                return;
            }

            const c = e.target.closest('[data-load]');
            if (c) return choose(ctx, Number(c.dataset.load));

            const go = e.target.closest('[data-goto]');
            if (go) return XS.Laptop.go(go.dataset.goto);

            const wp = e.target.closest('[data-waypoint]');
            if (wp) {
                const l = ctx.board.loads.find((x) => x.id === Number(wp.dataset.waypoint));
                const target = l && (l.remotePickup ? l.origin : l.stops[0]);
                if (target) {
                    XS.post('waypoint', target);
                    XS.toast('GPS set.', 'success');
                }
                return;
            }

            const open = e.target.closest('[data-crew-open]');
            if (open) return crewAction(open, () => XS.rpc('crewOpen', ctx.board.spot.id, Number(open.dataset.crewOpen)), 'Crew started. Others can join from this laptop.');

            const join = e.target.closest('[data-crew-join]');
            if (join) return crewAction(join, () => XS.rpc('crewJoin', Number(join.dataset.crewJoin), join.dataset.role), 'You are in the crew.');

            const kick = e.target.closest('[data-crew-kick]');
            if (kick) return crewAction(kick, () => XS.rpc('crewKick', Number(kick.dataset.crewKick)), 'Taken off the crew.');

            const leave = e.target.closest('[data-crew-leave]');
            if (leave) {
                const mineNow = myCrew(ctx);
                const lead = mineNow && mineNow.lead === ctx.board.me;
                if (lead && mineNow.members.length > 1) {
                    const sure = await XS.ask({ title: 'Call the crew off?', text: 'Everyone in it is sent back to the board.', confirm: 'Call it off', danger: true });
                    if (!sure) return;
                }
                return crewAction(leave, () => XS.rpc('crewLeave'), lead ? 'Crew called off.' : 'You left the crew.');
            }

            const start = e.target.closest('[data-crew-start]');
            if (start) {
                if (busy) return;
                busy = true;
                start.classList.add('off');
                const res = await XS.rpc('crewStart');
                busy = false;
                if (res.ok) {
                    XS.toast('Rolling out. Your trucks are in the bays.', 'success');
                    XS.close();
                } else {
                    start.classList.remove('off');
                    XS.toast(res.error, 'error');
                }
                return;
            }

            const take = e.target.closest('[data-take]');
            if (take) {
                const l = ctx.board.loads.find((x) => x.id === Number(take.dataset.take));
                if (l && l.illegal) {
                    const sure = await XS.ask(l.guards
                        ? { title: 'Hit a guarded trailer?', text: 'Armed guards protect it and shots bring the police. Heat builds with every run.', confirm: 'Hit it', danger: true }
                        : { title: 'Take an illegal load?', text: 'The police might get a tip about your truck. Heat builds with every run.', confirm: 'Take it', danger: true });
                    if (!sure) return;
                }
                take.classList.add('off');
                const res = await XS.rpc('take', ctx.board.spot.id, Number(take.dataset.take));
                if (res.ok) {
                    XS.toast('Load taken. Your truck is ready.', 'success');
                    XS.close();
                } else {
                    take.classList.remove('off');
                    XS.toast(res.error, 'error');
                }
            }
        };
    }

    function crew() {
        refreshCrews(true);
    }

    function leave() {
        clearTimeout(etaTimer);
        clearInterval(poll);
        poll = null;
    }

    return { render, leave, crew };
})();
