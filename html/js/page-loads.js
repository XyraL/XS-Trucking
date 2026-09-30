XS.Pages.loads = (() => {
    let tilt = null;
    let host = null;
    let filter = 'all';
    let selected = null;
    let etaTimer = null;

    function loads(ctx) {
        const all = ctx.board.loads || [];
        return all.filter((l) => {
            if (filter === 'coop') return l.convoy || l.escorts > 0;
            if (filter === 'hot') return l.hot;
            if (filter === 'illegal') return l.illegal;
            return !l.illegal || filter === 'all';
        });
    }

    function chip(l) {
        if (l.locked) return `<span class="chip">${XS.icon('lock')}Locked</span>`;
        if (l.illegal) return '<span class="chip red">Illegal</span>';
        if (l.hot) return `<span class="chip amber">${XS.icon('hot')}Hot</span>`;
        if (l.convoy) return `<span class="chip violet">Convoy ${l.convoy.max}</span>`;
        if (l.escorts > 0) return '<span class="chip violet">Escort</span>';
        if (l.timer > 0) return `<span class="chip cyan">${XS.clock(l.timer)}</span>`;
        if (l.stops.length > 1) return `<span class="chip cyan">${l.stops.length} drops</span>`;
        return '';
    }

    function card(l) {
        const cls = ['lc', 'glass', l.id === selected ? 'on' : '', l.locked ? 'lock' : '', l.illegal ? 'illegal' : ''].join(' ');
        return `<button class="${cls}" data-load="${l.id}">
            <div class="k"><span>${XS.esc(l.typeLabel.toUpperCase())} · ${XS.esc(l.weight)} T</span>${chip(l)}</div>
            <div class="d">${XS.esc(l.label)}</div>
            <div class="f"><span>${XS.dist(l.km)} · ${l.minutes} min</span><b>${XS.money(l.pay)}</b></div>
        </button>`;
    }

    function truckCard(ctx) {
        const t = ctx.board.truck;
        const parts = t ? t.parts : { fuel: 100 };
        const label = t ? t.label : 'Depot Hauler';
        const status = t ? (t.condition <= 0 ? '<span class="chip red">Needs repair</span>' : '<span class="chip green">Ready</span>') : '<span class="chip cyan">Free</span>';
        const trailer = ctx.board.trailer;
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
        if (l.escorts > 0) reqs.push(`<span class="req">${XS.icon('users')}${l.escorts} escort${l.escorts > 1 ? 's' : ''} welcome</span>`);

        const notes = [];
        if (l.timer > 0) notes.push(`<div class="row dim">${XS.icon('clock')}Has to arrive within ${XS.clock(l.timer)} or it pays less.</div>`);
        if (l.fragile) notes.push(`<div class="row dim">${XS.icon('warn')}Fragile. Every knock costs pay.</div>`);
        if (l.remotePickup) notes.push(`<div class="row dim">${XS.icon('pin')}The trailer waits at its own pickup point.</div>`);
        if (l.convoy) notes.push(`<div class="row dim">${XS.icon('users')}Up to ${l.convoy.max} trucks can haul this one together.</div>`);

        let action;
        if (ctx.board.run) action = `<button class="btn primary" data-goto="run" style="flex:2">${XS.icon('run')}You are on a load. Open it.</button>`;
        else if (l.locked) action = `<button class="btn off" style="flex:2">${XS.icon('lock')}${XS.esc(l.locked)}</button>`;
        else action = `<button class="btn ${l.illegal ? 'danger' : 'primary'}" data-take="${l.id}" style="flex:2">${l.illegal ? 'Take it anyway' : 'Take this load'}</button>`;

        return `<div class="glass loaddetail"><div class="ld-body">
            <div><div class="kicker" style="${l.illegal ? 'color:var(--red)' : ''}">Load ${l.id} · ${XS.esc(l.typeLabel)}${l.hot ? ' · hot' : ''}${l.illegal ? ' · illegal' : ''}</div>
                <div class="ttl">${XS.esc(l.label)}</div>
                <div class="dim" style="margin-top:4px">${XS.esc(l.cargo || l.typeLabel)} · ${l.weight} tonnes${l.stops.length > 1 ? ` · ${l.stops.length} drops` : ''}</div></div>
            <div class="tiles"><div class="tile"><small>Distance</small><b>${XS.dist(l.km)}</b></div>
                <div class="tile"><small>About</small><b>${l.minutes} min</b></div>
                <div class="tile"><small>XP</small><b>+${XS.num(l.xp)}</b></div></div>
            <div class="reqs">${reqs.join('')}</div>
            ${l.illegal ? `<div class="banner red">${XS.icon('warn')}<div class="grow"><b>Someone might call it in.</b><div class="dim" style="font-size:12px">Each run adds heat, and heat makes a tip-off more likely.</div></div></div>${heatBar(p.heat || 0)}` : ''}
            ${notes.join('')}
            <div class="money">
                <div class="lines">Base pay<b>${XS.money(l.pay)}</b>${bonuses.map(([n, v]) => `<br>${XS.esc(n)} +${v}%<b></b>`).join('')}<br><span class="mute">Skills and rating add more at the drop.</span></div>
                <div class="big"><span class="label">About</span><b>${XS.money(estimate)}</b></div>
            </div>
            </div><div class="row"><button class="btn" data-waypoint="${l.id}">${XS.icon('pin')}GPS</button>${action}</div>
        </div>`;
    }

    function routesFor(ctx) {
        return (ctx.board.loads || []).map((l) => ({
            id: l.id, illegal: l.illegal,
            points: [l.origin || ctx.board.spot.laptop, ...l.stops],
        }));
    }

    function placeEta(ctx) {
        clearTimeout(etaTimer);
        const bubble = host.querySelector('.eta');
        if (!bubble) return;
        const l = (ctx.board.loads || []).find((x) => x.id === selected);
        if (!l) { bubble.style.opacity = 0; return; }
        bubble.innerHTML = `<b>${XS.esc(l.label)}</b><span>${XS.dist(l.km)} · ${l.minutes} min · ${XS.money(l.pay)}</span>`;
        bubble.style.opacity = 0;
        etaTimer = setTimeout(() => {
            const at = tilt && tilt.anchor();
            if (!at) return;
            bubble.style.left = `${at.x}px`;
            bubble.style.top = `${Math.max(90, at.y)}px`;
            bubble.style.opacity = 1;
        }, 1150);
    }

    function paint(ctx) {
        const list = loads(ctx);
        const count = (ctx.board.loads || []).filter((l) => !l.locked).length;
        const hasIllegal = (ctx.board.loads || []).some((l) => l.illegal);
        host.querySelector('.carousel').innerHTML = list.length
            ? list.map(card).join('')
            : `<div class="glass lc" style="flex:1;cursor:default">No loads match this filter.</div>`;
        host.querySelector('.maphead').innerHTML = `
            <div><h1>${count} load${count === 1 ? '' : 's'} ready</h1>
                <p>${XS.esc(ctx.board.spot.name)}${ctx.board.hotLeft ? ` · hot loads swap in ${Math.ceil(ctx.board.hotLeft / 60)} min` : ''}</p></div>
            <div class="seg">
                ${[['all', 'All'], ['coop', 'Co-op'], ['hot', 'Hot']].map(([id, label]) => `<button class="${filter === id ? 'on' : ''}" data-filter="${id}">${label}</button>`).join('')}
                ${hasIllegal ? `<button class="${filter === 'illegal' ? 'on' : ''}" data-filter="illegal">${XS.icon('warn')}Illegal</button>` : ''}
            </div>`;
        host.querySelector('.side').innerHTML = truckCard(ctx) + detail(ctx);
        const on = host.querySelector('.lc.on');
        if (on) on.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    }

    function render(el, ctx, opts) {
        host = el;
        const list = ctx.board.loads || [];
        if (!selected || !list.find((l) => l.id === selected)) {
            const first = list.find((l) => !l.locked && !l.illegal) || list[0];
            selected = first ? first.id : null;
        }
        if (opts.load) selected = opts.load;

        el.innerHTML = `<div class="loads">
            <div class="mapcard"><div class="tiltbox"></div>
                <div class="maphead"></div><div class="glass eta" style="opacity:0"></div><div class="carousel"></div></div>
            <div class="side"></div></div>`;

        tilt = XS.Tilt.create(el.querySelector('.tiltbox'));
        const carousel = el.querySelector('.carousel');
        carousel.addEventListener('wheel', (e) => {
            if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
            carousel.scrollLeft += e.deltaY;
            e.preventDefault();
        }, { passive: false });
        tilt.show(routesFor(ctx), selected, ctx.board.spot.laptop);
        paint(ctx);
        placeEta(ctx);

        el.onclick = async (e) => {
            const f = e.target.closest('[data-filter]');
            if (f) {
                filter = f.dataset.filter;
                const visible = loads(ctx);
                if (!visible.find((l) => l.id === selected) && visible[0]) {
                    selected = visible[0].id;
                    tilt.select(selected);
                    placeEta(ctx);
                }
                paint(ctx);
                return;
            }

            const c = e.target.closest('[data-load]');
            if (c) {
                selected = Number(c.dataset.load);
                tilt.select(selected);
                paint(ctx);
                placeEta(ctx);
                return;
            }

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

            const take = e.target.closest('[data-take]');
            if (take) {
                const l = ctx.board.loads.find((x) => x.id === Number(take.dataset.take));
                if (l && l.illegal) {
                    const sure = await XS.ask({ title: 'Take an illegal load?', text: 'The police might get a tip about your truck. Heat builds with every run.', confirm: 'Take it', danger: true });
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

    function leave() {
        clearTimeout(etaTimer);
    }

    return { render, leave };
})();
