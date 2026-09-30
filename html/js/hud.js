XS.Hud = (() => {
    let last = null;
    let built = false;

    const STAGE_ICON = { hookup: 'loads', enroute: 'flag', return: 'check' };

    function build() {
        const root = XS.$('#hud');
        root.innerHTML = `<div class="hudbar">
            <div class="hudstage"></div>
            <div class="grow"><div class="hudobj"></div><div class="hudsub"></div></div>
            <div class="dots"></div>
            <div class="hudtime"></div>
            <div class="hudmeta"><div class="row"><span>FUEL</span><span class="bar"><i></i></span><span class="fuelpct mono"></span></div></div>
            <div class="huddist"></div>
        </div>`;
        built = true;
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

        const bar = root.querySelector('.hudbar');
        bar.classList.toggle('red', !!data.tipped);
        root.querySelector('.hudstage').innerHTML = XS.icon(STAGE_ICON[data.stage] || 'loads');
        root.querySelector('.hudobj').textContent = data.tipped ? 'Reported! ' + (data.objective || '') : (data.objective || '');
        root.querySelector('.hudsub').textContent = `${data.label || ''}${data.cargo ? ` · ${data.cargo}` : ''}${data.stage === 'hookup' && !data.hitched ? ' · not hitched' : ''}`;
        root.querySelector('.huddist').textContent = data.distance != null ? XS.metres(data.distance) : '';

        const dots = [];
        for (let i = 1; i <= (data.stops || 1); i++) {
            const done = data.stage === 'return' || (data.stage === 'enroute' && i < data.stop);
            const now = data.stage === 'enroute' && i === data.stop;
            dots.push(`<i class="${done ? 'done' : now ? 'now' : ''}"></i>`);
        }
        root.querySelector('.dots').innerHTML = dots.join('');

        const time = root.querySelector('.hudtime');
        time.innerHTML = data.deadline != null && data.stage !== 'return'
            ? `<div class="hudtimer${data.deadline < 0 ? ' late' : ''}">${data.deadline < 0 ? 'LATE' : XS.clock(data.deadline)}</div>` : '';

        const meta = root.querySelector('.hudmeta');
        if (data.fuel != null) {
            meta.classList.remove('hidden');
            const fuel = Math.round(data.fuel);
            const i = meta.querySelector('.bar i');
            i.style.width = `${fuel}%`;
            meta.querySelector('.bar').className = `bar ${fuel < 20 ? 'bad' : fuel < 40 ? 'warn' : 'good'}`;
            meta.querySelector('.fuelpct').textContent = `${fuel}%`;
        } else {
            meta.classList.add('hidden');
        }

        root.classList.add('show');
    }

    return { update, last: () => last };
})();

XS.Receipt = (() => {
    let timer = null;

    const LABELS = { hot: 'Hot load', truck: 'Own truck', trailer: 'Own trailer', multi: 'Multi-drop', rating: 'Rating', skills: 'Skills', dock: 'Dock Master', business: 'Business perks' };

    function show(r) {
        const root = XS.$('#receipt');
        if (!r) return;
        clearTimeout(timer);

        const lines = Object.entries(r.parts || {})
            .filter(([, v]) => Number(v))
            .map(([k, v]) => `<span>${XS.esc(LABELS[k] || k)}<b class="${v < 0 ? 'bad' : 'good'}">${v > 0 ? '+' : ''}${v}%</b></span>`);
        lines.unshift(`<span>Base pay<b>${XS.money(r.base)}</b></span>`);
        if (r.business > 0) lines.push(`<span>To the business<b>${XS.money(r.business)}</b></span>`);
        lines.push(`<span>Driving score<b>${r.score}/100</b></span>`);
        lines.push(`<span>XP<b class="accent">+${XS.num(r.xp)}</b></span>`);

        const notes = [];
        if (r.late) notes.push('Late: paid less');
        if (r.fragile && r.score < 100) notes.push('Fragile: damage cost pay');
        if (r.dock > 0) notes.push(`Docked ${r.dock}% clean`);

        root.innerHTML = `<div class="rcard${r.illegal ? ' illegal' : ''}">
            <div class="row between"><div><div class="kicker" style="${r.illegal ? 'color:var(--red)' : 'color:var(--green)'}">${r.illegal ? 'Dropped off, no questions' : 'Delivered'}</div>
                <h3>${XS.esc(r.label)}</h3></div><span class="dim">${XS.dist(r.km)} · ${r.minutes} min</span></div>
            <div class="pay" data-pay>${XS.money(0)}</div>
            ${r.item ? `<div class="dim">Paid as ${XS.esc(r.item)}</div>` : ''}
            <div class="rlines">${lines.join('')}</div>
            ${notes.length ? `<div class="dim" style="font-size:12px">${notes.map(XS.esc).join(' · ')}</div>` : ''}
            ${r.leveled ? `<div class="levelup">Level ${r.level} · ${XS.esc(r.title)} · new skill point</div>` : ''}
        </div>`;

        root.classList.add('show');
        XS.countUp(root.querySelector('[data-pay]'), r.driver, { duration: 1400 });
        timer = setTimeout(() => root.classList.remove('show'), 9000);
    }

    return { show };
})();
