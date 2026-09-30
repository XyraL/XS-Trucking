XS.Pages.run = (() => {
    let host = null;
    let tilt = null;
    let current = null;
    let poll = null;

    const STAGES = { hookup: 'Hitching', enroute: 'On the road', return: 'Heading back', escort: 'Escorting', done: 'Delivered', gone: 'Dropped out' };

    function steps(run) {
        let out;
        let at;
        if (run.role === 'escort') {
            out = [{ label: 'Escort', icon: 'shield' }, { label: run.truckNet ? 'Return' : 'Paid', icon: 'check' }];
            at = run.stage === 'escort' ? 0 : 1;
        } else {
            out = [{ label: 'Hitch', icon: 'loads' }];
            run.stops.forEach((_, i) => out.push({ label: run.stops.length > 1 ? `Drop ${i + 1}` : 'Drop', icon: 'flag' }));
            out.push({ label: 'Return', icon: 'check' });
            at = run.stage === 'hookup' ? 0 : run.stage === 'enroute' ? run.stop : out.length - 1;
        }

        return out.map((s, i) => {
            const cls = i < at ? 'done' : i === at ? 'now' : '';
            const link = i < out.length - 1 ? `<div class="link${i < at ? ' done' : ''}"></div>` : '';
            return `<div class="step ${cls}"><i>${XS.icon(i < at ? 'check' : s.icon)}</i>${XS.esc(s.label)}</div>${link}`;
        }).join('');
    }

    function objective(run) {
        if (run.role === 'codriver') return run.stage === 'return' ? `Riding back with ${run.driverName}` : `Riding with ${run.driverName}`;
        if (run.role === 'escort') return run.stage === 'escort' ? 'Keep the convoy safe' : 'Bring the pilot car back';
        if (run.stage === 'hookup') return 'Hitch the trailer';
        if (run.stage === 'enroute') return run.stops.length > 1 ? `Deliver drop ${run.stop} of ${run.stops.length}` : 'Deliver the load';
        return 'Bring the truck back';
    }

    function hint(run) {
        if (run.role === 'codriver') {
            return run.stage === 'return'
                ? 'The load is off. You are paid when the truck is handed back.'
                : 'Stay in the cab until the last drop. You are paid when the truck is handed back.';
        }
        if (run.role === 'escort') {
            return run.stage === 'escort'
                ? `Stay within ${XS.metres(run.escortRange)} of a truck for ${run.escortPresence}% of the trip to be paid in full.`
                : 'Park it in a return bay at any trucking spot and press E to get paid.';
        }
        if (run.stage === 'hookup') return 'Back the truck under the trailer. It hitches on its own.';
        if (run.stage === 'enroute') return 'Reverse the trailer into the drop zone and press E. Line it up with the arrow for a Dock Master bonus.';
        return 'Park in a return bay at any trucking spot and press E to get paid.';
    }

    function tips(run) {
        if (run.role === 'codriver') {
            return [
                ['users', 'You are in the cab at the final drop. Out of the cab means no pay.'],
                ['shield', 'Your driver drives clean. Your XP follows theirs.'],
            ];
        }
        if (run.role === 'escort') {
            return [
                ['shield', 'You stay close. Pay drops the longer you are out of range.'],
                ['route', 'You run ahead and hold junctions so the trucks keep rolling.'],
                ['check', 'At least one truck delivers. If none do, there is no escort pay.'],
            ];
        }

        const out = [];
        if (run.stage === 'hookup') out.push(['loads', 'Reverse slowly so the fifth wheel lines up. The trailer hitches on its own.']);
        if (run.stage !== 'return') out.push(['flag', 'Back the trailer in straight, along the arrow at the drop, for the Dock Master bonus.']);
        if (run.convoy) out.push(['users', 'The whole convoy delivers close together. Every other truck adds to your pay.']);
        if (run.deadline) out.push(['clock', 'It gets there before the timer runs out. Late loads pay less.']);
        if (run.fragile) out.push(['warn', 'It stays in one piece. Every knock on a fragile load costs pay.']);
        out.push(['shield', 'You drive clean. Damage lowers your rating, and a high rating pays a bonus on every load.']);
        if (run.illegal) out.push(['warn', 'Nobody reports it. If they do, keep moving and lose the police before the drop.']);
        if (run.stage === 'return') out.push(['check', 'You park in any trucking spot\'s return bays. That is when you get paid.']);
        return out;
    }

    function share(ctx, run) {
        const t = ctx.board.coop || {};
        if (run.role === 'codriver') return Math.floor(run.pay * (t.codriverCut || 0) / 100);
        if (run.role === 'escort') return Math.floor(run.pay * (t.escortCut || 0) / 100);
        return run.pay;
    }

    function xpFor(ctx, run) {
        const t = ctx.board.coop || {};
        if (run.role === 'codriver') return Math.floor(run.xp * (t.codriverXp || 0) / 100);
        if (run.role === 'escort') return Math.floor(run.xp * 0.5);
        return run.xp;
    }

    function crewPanel(run) {
        const crew = run.crew || [];
        if (!crew.length) return '';
        const trucks = crew.filter((m) => m.role === 'driver');
        const delivered = trucks.filter((m) => m.delivered).length;
        const rows = crew.map((m) => {
            const stage = m.delivered ? 'done' : m.stage;
            let extra = '';
            if (m.role === 'escort' && m.presence != null) extra = ` · ${m.presence}% close`;
            else if (stage === 'enroute' && run.stops.length > 1) extra = ` · drop ${m.stop}`;
            return `<div class="seat on ${m.role}${m.me ? ' self' : ''}"><span class="si">${XS.icon(m.role === 'escort' ? 'shield' : 'truck')}</span>
                <div class="grow"><b>${XS.esc(m.name)}${m.me ? ' (you)' : ''}</b><small>${STAGES[stage] || XS.esc(stage)}${extra}</small></div></div>`;
        }).join('');
        return `<div class="row between"><span class="kicker">Convoy</span><span class="dim" style="font-size:12px">${delivered}/${trucks.length} delivered</span></div>
            <div class="seats">${rows}</div>`;
    }

    function codriverRow(ctx, run) {
        if (run.role === 'codriver') return `<div class="row"><span class="grow dim">Driver: ${XS.esc(run.driverName)}</span><span class="chip green">Riding along</span></div>`;
        if (run.role !== 'driver' || !(ctx.board.coop || {}).codriver) return '';
        if (run.codriver) return `<div class="row"><span class="grow dim">Co-driver: ${XS.esc(run.codriver.name)}</span><span class="chip green">In the crew</span></div>`;
        if (!run.canInvite) return '';
        return `<div class="row"><span class="grow dim">No co-driver. They earn ${(ctx.board.coop || {}).codriverCut}% on top of your pay.</span>
                <button class="btn sm" data-invite>${XS.icon('plus')}Invite</button></div><div data-nearby></div>`;
    }

    function cancelLabel(run) {
        if (run.role === 'codriver') return 'Leave the cab';
        if (run.role === 'escort') return 'Stop escorting';
        return 'Drop this load';
    }

    function markersFor(ctx, run) {
        const laptop = ctx.board.spot.laptop;
        const home = run.stage === 'return';
        const tone = run.illegal ? 'red' : 'cyan';
        const out = [{ type: 'depot', x: laptop.x, y: laptop.y, icon: 'loads', tone: home ? 'green' : 'white', active: home, label: ctx.board.spot.name }];
        if (run.stage === 'hookup' && run.target) {
            out.push({ type: 'pickup', x: run.target.x, y: run.target.y, icon: 'pin', tone: 'amber', active: true, label: 'Your trailer' });
        }
        run.stops.forEach((s, i) => {
            const n = i + 1;
            const done = home || (run.stage === 'enroute' && n < run.stop);
            const now = (run.stage === 'enroute' || run.stage === 'escort') && n === run.stop;
            out.push({
                type: 'drop', x: s.x, y: s.y, tone, active: now, done, icon: done ? 'check' : null,
                number: !done && run.stops.length > 1 ? n : null, label: run.stops.length > 1 ? `Drop ${n}` : 'Drop point',
            });
        });
        return out;
    }

    function empty() {
        return `<div class="glass" style="height:100%;display:grid;place-items:center"><div class="empty">${XS.icon('run')}<h3>You are not on a load</h3>
            <p>Pick one on the Loads page. Your truck will be waiting in a bay.</p><button class="btn primary" data-goto="loads">${XS.icon('loads')}See loads</button></div></div>`;
    }

    function paintLive() {
        if (!host || !current) return;
        const run = current.board.run;
        if (!run) return;
        const crew = host.querySelector('[data-crew]');
        if (crew) {
            const html = crewPanel(run);
            crew.innerHTML = html;
            crew.classList.toggle('hidden', !html);
        }
        const co = host.querySelector('[data-codriver]');
        if (co && !co.querySelector('[data-nearby] button')) co.innerHTML = codriverRow(current, run);
    }

    async function refreshRun() {
        if (!host || !current || !XS.Laptop.ctx.open || XS.Laptop.ctx.page !== 'run' || !current.board.run) return;
        const res = await XS.rpc('run');
        if (!res.ok || !res.data || !host) return;
        if (res.data.id !== current.board.run.id) return;
        res.data.role = res.data.role || 'driver';
        current.board.run = res.data;
        paintLive();
    }

    function render(el, ctx) {
        host = el;
        current = ctx;
        clearInterval(poll);
        const run = ctx.board.run;
        if (!run) {
            el.innerHTML = empty();
            el.onclick = (e) => { const g = e.target.closest('[data-goto]'); if (g) XS.Laptop.go(g.dataset.goto); };
            return;
        }
        run.role = run.role || 'driver';

        const pays = share(ctx, run);
        const truckLine = run.role === 'escort' ? run.truckLabel : run.role === 'codriver' ? `${run.truckLabel} · ${run.plate}` : run.truckLabel;

        el.innerHTML = `<div class="run">
            <div class="mapcard"><div class="tiltbox"></div>
                <div class="maphead"><div><div class="kicker" style="${run.illegal ? 'color:var(--red)' : ''}">${run.role === 'escort' ? 'Escort · ' : run.role === 'codriver' ? 'Co-driver · ' : ''}${XS.esc(run.typeLabel || '')} · ${XS.esc(run.cargo || '')}</div>
                    <h1>${XS.esc(run.label)}</h1><p>From ${XS.esc(run.spotName)}${run.plate ? ` · plate ${XS.esc(run.plate)}` : ''}</p></div></div>
                <div class="glass crewfloat hidden" data-crew></div>
                <div style="position:absolute;left:24px;bottom:22px;right:24px;z-index:2" class="row between">
                    <div><div class="label">${run.role === 'escort' && run.stage === 'escort' ? 'To the convoy' : 'To go'}</div><div class="bigdist" data-live="dist">—</div></div>
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
                    <div class="tiles"><div class="tile"><small>${run.role === 'driver' ? 'Pays' : 'Your cut'}</small><b class="good">${run.role === 'driver' ? '' : '~'}${XS.money(pays)}</b></div>
                        <div class="tile"><small>XP</small><b>${run.role === 'driver' ? '+' : '~'}${XS.num(xpFor(ctx, run))}</b></div>
                        <div class="tile"><small>Weight</small><b>${run.weight} t</b></div></div>
                    <div class="row"><span class="grow dim">${run.role === 'escort' ? 'Car' : 'Truck'}: ${XS.esc(truckLine)}</span>${run.fragile ? '<span class="chip amber">Fragile</span>' : ''}${run.hot ? '<span class="chip amber">Hot</span>' : ''}${run.illegal ? '<span class="chip red">Illegal</span>' : ''}</div>
                    <div class="col" style="gap:8px" data-codriver></div>
                </div>
                <div class="glass panel col" style="flex:1;min-height:0;overflow:auto">
                    <div class="kicker">Pays more when</div>
                    ${tips(run).map((t) => `<div class="row" style="align-items:flex-start">${XS.icon(t[0])}<span class="dim">${XS.esc(t[1])}</span></div>`).join('')}
                </div>
                <div class="glass panel row">
                    <button class="btn" data-gps>${XS.icon('pin')}${run.role === 'escort' && run.stage === 'escort' ? 'GPS to the convoy' : 'GPS to the next stop'}</button>
                    <button class="btn ghost bad" data-cancel style="margin-left:auto">${XS.icon(run.role === 'driver' ? 'trash' : 'close')}${cancelLabel(run)}</button>
                </div>
            </div></div>`;

        tilt = XS.Tilt.create(el.querySelector('.tiltbox'));
        tilt.show(markersFor(ctx, run));
        paintLive();
        live(XS.Hud.last());
        if (run.crew || run.role === 'driver') poll = setInterval(refreshRun, 4000);

        el.onclick = async (e) => {
            if (e.target.closest('[data-gps]')) {
                const r = current.board.run || run;
                const target = r.stage === 'escort' ? r.leadAt : (r.target || (r.returns && r.returns[0]));
                if (target) { XS.post('waypoint', target); XS.toast('GPS set.', 'success'); }
                return;
            }

            if (e.target.closest('[data-invite]')) {
                const res = await XS.rpc('nearbyPlayers');
                const box = host.querySelector('[data-nearby]');
                if (!box) return;
                box.innerHTML = res.ok && res.data && res.data.length
                    ? `<div class="row wrap">${res.data.map((p) => `<button class="btn sm" data-rider="${p.source}">${XS.icon('plus')}${XS.esc(p.name)}</button>`).join('')}</div>`
                    : '<div class="dim" style="font-size:12px">Nobody is close enough. Stand next to them.</div>';
                return;
            }

            const rider = e.target.closest('[data-rider]');
            if (rider) {
                rider.classList.add('off');
                const res = await XS.rpc('inviteRider', Number(rider.dataset.rider));
                if (XS.result(res, 'Invite sent. They have a minute to get in.')) {
                    const box = host.querySelector('[data-nearby]');
                    if (box) box.innerHTML = '';
                } else {
                    rider.classList.remove('off');
                }
                return;
            }

            if (e.target.closest('[data-cancel]')) {
                const r = current.board.run || run;
                const ask = r.role === 'codriver'
                    ? { title: 'Leave the cab?', text: 'You stop riding along and get no pay for this load.', confirm: 'Leave' }
                    : r.role === 'escort'
                        ? { title: 'Stop escorting?', text: 'You leave the convoy and get no escort pay.', confirm: 'Stop', danger: true }
                        : { title: 'Drop this load?', text: 'The truck and trailer are taken back and there is a fee.', confirm: 'Drop it', danger: true };
                if (!(await XS.ask(ask))) return;
                const res = await XS.rpc('cancel');
                if (XS.result(res, r.role === 'driver' ? 'Load dropped.' : 'Done.')) XS.Laptop.refresh('loads');
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

    function leave() {
        clearInterval(poll);
        poll = null;
    }

    return { render, live, leave };
})();
