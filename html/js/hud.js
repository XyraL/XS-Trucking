XS.Hud = (() => {
    let last = null;
    let built = false;

    const STAGE_ICON = { hookup: 'loads', enroute: 'flag', return: 'check', escort: 'shield' };

    function build() {
        const root = XS.$('#hud');
        root.innerHTML = `<div class="hudbar">
            <div class="hudstage"></div>
            <div class="grow"><div class="hudobj"></div><div class="hudsub"></div></div>
            <div class="dots"></div>
            <div class="hudtime"></div>
            <div class="hudmeta">
                <div class="row" data-m="fuel"><span>FUEL</span><span class="bar"><i></i></span><span class="pct mono"></span></div>
                <div class="row" data-m="close"><span>CLOSE</span><span class="bar"><i></i></span><span class="pct mono"></span></div>
            </div>
            <div class="huddist"></div>
        </div>`;
        built = true;
    }

    function meter(root, key, value, cls) {
        const row = root.querySelector(`[data-m="${key}"]`);
        if (value == null) {
            row.classList.add('hidden');
            return;
        }
        row.classList.remove('hidden');
        const pct = Math.max(0, Math.min(100, Math.round(value)));
        row.querySelector('.bar i').style.width = `${pct}%`;
        row.querySelector('.bar').className = `bar ${cls}`;
        row.querySelector('.pct').textContent = `${pct}%`;
    }

    function sub(data) {
        const parts = [data.label || ''];
        if (data.role === 'escort') {
            if (data.stage === 'escort' && data.leadName) parts.push(`following ${data.leadName}`);
            if (data.stage === 'escort' && data.inRange != null) parts.push(data.inRange ? 'in range' : 'out of range');
        } else {
            if (data.cargo) parts.push(data.cargo);
            if (data.stage === 'hookup' && !data.hitched) parts.push('not hitched');
            if (data.crew && data.crew.trucks > 1) parts.push(`convoy ${data.crew.delivered}/${data.crew.trucks} in`);
            if (data.codriver) parts.push(`with ${data.codriver}`);
        }
        return parts.filter(Boolean).join(' · ');
    }

    function update(data) {
        const root = XS.$('#hud');
        last = data || null;
        if (XS.Pages.run && XS.Pages.run.live) XS.Pages.run.live(last);

        if (!data) {
            root.classList.remove('show');
            return;
        }
        if (!built) build();

        const role = data.role || 'driver';
        const bar = root.querySelector('.hudbar');
        bar.classList.toggle('red', !!data.tipped);
        bar.classList.toggle('far', role === 'escort' && data.inRange === false);
        bar.dataset.role = role;

        root.querySelector('.hudstage').innerHTML = XS.icon(role === 'codriver' ? 'users' : STAGE_ICON[data.stage] || 'loads');
        root.querySelector('.hudobj').textContent = data.tipped ? 'Reported! ' + (data.objective || '') : (data.objective || '');
        root.querySelector('.hudsub').textContent = sub(data);
        root.querySelector('.huddist').textContent = data.distance != null ? XS.metres(data.distance) : '';

        const dots = [];
        if (role !== 'escort') {
            for (let i = 1; i <= (data.stops || 1); i++) {
                const done = data.stage === 'return' || (data.stage === 'enroute' && i < data.stop);
                const now = data.stage === 'enroute' && i === data.stop;
                dots.push(`<i class="${done ? 'done' : now ? 'now' : ''}"></i>`);
            }
        }
        root.querySelector('.dots').innerHTML = dots.join('');

        const time = root.querySelector('.hudtime');
        time.innerHTML = data.deadline != null && data.stage !== 'return' && role !== 'escort'
            ? `<div class="hudtimer${data.deadline < 0 ? ' late' : ''}">${data.deadline < 0 ? 'LATE' : XS.clock(data.deadline)}</div>` : '';

        const fuel = data.fuel != null ? Math.round(data.fuel) : null;
        meter(root, 'fuel', fuel, fuel == null ? '' : fuel < 20 ? 'bad' : fuel < 40 ? 'warn' : 'good');

        const presence = role === 'escort' && data.stage === 'escort' && data.crew ? data.crew.presence : null;
        const needed = data.presenceNeed || 0;
        meter(root, 'close', presence, presence == null ? '' : presence >= needed ? 'good' : presence >= needed / 2 ? 'warn' : 'bad');

        root.querySelector('.hudmeta').classList.toggle('hidden', fuel == null && presence == null);
        root.classList.add('show');
    }

    return { update, last: () => last };
})();

XS.Receipt = (() => {
    let timer = null;

    const LABELS = { hot: 'Hot load', truck: 'Own truck', trailer: 'Own trailer', multi: 'Multi-drop', rating: 'Rating', skills: 'Skills', dock: 'Dock Master', business: 'Business perks', convoy: 'Convoy' };

    function driverLines(r) {
        const lines = Object.entries(r.parts || {})
            .filter(([, v]) => Number(v))
            .map(([k, v]) => `<span>${XS.esc(LABELS[k] || k)}<b class="${v < 0 ? 'bad' : 'good'}">${v > 0 ? '+' : ''}${v}%</b></span>`);
        lines.unshift(`<span>Base pay<b>${XS.money(r.base)}</b></span>`);
        if (r.business > 0) lines.push(`<span>To the business<b>${XS.money(r.business)}</b></span>`);
        lines.push(`<span>Driving score<b>${r.score}/100</b></span>`);
        lines.push(`<span>XP<b class="accent">+${XS.num(r.xp)}</b></span>`);
        return lines;
    }

    function sideLines(r) {
        const lines = [];
        if (r.role === 'codriver') {
            lines.push(`<span>Rode with<b>${XS.esc(r.driverName || '')}</b></span>`);
            lines.push(`<span>Driving score<b>${r.score}/100</b></span>`);
        } else {
            lines.push(`<span>Close to the convoy<b>${r.presence}%</b></span>`);
        }
        lines.push(`<span>XP<b class="accent">+${XS.num(r.xp)}</b></span>`);
        return lines;
    }

    function kicker(r) {
        if (r.role === 'codriver') return 'Co-driver pay';
        if (r.role === 'escort') return 'Escort pay';
        return r.illegal ? 'Dropped off, no questions' : 'Delivered';
    }

    function show(r) {
        const root = XS.$('#receipt');
        if (!r) return;
        clearTimeout(timer);

        const side = r.role === 'codriver' || r.role === 'escort';
        const lines = side ? sideLines(r) : driverLines(r);

        const notes = [];
        if (r.late) notes.push('Late: paid less');
        if (r.fragile && r.score < 100) notes.push('Fragile: damage cost pay');
        if (r.dock > 0) notes.push(`Docked ${r.dock}% clean`);

        root.innerHTML = `<div class="rcard${r.illegal ? ' illegal' : ''}${side ? ' side' : ''}">
            <div class="row between"><div><div class="kicker" style="${r.illegal ? 'color:var(--red)' : side ? 'color:var(--violet)' : 'color:var(--green)'}">${kicker(r)}</div>
                <h3>${XS.esc(r.label)}</h3></div><span class="dim">${side ? '' : `${XS.dist(r.km)} · `}${r.minutes} min</span></div>
            <div class="pay" data-pay>${XS.money(0)}</div>
            ${r.item ? `<div class="dim">Paid as ${XS.esc(r.item)}</div>` : ''}
            <div class="rlines">${lines.join('')}</div>
            ${notes.length ? `<div class="dim" style="font-size:12px">${notes.map(XS.esc).join(' · ')}</div>` : ''}
            ${r.leveled ? `<div class="levelup">Level ${r.level}${r.title ? ` · ${XS.esc(r.title)}` : ''} · new skill point</div>` : ''}
        </div>`;

        root.classList.add('show');
        XS.countUp(root.querySelector('[data-pay]'), r.driver, { duration: 1400 });
        timer = setTimeout(() => root.classList.remove('show'), 9000);
    }

    return { show };
})();
