XS.Pages.boards = (() => {
    let tab = 'earners';
    let boards = null;
    let history = null;

    function podium(rows, value) {
        const top = rows.slice(0, 3);
        if (!top.length) return '';
        const order = [top[1], top[0], top[2]].filter(Boolean);
        return `<div class="podium">${order.map((r) => {
            const place = rows.indexOf(r) + 1;
            return `<div class="pod p${place}"><div class="n">#${place}</div><b style="font:700 15px var(--display)">${XS.esc(r.name || 'Unknown')}</b><div class="dim" style="font-size:12px;margin-top:4px">${value(r)}</div></div>`;
        }).join('')}</div>`;
    }

    function table(rows, cols) {
        if (!rows.length) return `<div class="empty">${XS.icon('boards')}<h3>Nobody yet</h3><p>Finish a load to get on the board.</p></div>`;
        return `<table class="grid"><thead><tr><th>#</th>${cols.map((c) => `<th class="${c.r ? 'r' : ''}">${c.label}</th>`).join('')}</tr></thead>
            <tbody>${rows.map((r, i) => `<tr><td class="mono dim">${i + 1}</td>${cols.map((c) => `<td class="${c.r ? 'r mono' : ''}">${c.cell(r)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    }

    function board() {
        if (!boards) return '<div class="skel" style="height:100%"></div>';
        if (tab === 'earners') {
            return podium(boards.earners, (r) => XS.money(r.earned)) + table(boards.earners, [
                { label: 'Driver', cell: (r) => XS.esc(r.name || 'Unknown') },
                { label: 'Level', r: true, cell: (r) => r.level },
                { label: 'Loads', r: true, cell: (r) => XS.num(r.loads) },
                { label: 'Earned', r: true, cell: (r) => `<span class="good">${XS.money(r.earned)}</span>` },
            ]);
        }
        if (tab === 'week') {
            return podium(boards.week, (r) => `${r.loads} loads`) + table(boards.week, [
                { label: 'Driver', cell: (r) => XS.esc(r.name || 'Unknown') },
                { label: 'Loads', r: true, cell: (r) => XS.num(r.loads) },
                { label: 'Rating', r: true, cell: (r) => r.rating },
                { label: 'Earned', r: true, cell: (r) => `<span class="good">${XS.money(r.earned)}</span>` },
            ]);
        }
        return table(boards.businesses, [
            { label: 'Business', cell: (r) => `<span class="row"><span class="bizlogo" style="width:30px;height:30px;border-radius:9px;font-size:11px;border-width:1px;--bc:${XS.esc(r.colour)};${r.logo ? `background-image:url('${XS.esc(r.logo)}')` : ''}">${r.logo ? '' : XS.esc((r.name || '?')[0])}</span>${XS.esc(r.name)}</span>` },
            { label: 'Members', r: true, cell: (r) => r.members },
            { label: 'Loads', r: true, cell: (r) => XS.num(r.loads) },
            { label: 'This week', r: true, cell: (r) => `<span class="good">${XS.money(r.week)}</span>` },
            { label: 'Rep', r: true, cell: (r) => XS.num(r.reputation) },
        ]);
    }

    function mine() {
        if (!history) return '<div class="skel" style="height:100%"></div>';
        const series = XS.days(history.daily, 'earned');
        const total = series.reduce((s, d) => s + d.value, 0);
        const rows = history.rows.slice(0, 12).map((r) => `<div class="item">
            <div class="grow"><div class="ttl">${XS.esc(r.label)}</div><div class="sub">${XS.ago(r.ts)} · score ${r.trip_rating}${r.illegal ? ' · illegal' : ''}${r.spoiled ? ' · late' : ''}</div></div>
            <b class="mono good">${XS.money(r.driver_cut)}</b></div>`).join('');
        return `<div class="glass panel col" style="gap:12px;height:100%;min-height:0">
            <div class="row between"><div><div class="label">Last 14 days</div><div style="font:800 30px var(--display)" class="good">${XS.money(total)}</div></div>${XS.icon('chart')}</div>
            ${XS.columns(series, { h: 110 })}
            <div class="label">Recent loads</div>
            <div class="list" style="overflow:auto;min-height:0">${rows || '<div class="dim">No loads yet.</div>'}</div></div>`;
    }

    function paint(el) {
        el.querySelector('.bmain').innerHTML = `<div class="row between"><h2>Leaderboards</h2><div class="seg">
            ${[['earners', 'Top earners'], ['week', 'This week'], ['biz', 'Businesses']].map(([id, label]) => `<button class="${tab === id ? 'on' : ''}" data-tab="${id}">${label}</button>`).join('')}</div></div>
            <div class="col" style="gap:14px;overflow:auto;min-height:0">${board()}</div>`;
        el.querySelector('.bmine').innerHTML = mine();
    }

    async function render(el) {
        el.innerHTML = '<div class="boards"><div class="glass panel col bmain" style="gap:16px;min-height:0"></div><div class="bmine" style="min-height:0"></div></div>';
        paint(el);
        const [b, h] = await Promise.all([XS.rpc('leaderboards'), XS.rpc('history')]);
        boards = b.ok ? b.data : { earners: [], week: [], businesses: [] };
        history = h.ok ? h.data : { rows: [], daily: [] };
        paint(el);
        el.onclick = (e) => {
            const t = e.target.closest('[data-tab]');
            if (t) { tab = t.dataset.tab; paint(el); }
        };
    }

    return { render };
})();
