XS.Pages.skills = (() => {
    let host = null;
    let data = null;
    let chosen = null;
    let flash = null;

    function rgba(hex, a) {
        const n = parseInt(hex.slice(1), 16);
        return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
    }

    const STATS = {
        pay: 'pay', xp: 'XP', wear: 'less part wear', repair: 'off repairs and services', upgrade: 'off upgrades',
        rating: 'less rating lost to damage', dock: 'Dock Master bonus', timer: 'more time on timed loads',
        convoy: 'convoy bonus', escort: 'escort pay', cut: 'more of business loads', rep: 'business reputation',
        tipoff: 'lower tip-off chance', heatDecay: 'faster heat decay', heatGain: 'less heat per run',
    };

    function when(w) {
        if (!w) return '';
        const parts = [];
        if (w.minKm) parts.push(`on loads of ${XS.dist(w.minKm)} or more`);
        if (w.minWeight) parts.push(`on loads of ${w.minWeight} t or more`);
        if (w.night) parts.push('at night');
        if (w.illegal) parts.push('on illegal runs');
        if (w.business) parts.push('in business trucks');
        if (w.minRating) parts.push(`while your rating is ${w.minRating}+`);
        if (w.types) parts.push(`on ${w.types.join(', ')} loads`);
        return parts.length ? ` ${parts.join(' ')}` : '';
    }

    function effect(e) {
        const stat = STATS[e.stat] || e.stat;
        const sign = ['wear', 'repair', 'upgrade', 'rating', 'tipoff', 'heatGain'].includes(e.stat) ? '−' : '+';
        return `${sign}${e.value}% ${stat}${when(e.when)}`;
    }

    function skillAt(id) {
        for (const b of data.branches) {
            const s = b.skills.find((x) => x.id === id);
            if (s) return { skill: s, branch: b };
        }
        return null;
    }

    function status(skill) {
        const ranks = data.profile.skills || {};
        const rank = ranks[skill.id] || 0;
        const unmet = (skill.requires || []).filter((r) => !(ranks[r] > 0));
        return { rank, max: rank >= skill.ranks, locked: unmet.length > 0, unmet };
    }

    function node(skill, branch) {
        const st = status(skill);
        const cls = ['node', st.rank > 0 ? 'has' : '', st.max ? 'max' : '', st.locked && st.rank === 0 ? 'locked' : '', chosen === skill.id ? 'sel' : '', flash === skill.id ? 'unlock' : ''].join(' ');
        const pips = Array.from({ length: skill.ranks }, (_, i) => `<i class="${i < st.rank ? 'on' : ''}"></i>`).join('');
        return `<button class="${cls}" data-skill="${skill.id}"><b>${XS.esc(skill.label)}</b><small>${st.rank}/${skill.ranks}${st.locked && st.rank === 0 ? ' · locked' : ''}</small><div class="rk">${pips}</div></button>`;
    }

    function tree() {
        return data.branches.map((b) => {
            const vars = `--c:${b.colour};--cs:${rgba(b.colour, 0.55)};--cf:${rgba(b.colour, 0.2)};--cg:${rgba(b.colour, 0.18)}`;
            const nodes = b.skills.map((s, i) => {
                const wire = i > 0 ? `<div class="wire${status(s).rank > 0 || status(b.skills[i - 1]).rank > 0 ? ' on' : ''}"></div>` : '';
                return wire + node(s, b);
            }).join('');
            return `<div class="branch" style="${vars}"><h3><i></i>${XS.esc(b.label)}</h3>${nodes}</div>`;
        }).join('');
    }

    function detail() {
        const p = data.profile.points;
        const head = `<div class="row between"><div><div class="label">Skill points</div><div style="font:800 40px var(--display)">${p.available}</div></div>
            <div style="text-align:right" class="dim">${p.spent} spent<br>1 more each level</div></div>`;

        const found = chosen && skillAt(chosen);
        if (!found) {
            return `<div class="glass panel col" style="gap:14px">${head}<p>Pick a skill to see what it does. Each branch suits a different way of driving, and you can mix them.</p>
                <button class="btn ghost" data-respec>${XS.icon('refresh')}Reset all skills · ${XS.money(data.respecCost)}</button></div>`;
        }

        const { skill, branch } = found;
        const st = status(skill);
        const reqs = (skill.requires || []).map((r) => {
            const other = skillAt(r);
            const ok = (data.profile.skills || {})[r] > 0;
            return `<span class="req${ok ? '' : ' no'}">${XS.icon(ok ? 'check' : 'lock')}${XS.esc(other ? other.skill.label : r)}</span>`;
        }).join('');

        let button;
        if (st.max) button = '<button class="btn good off">Maxed out</button>';
        else if (st.locked) button = `<button class="btn off">${XS.icon('lock')}Unlock the skills above first</button>`;
        else if (p.available < 1) button = '<button class="btn off">No points. Level up for more.</button>';
        else button = `<button class="btn primary" data-buy="${skill.id}">${st.rank ? `Rank ${st.rank + 1}` : 'Learn it'} · 1 point</button>`;

        return `<div class="glass panel col" style="gap:14px;--c:${branch.colour}">${head}
            <div class="section"><div class="kicker" style="color:${branch.colour}">${XS.esc(branch.label)}</div>
            <h2>${XS.esc(skill.label)}</h2><p>${XS.esc(skill.description)}</p>
            <div class="col" style="gap:6px">${skill.effects.map((e) => `<div class="row">${XS.icon('spark')}<span>${XS.esc(effect(e))}${skill.ranks > 1 ? ' per rank' : ''}</span></div>`).join('')}</div>
            ${reqs ? `<div class="label">Needs</div><div class="reqs">${reqs}</div>` : ''}
            <div class="row between"><span class="dim">Rank ${st.rank} of ${skill.ranks}</span></div>${button}</div>
            <button class="btn ghost" data-respec>${XS.icon('refresh')}Reset all skills · ${XS.money(data.respecCost)}</button></div>`;
    }

    function paint() {
        host.querySelector('.tree').innerHTML = tree();
        host.querySelector('.skside').innerHTML = detail();
        flash = null;
    }

    async function render(el) {
        host = el;
        el.innerHTML = `<div class="skills"><div class="glass tree"><div class="skel" style="grid-column:1/-1;height:100%"></div></div><div class="skside"></div></div>`;
        const res = await XS.rpc('skills');
        if (!res.ok) { el.querySelector('.tree').innerHTML = `<div class="empty">${XS.esc(res.error)}</div>`; return; }
        data = res.data;
        paint();

        el.onclick = async (e) => {
            const s = e.target.closest('[data-skill]');
            if (s) { chosen = s.dataset.skill; return paint(); }

            const b = e.target.closest('[data-buy]');
            if (b) {
                const id = b.dataset.buy;
                const r = await XS.rpc('buySkill', id);
                if (!XS.result(r)) return;
                const again = await XS.rpc('skills');
                if (again.ok) data = again.data;
                flash = id;
                XS.toast('Skill learned.', 'success');
                paint();
                XS.Laptop.refresh(false);
                return;
            }

            if (e.target.closest('[data-respec]')) {
                const sure = await XS.ask({ title: 'Reset every skill?', text: `All your points come back to spend again. It costs ${XS.money(data.respecCost)}.`, confirm: 'Reset', danger: true });
                if (!sure) return;
                const r = await XS.rpc('respec');
                if (!XS.result(r, 'Skills reset.')) return;
                const again = await XS.rpc('skills');
                if (again.ok) data = again.data;
                chosen = null;
                paint();
                XS.Laptop.refresh(false);
            }
        };
    }

    return { render };
})();
