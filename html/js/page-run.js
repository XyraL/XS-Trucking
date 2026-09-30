XS.Pages.run = (() => {
    let host = null;
    let tilt = null;

    function steps(run) {
        const out = [{ key: 'hookup', label: 'Hitch', icon: 'loads' }];
        run.stops.forEach((_, i) => out.push({ key: `stop${i + 1}`, label: run.stops.length > 1 ? `Drop ${i + 1}` : 'Drop', icon: 'flag' }));
        out.push({ key: 'return', label: 'Return', icon: 'check' });

        const current = run.stage === 'hookup' ? 0 : run.stage === 'enroute' ? run.stop : out.length - 1;
        return out.map((s, i) => {
            const cls = i < current ? 'done' : i === current ? 'now' : '';
            const link = i < out.length - 1 ? `<div class="link${i < current ? ' done' : ''}"></div>` : '';
            return `<div class="step ${cls}"><i>${XS.icon(i < current ? 'check' : s.icon)}</i>${XS.esc(s.label)}</div>${link}`;
        }).join('');
    }

    function objective(run) {
        if (run.stage === 'hookup') return 'Hitch the trailer';
        if (run.stage === 'enroute') return run.stops.length > 1 ? `Deliver drop ${run.stop} of ${run.stops.length}` : 'Deliver the load';
        return 'Bring the truck back';
    }

    function hint(run) {
        if (run.stage === 'hookup') return 'Back the truck under the trailer. It hitches on its own.';
        if (run.stage === 'enroute') return 'Reverse the trailer into the drop zone and press E. Line it up with the arrow for a Dock Master bonus.';
        return 'Park in a return bay at any trucking spot and press E to get paid.';
    }

    function tips(run) {
        const out = [];
        if (run.stage === 'hookup') out.push(['loads', 'Reverse slowly so the fifth wheel lines up. The trailer hitches on its own.']);
        if (run.stage !== 'return') out.push(['flag', 'Back the trailer in straight, along the arrow at the drop, for the Dock Master bonus.']);
        if (run.deadline) out.push(['clock', 'It gets there before the timer runs out. Late loads pay less.']);
        if (run.fragile) out.push(['warn', 'It stays in one piece. Every knock on a fragile load costs pay.']);
        out.push(['shield', 'You drive clean. Damage lowers your rating, and a high rating pays a bonus on every load.']);
        if (run.illegal) out.push(['warn', 'Nobody reports it. If they do, keep moving and lose the police before the drop.']);
        if (run.stage === 'return') out.push(['check', 'You park in any trucking spot\'s return bays. That is when you get paid.']);
        return out;
    }

    function empty() {
        return `<div class="glass" style="height:100%;display:grid;place-items:center"><div class="empty">${XS.icon('run')}<h3>You are not on a load</h3>
            <p>Pick one on the Loads page. Your truck will be waiting in a bay.</p><button class="btn primary" data-goto="loads">${XS.icon('loads')}See loads</button></div></div>`;
    }

    function render(el, ctx) {
        host = el;
        const run = ctx.board.run;
        if (!run) {
            el.innerHTML = empty();
            el.onclick = (e) => { const g = e.target.closest('[data-goto]'); if (g) XS.Laptop.go(g.dataset.goto); };
            return;
        }

        el.innerHTML = `<div class="run">
            <div class="mapcard"><div class="tiltbox"></div>
                <div class="maphead"><div><div class="kicker" style="${run.illegal ? 'color:var(--red)' : ''}">${XS.esc(run.typeLabel || '')} · ${XS.esc(run.cargo || '')}</div>
                    <h1>${XS.esc(run.label)}</h1><p>From ${XS.esc(run.spotName)} · plate ${XS.esc(run.plate)}</p></div></div>
                <div style="position:absolute;left:24px;bottom:22px;right:24px;z-index:2" class="row between">
                    <div><div class="label">To go</div><div class="bigdist" data-live="dist">—</div></div>
                    <div data-live="timer"></div>
                </div></div>
            <div class="side">
                <div class="glass panel col" style="gap:14px">
                    <div class="kicker">Now</div>
                    <div class="objective">${XS.esc(objective(run))}</div>
                    <p>${XS.esc(hint(run))}</p>
                    <div class="track">${steps(run)}</div>
                    ${run.tipped ? `<div class="banner red">${XS.icon('warn')}<div><b>Your cargo was reported.</b><div class="dim" style="font-size:12px">The police have your plate. Keep moving.</div></div></div>` : ''}
                </div>
                <div class="glass panel col">
                    <div class="tiles"><div class="tile"><small>Pays</small><b class="good">${XS.money(run.pay)}</b></div>
                        <div class="tile"><small>XP</small><b>+${XS.num(run.xp)}</b></div>
                        <div class="tile"><small>Weight</small><b>${run.weight} t</b></div></div>
                    <div class="row"><span class="grow dim">Truck: ${XS.esc(run.truckLabel)}</span>${run.fragile ? '<span class="chip amber">Fragile</span>' : ''}${run.hot ? '<span class="chip amber">Hot</span>' : ''}${run.illegal ? '<span class="chip red">Illegal</span>' : ''}</div>
                </div>
                <div class="glass panel col" style="flex:1;min-height:0;overflow:auto">
                    <div class="kicker">Pays more when</div>
                    ${tips(run).map((t) => `<div class="row" style="align-items:flex-start">${XS.icon(t[0])}<span class="dim">${XS.esc(t[1])}</span></div>`).join('')}
                </div>
                <div class="glass panel row">
                    <button class="btn" data-gps>${XS.icon('pin')}GPS to the next stop</button>
                    <button class="btn ghost bad" data-cancel style="margin-left:auto">${XS.icon('trash')}Drop this load</button>
                </div>
            </div></div>`;

        const route = [run.stage === 'hookup' && run.target ? run.target : null, ...run.stops].filter(Boolean);
        tilt = XS.Tilt.create(el.querySelector('.tiltbox'));
        tilt.show([{ id: 1, illegal: run.illegal, points: route.length > 1 ? route : [ctx.board.spot.laptop, ...run.stops] }], 1);
        live(XS.Hud.last());

        el.onclick = async (e) => {
            if (e.target.closest('[data-gps]')) {
                const target = run.target || (run.returns && run.returns[0]);
                if (target) { XS.post('waypoint', target); XS.toast('GPS set.', 'success'); }
                return;
            }
            if (e.target.closest('[data-cancel]')) {
                const sure = await XS.ask({ title: 'Drop this load?', text: 'The truck and trailer are taken back and there is a fee.', confirm: 'Drop it', danger: true });
                if (!sure) return;
                const res = await XS.rpc('cancel');
                if (XS.result(res, 'Load dropped.')) XS.Laptop.refresh('loads');
            }
        };
    }

    function live(data) {
        if (!host || !data || XS.Laptop.ctx.page !== 'run') return;
        const dist = host.querySelector('[data-live="dist"]');
        if (dist && data.distance != null) dist.textContent = XS.metres(data.distance);
        const timer = host.querySelector('[data-live="timer"]');
        if (timer) {
            timer.innerHTML = data.deadline != null
                ? `<div class="hudtimer${data.deadline < 0 ? ' late' : ''}">${data.deadline < 0 ? 'LATE' : XS.clock(data.deadline)}</div>`
                : '';
        }
    }

    return { render, live };
})();
