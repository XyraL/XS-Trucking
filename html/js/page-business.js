XS.Pages.business = (() => {
    let host = null;
    let biz = null;
    let section = 'overview';
    let ranksDraft = null;

    const SECTIONS = [
        { id: 'overview', label: 'Overview', icon: 'chart' },
        { id: 'members', label: 'Members', icon: 'users' },
        { id: 'ranks', label: 'Ranks & pay', icon: 'shield' },
        { id: 'bank', label: 'Bank', icon: 'bank' },
        { id: 'fleet', label: 'Fleet', icon: 'truck' },
        { id: 'perks', label: 'Perks', icon: 'spark' },
        { id: 'settings', label: 'Settings', icon: 'gear' },
    ];

    function rgba(hex, a) {
        const n = parseInt(String(hex || '#38d9ff').slice(1), 16) || 0x38d9ff;
        return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
    }

    function logo(size = 84) {
        const style = `width:${size}px;height:${size}px;--bc:${XS.esc(biz.colour)};--bg2:${rgba(biz.colour, 0.3)};${biz.logo && !biz.logoHidden ? `background-image:url('${XS.esc(biz.logo)}')` : ''}`;
        const initials = biz.name.split(/s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
        return `<div class="bizlogo" style="${style}">${biz.logo && !biz.logoHidden ? '' : XS.esc(initials)}</div>`;
    }

    function start(data) {
        return `<div class="glass" style="height:100%;display:grid;place-items:center">
            <div class="col" style="width:560px;gap:16px;text-align:center;align-items:center">
                <div class="bizlogo" style="width:96px;height:96px">${XS.icon('business')}</div>
                <h1>Start a trucking business</h1>
                <p>A team with its own trucks, a shared bank, ranks and pay cuts, perks that level up with your reputation, a logo, and a place on the leaderboards.</p>
                ${data.enabled ? `<div class="row" style="width:100%"><input class="field grow" id="biz-name" maxlength="${data.nameLength[1]}" placeholder="Business name">
                    <button class="btn primary" data-found>Start it · ${XS.money(data.foundingCost)}</button></div>
                    <div class="dim" style="font-size:12px">Or ask an owner to invite you.</div>` : '<div class="dim">Businesses are turned off on this server.</div>'}
            </div></div>`;
    }

    function overview() {
        const lvl = biz.level;
        const next = biz.nextLevel;
        const pct = next ? ((biz.reputation - lvl.rep) / Math.max(1, next.rep - lvl.rep)) * 100 : 100;
        const series = XS.days(biz.daily, 'revenue');
        const week = series.slice(-7).reduce((s, d) => s + d.value, 0);
        const top = [...biz.members].sort((a, b) => b.earned - a.earned).slice(0, 5);

        return `<div class="bizhero">${logo()}<div class="grow">
                <div class="kicker">Level ${lvl.level} · ${XS.esc(lvl.title)}</div><h1>${XS.esc(biz.name)}</h1>
                <p>${XS.esc(biz.motto || 'No motto yet.')}</p>
                <div class="row" style="margin-top:8px"><span class="grow">${XS.bar(pct, 'xp')}</span><span class="mono dim">${XS.num(biz.reputation)}${next ? ` / ${XS.num(next.rep)}` : ''} rep</span></div></div></div>
            <div class="tiles"><div class="tile"><small>Bank</small><b class="good">${XS.money(biz.bank)}</b></div>
                <div class="tile"><small>This week</small><b>${XS.money(week)}</b></div>
                <div class="tile"><small>Loads</small><b>${XS.num(biz.deliveries)}</b></div>
                <div class="tile"><small>Members</small><b>${biz.slots.members}/${biz.slots.membersMax}</b></div>
                <div class="tile"><small>Trucks</small><b>${biz.slots.fleet}/${biz.slots.fleetMax}</b></div>
                <div class="tile"><small>Perk points</small><b class="accent">${biz.perkPoints}</b></div></div>
            <div class="glass panel col" style="background:var(--glass-2)"><div class="row between"><h3>Business income, 14 days</h3><span class="dim">From members hauling business trucks</span></div>${XS.columns(series, { h: 120 })}</div>
            <div class="fgrid">
                <div class="col"><h3>Top earners</h3><div class="list">${top.map((m) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(m.name)}</div><div class="sub">${XS.esc(m.rank)} · ${m.deliveries} loads</div></div><b class="mono good">${XS.money(m.earned)}</b></div>`).join('')}</div></div>
                <div class="col"><h3>Latest</h3><div class="list">${biz.ledger.slice(0, 6).map((l) => `<div class="item"><div class="grow"><div class="ttl">${XS.esc(l.note || l.kind)}</div><div class="sub">${XS.esc(l.name)} · ${XS.ago(l.ts)}</div></div>${l.amount ? `<b class="mono ${l.amount < 0 ? 'bad' : 'good'}">${XS.money(l.amount)}</b>` : ''}</div>`).join('') || '<div class="dim">Nothing yet.</div>'}</div></div>
            </div>`;
    }

    function members() {
        const me = biz.me;
        const rankOpts = (m) => biz.ranks.map((r) => `<option value="${r.grade}" ${r.grade === m.grade ? 'selected' : ''}>${XS.esc(r.name)}</option>`).join('');
        const rows = biz.members.map((m) => `<tr>
            <td><span class="row"><span class="pulse-dot" style="${m.online ? '' : 'background:#56627a;animation:none'}"></span>${XS.esc(m.name)}${m.owner ? ' <span class="chip amber">Owner</span>' : ''}</span></td>
            <td>${me.perms.promote && !m.owner && m.citizenid !== me.citizenid ? `<select class="field sm" data-grade="${XS.esc(m.citizenid)}">${rankOpts(m)}</select>` : XS.esc(m.rank)}</td>
            <td class="r mono">${m.deliveries}</td><td class="r mono good">${XS.money(m.earned)}</td>
            <td class="r">${me.perms.kick && !m.owner && m.citizenid !== me.citizenid ? `<button class="btn xs" data-kick="${XS.esc(m.citizenid)}">Remove</button>` : ''}
                ${me.owner && !m.owner ? `<button class="btn xs" data-transfer="${XS.esc(m.citizenid)}">Make owner</button>` : ''}</td></tr>`).join('');

        return `<div class="row between"><h2>Members <span class="dim" style="font-size:15px">${biz.slots.members}/${biz.slots.membersMax}</span></h2>
                <div class="row">${me.perms.invite ? `<button class="btn primary sm" data-invite>${XS.icon('plus')}Invite someone nearby</button>` : ''}
                ${!me.owner ? '<button class="btn ghost sm bad" data-leave>Leave</button>' : ''}</div></div>
            <div data-nearby></div>
            <table class="grid"><thead><tr><th>Name</th><th>Rank</th><th class="r">Loads</th><th class="r">Earned for us</th><th></th></tr></thead><tbody>${rows}</tbody></table>`;
    }

    function ranks() {
        const can = biz.me.perms.ranks;
        ranksDraft = ranksDraft || biz.ranks.map((r) => ({ ...r, permissions: r.permissions === '*' ? '*' : Array.isArray(r.permissions) ? [...r.permissions] : [] }));
        const permKeys = Object.keys(biz.permissions);
        const rows = ranksDraft.map((r, i) => {
            const top = i === ranksDraft.length - 1;
            const perms = top
                ? '<span class="chip amber">Everything</span>'
                : permKeys.map((p) => `<span class="perm${r.permissions.includes(p) ? ' on' : ''}" ${can ? `data-perm="${i}:${p}"` : ''} title="${XS.esc(biz.permissions[p])}">${XS.esc(p)}</span>`).join('');
            return `<div class="glass panel col" style="background:var(--glass-2);gap:10px">
                <div class="row"><span class="n mono dim">#${i + 1}</span>
                    <input class="field sm grow" ${can ? '' : 'disabled'} data-rname="${i}" value="${XS.esc(r.name)}" maxlength="32">
                    <span class="label">Keeps</span><input class="field sm" style="width:80px" type="number" min="0" max="100" ${can ? '' : 'disabled'} data-rcut="${i}" value="${r.cut}"><span class="dim">%</span>
                    ${can && !top && ranksDraft.length > 2 ? `<button class="btn xs" data-rdel="${i}">${XS.icon('trash')}</button>` : ''}</div>
                <div class="row wrap" style="gap:6px">${perms}</div></div>`;
        }).join('');

        return `<div class="row between"><h2>Ranks & pay</h2>${can ? `<div class="row"><button class="btn sm" data-radd>${XS.icon('plus')}Add a rank</button><button class="btn sm primary" data-rsave>Save ranks</button></div>` : ''}</div>
            <p>"Keeps" is how much of a load's pay a driver of that rank keeps when they haul in a business truck. The rest goes to the bank. The top rank can do everything.</p>
            <div class="col">${rows}</div>`;
    }

    function bank() {
        const can = biz.me.perms.bank;
        return `<div class="row between"><div><div class="label">Balance</div><div style="font:800 44px var(--display)" class="good">${XS.money(biz.bank)}</div></div>
                ${biz.mods.deposit ? `<span class="chip green">Deposits +${biz.mods.deposit}%</span>` : ''}</div>
            <div class="fgrid"><div class="row"><input class="field" type="number" min="1" id="dep" placeholder="Amount"><button class="btn good" data-dep>Put in</button></div>
                <div class="row"><input class="field" type="number" min="1" id="wd" placeholder="Amount" ${can ? '' : 'disabled'}><button class="btn ${can ? '' : 'off'}" data-wd>Take out</button></div></div>
            <table class="grid"><thead><tr><th>What</th><th>Who</th><th>When</th><th class="r">Amount</th></tr></thead>
            <tbody>${biz.ledger.map((l) => `<tr><td>${XS.esc(l.note || l.kind)}</td><td class="dim">${XS.esc(l.name)}</td><td class="dim">${XS.ago(l.ts)}</td>
                <td class="r mono ${l.amount < 0 ? 'bad' : l.amount > 0 ? 'good' : 'dim'}">${l.amount ? XS.money(l.amount) : '—'}</td></tr>`).join('')}</tbody></table>`;
    }

    function fleet() {
        const next = biz.slots.fleetNext;
        return `<div class="row between"><h2>Fleet <span class="dim" style="font-size:15px">${biz.slots.fleet}/${biz.slots.fleetMax} trucks</span></h2>
                <button class="btn primary sm" data-go-truck>${XS.icon('truck')}Manage in the Truck page</button></div>
            <p>Business trucks are driven by any member unless reserved for one. Loads hauled in them split the pay by rank. Idle trucks can go out on fleet runs for the bank${biz.runs && biz.runs.enabled ? `, up to ${biz.runs.max + (biz.mods.runs || 0)} at a time` : ''}.</p>
            ${next ? `<div class="banner">${XS.icon('plus')}<div class="grow"><b>${next.add} more truck slots</b><div class="dim" style="font-size:12px">Paid from the bank</div></div>
                <button class="btn sm ${biz.me.perms.perks ? 'primary' : 'off'}" data-slots="fleet">${XS.money(next.cost)}</button></div>` : '<div class="chip green">Fleet fully upgraded</div>'}`;
    }

    function perks() {
        const can = biz.me.perms.perks;
        const branches = biz.perkTree.map((b) => `<div class="col"><h3>${XS.esc(b.label)}</h3>${b.tiers.map((t, i) => {
            const owned = biz.perks[t.id];
            const open = i === 0 || biz.perks[b.tiers[i - 1].id];
            return `<div class="item${owned ? ' on' : ''}"><div class="grow"><div class="ttl">${XS.esc(t.label)}</div><div class="sub">${XS.esc(t.description)}</div></div>
                ${owned ? '<span class="chip green">Unlocked</span>' : `<button class="btn xs ${can && open ? 'primary' : 'off'}" data-perk="${t.id}">${t.cost} pt</button>`}</div>`;
        }).join('')}</div>`).join('');

        const next = biz.slots.memberNext;
        return `<div class="row between"><h2>Perks</h2><span class="chip violet">${biz.perkPoints} perk point${biz.perkPoints === 1 ? '' : 's'}</span></div>
            <p>Perk points come from reputation levels. Every load a member hauls earns reputation.</p>
            <div class="fgrid">${branches}</div>
            <div class="section"><h3>Upgrades</h3>
            ${next ? `<div class="banner">${XS.icon('users')}<div class="grow"><b>${next.add} more member slots</b><div class="dim" style="font-size:12px">Now ${biz.slots.membersMax}. Paid from the bank.</div></div>
                <button class="btn sm ${can ? 'primary' : 'off'}" data-slots="members">${XS.money(next.cost)}</button></div>` : '<span class="chip green">Members fully upgraded</span>'}</div>`;
    }

    function settings() {
        const can = biz.me.perms.settings;
        return `<h2>Settings</h2>
            <div class="bizhero">${logo(96)}<div class="grow col" style="gap:8px">
                <span class="label">Logo link</span><input class="field" id="s-logo" ${can ? '' : 'disabled'} value="${XS.esc(biz.logo || '')}" placeholder="https://i.imgur.com/....png">
                <span class="dim" style="font-size:12px">A picture on ${XS.esc((XS.state.bizHosts || ['imgur.com', 'fivemanage.com']).join(' or '))}. Keep it friendly, admins can see every logo.</span>
                ${biz.logoHidden ? '<span class="chip red">An admin hid this logo</span>' : ''}</div></div>
            <div class="fgrid"><div class="fcell"><span class="label">Name</span><input class="field" id="s-name" ${can ? '' : 'disabled'} value="${XS.esc(biz.name)}"></div>
                <div class="fcell"><span class="label">Colour</span><input class="field" id="s-colour" type="color" ${can ? '' : 'disabled'} value="${XS.esc(biz.colour)}" style="height:44px;padding:4px"></div></div>
            <div class="fcell"><span class="label">Motto</span><input class="field" id="s-motto" ${can ? '' : 'disabled'} maxlength="120" value="${XS.esc(biz.motto || '')}"></div>
            <label class="check"><input type="checkbox" id="s-recruit" ${biz.recruiting ? 'checked' : ''} ${can ? '' : 'disabled'}><i></i>Looking for drivers</label>
            ${can ? '<div class="row end"><button class="btn primary" data-save-profile>Save settings</button></div>' : ''}
            ${biz.me.owner ? `<div class="section"><h3 class="bad">Close the business</h3><p>Trucks go back to whoever bought them. The bank is lost.</p>
                <div><button class="btn danger" data-disband>Close ${XS.esc(biz.name)}</button></div></div>` : ''}`;
    }

    const RENDER = { overview, members, ranks, bank, fleet, perks, settings };

    function paint() {
        host.querySelector('.biznav').innerHTML = SECTIONS.map((s) =>
            `<button class="${section === s.id ? 'on' : ''}" data-sec="${s.id}">${XS.icon(s.icon)}${s.label}</button>`).join('');
        host.querySelector('.bizbody').innerHTML = RENDER[section]();
        const preview = host.querySelector('#s-logo');
        if (preview) {
            preview.oninput = () => {
                const node = host.querySelector('.bizhero .bizlogo');
                node.style.backgroundImage = preview.value ? `url('${preview.value.replace(/'/g, '')}')` : '';
                node.textContent = preview.value ? '' : biz.name.slice(0, 2).toUpperCase();
            };
        }
    }

    async function reload() {
        const res = await XS.rpc('business');
        if (!res.ok) return false;
        biz = res.data;
        ranksDraft = null;
        return true;
    }

    async function afterChange(res, message) {
        if (!XS.result(res, message)) return;
        await reload();
        if (biz.none) return render(host);
        paint();
        XS.Laptop.refresh(false);
    }

    async function onClick(e) {
        const t = e.target.closest('button, .perm');
        if (!t) return;
        const d = t.dataset;

        if (d.found !== undefined) {
            const name = host.querySelector('#biz-name').value.trim();
            const res = await XS.rpc('foundBusiness', name);
            if (XS.result(res, 'Your business is open.')) { await reload(); section = 'overview'; render(host); XS.Laptop.refresh(false); }
            return;
        }
        if (d.sec) { section = d.sec; ranksDraft = null; return paint(); }
        if (d.goTruck !== undefined) return XS.Laptop.go('truck');
        if (d.invite !== undefined) {
            const res = await XS.rpc('nearbyPlayers');
            const box = host.querySelector('[data-nearby]');
            box.innerHTML = res.ok && res.data.length
                ? `<div class="row wrap">${res.data.map((p) => `<button class="btn sm" data-inv="${p.source}">${XS.icon('plus')}${XS.esc(p.name)}</button>`).join('')}</div>`
                : '<div class="dim">Nobody is close enough. Stand next to them.</div>';
            return;
        }
        if (d.inv) return afterChange(await XS.rpc('businessInvite', Number(d.inv)), 'Invite sent.');
        if (d.kick) {
            if (!(await XS.ask({ title: 'Remove this member?', confirm: 'Remove', danger: true }))) return;
            return afterChange(await XS.rpc('businessKick', d.kick), 'Removed.');
        }
        if (d.transfer) {
            if (!(await XS.ask({ title: 'Hand the business over?', text: 'They become the owner and you drop one rank.', confirm: 'Hand it over', danger: true }))) return;
            return afterChange(await XS.rpc('businessTransfer', d.transfer), 'They own it now.');
        }
        if (d.leave !== undefined) {
            if (!(await XS.ask({ title: 'Leave the business?', confirm: 'Leave', danger: true }))) return;
            const res = await XS.rpc('businessLeave');
            if (XS.result(res, 'You left.')) { await reload(); render(host); XS.Laptop.refresh(false); }
            return;
        }
        if (d.perm) {
            const [i, p] = d.perm.split(':');
            const list = ranksDraft[Number(i)].permissions;
            const at = list.indexOf(p);
            if (at >= 0) list.splice(at, 1); else list.push(p);
            return paint();
        }
        if (d.radd !== undefined) {
            if (ranksDraft.length >= biz.maxRanks) return XS.toast(`At most ${biz.maxRanks} ranks.`, 'error');
            ranksDraft.splice(ranksDraft.length - 1, 0, { name: 'New rank', cut: 60, permissions: [] });
            return paint();
        }
        if (d.rdel) { ranksDraft.splice(Number(d.rdel), 1); return paint(); }
        if (d.rsave !== undefined) return afterChange(await XS.rpc('businessRanks', ranksDraft), 'Ranks saved.');
        if (d.dep !== undefined) return afterChange(await XS.rpc('businessDeposit', Number(host.querySelector('#dep').value)), 'Deposited.');
        if (d.wd !== undefined) return afterChange(await XS.rpc('businessWithdraw', Number(host.querySelector('#wd').value)), 'Withdrawn.');
        if (d.perk) return afterChange(await XS.rpc('businessPerk', d.perk), 'Perk unlocked.');
        if (d.slots) return afterChange(await XS.rpc('businessSlots', d.slots), 'Upgraded.');
        if (d.saveProfile !== undefined) {
            return afterChange(await XS.rpc('businessProfile', {
                logo: host.querySelector('#s-logo').value.trim(), name: host.querySelector('#s-name').value.trim(),
                colour: host.querySelector('#s-colour').value, motto: host.querySelector('#s-motto').value.trim(),
                recruiting: host.querySelector('#s-recruit').checked,
            }), 'Saved.');
        }
        if (d.disband !== undefined) {
            if (!(await XS.ask({ title: `Close ${biz.name}?`, text: 'This cannot be undone.', confirm: 'Close it', danger: true }))) return;
            const res = await XS.rpc('businessDisband');
            if (XS.result(res, 'The business is closed.')) { await reload(); render(host); XS.Laptop.refresh(false); }
        }
    }

    function onInput(e) {
        const t = e.target;
        if (t.dataset.rname) ranksDraft[Number(t.dataset.rname)].name = t.value;
        if (t.dataset.rcut) ranksDraft[Number(t.dataset.rcut)].cut = Number(t.value) || 0;
    }

    async function onChange(e) {
        const t = e.target;
        if (t.dataset.grade) await afterChange(await XS.rpc('businessGrade', t.dataset.grade, Number(t.value)), 'Rank changed.');
    }

    async function render(el) {
        host = el;
        el.innerHTML = '<div class="skel" style="height:100%"></div>';
        if (!biz || biz.none || !el.dataset.loaded) {
            if (!(await reload())) { el.innerHTML = '<div class="empty">Could not load the business.</div>'; return; }
            el.dataset.loaded = '1';
        }

        if (biz.none) {
            XS.state.bizHosts = biz.logoHosts;
            el.innerHTML = start(biz);
        } else {
            el.innerHTML = '<div class="biz"><nav class="glass biznav"></nav><div class="glass bizbody"></div></div>';
            paint();
        }
        el.onclick = onClick;
        el.oninput = onInput;
        el.onchange = onChange;
    }

    return {
        render: (el) => { el.dataset.loaded = ''; return render(el); },
    };
})();
