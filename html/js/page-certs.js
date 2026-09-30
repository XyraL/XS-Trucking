XS.Pages.certs = (() => {
    function progress(label, have, need) {
        const pct = need > 0 ? Math.min(100, (have / need) * 100) : 100;
        return `<div class="col" style="gap:6px"><div class="row between"><span class="label">${XS.esc(label)}</span>
            <span class="mono ${have >= need ? 'good' : 'dim'}">${XS.num(Math.min(have, need))} / ${XS.num(need)}</span></div>${XS.bar(pct, have >= need ? 'good' : 'xp')}</div>`;
    }

    function card(c, p) {
        const ready = p.level >= c.level && p.deliveries >= c.deliveries;
        const button = c.held
            ? '<button class="btn good off">Certified</button>'
            : ready ? `<button class="btn primary" data-earn="${c.id}">Get certified · ${XS.money(c.fee)}</button>`
                : '<button class="btn off">Not yet</button>';
        return `<div class="glass cert${c.held ? ' held' : ''}">
            <div class="seal">${XS.icon(c.held ? 'check' : 'certs')}</div>
            <div class="kicker">${c.held ? 'Held' : `From level ${c.level}`}</div>
            <h2 style="max-width:78%">${XS.esc(c.label)}</h2>
            <p style="font-size:13px">${XS.esc(c.description)}</p>
            <div class="row wrap">${(c.types || []).map((t) => `<span class="chip cyan">${XS.esc(t)}</span>`).join('') || '<span class="chip">Special routes</span>'}</div>
            ${c.held ? '' : progress('Level', p.level, c.level) + progress('Deliveries', p.deliveries, c.deliveries)}
            <div style="margin-top:auto">${button}</div>
        </div>`;
    }

    async function render(el) {
        el.innerHTML = '<div class="certs"><div class="skel" style="height:260px"></div><div class="skel" style="height:260px"></div><div class="skel" style="height:260px"></div></div>';
        const res = await XS.rpc('certs');
        if (!res.ok) { el.innerHTML = `<div class="empty">${XS.esc(res.error)}</div>`; return; }
        const { list, profile } = res.data;
        el.innerHTML = `<div class="certs">${list.map((c) => card(c, profile)).join('')}</div>`;

        el.onclick = async (e) => {
            const b = e.target.closest('[data-earn]');
            if (!b) return;
            const r = await XS.rpc('earnCert', b.dataset.earn);
            if (XS.result(r, 'Certified. New loads are open to you.')) {
                render(el);
                XS.Laptop.refresh(false);
            }
        };
    }

    return { render };
})();
