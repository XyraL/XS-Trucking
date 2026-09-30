XS.Pages = {};

XS.Laptop = (() => {
    const DOCK = [
        { id: 'loads', label: 'Loads', icon: 'loads' },
        { id: 'run', label: 'My run', icon: 'run' },
        { id: 'truck', label: 'Truck', icon: 'truck' },
        { id: 'skills', label: 'Skills', icon: 'skills' },
        { id: 'certs', label: 'Certificates', icon: 'certs' },
        { id: 'business', label: 'Business', icon: 'business' },
        { id: 'boards', label: 'Leaderboards', icon: 'boards' },
    ];

    const ctx = { board: null, page: null, hour: 12, open: false };
    let root;

    function scale() {
        const s = Math.min(window.innerWidth / 1680, window.innerHeight / 945);
        document.documentElement.style.setProperty('--s', Math.max(0.5, s).toFixed(4));
    }
    window.addEventListener('resize', scale);

    function initials(name) {
        return String(name || 'XS').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
    }

    function top() {
        const b = ctx.board;
        const p = b.profile || {};
        const biz = b.business;
        const logo = biz && biz.logo ? `style="background-image:url('${XS.esc(biz.logo)}')"` : '';
        const progress = p.nextXp ? (p.xp - p.levelXp) / Math.max(1, p.nextXp - p.levelXp) : 1;
        const hh = String(ctx.hour).padStart(2, '0');

        return `
            <div class="brand">
                <div class="logo"><div ${logo}>${biz && biz.logo ? '' : XS.esc(initials(biz ? biz.name : 'X S'))}</div></div>
                <div><b>${XS.esc(biz ? biz.name : 'XS Trucking')}</b><span><i></i>${XS.esc(b.spot.name)}</span></div>
            </div>
            <div class="clock"><b>${hh}:00</b><span>${XS.esc(p.title || 'Driver')} · rating ${XS.esc(p.rating ?? 100)}</span></div>
            <div class="me">
                <div class="who"><b>${XS.esc(p.name || 'Driver')}</b><span>${XS.money(p.earned || 0)} earned</span></div>
                ${XS.ring(progress, p.level || 1, 50)}
                <button class="closer" data-close>${XS.icon('close')}</button>
            </div>`;
    }

    function dock() {
        const b = ctx.board;
        const points = b.profile && b.profile.points ? b.profile.points.available : 0;
        return DOCK.map((d) => {
            let badge = '';
            if (d.id === 'skills' && points > 0) badge = `<span class="badge">${points}</span>`;
            if (d.id === 'run' && b.run) badge = '<span class="badge live">•</span>';
            if (d.id === 'business' && !XS.state.config.business) return '';
            return `<button class="dk${ctx.page === d.id ? ' on' : ''}" data-page="${d.id}">${badge}${XS.icon(d.icon)}${d.label}</button>`;
        }).join('');
    }

    function paintChrome() {
        root.querySelector('.topbar').innerHTML = top();
        root.querySelector('.dock').innerHTML = dock();
    }

    function go(page, opts) {
        const def = XS.Pages[page];
        if (!def) return;
        ctx.page = page;
        root.querySelectorAll('.page').forEach((n) => n.classList.toggle('on', n.dataset.page === page));
        root.querySelectorAll('.dk').forEach((n) => n.classList.toggle('on', n.dataset.page === page));
        const host = root.querySelector(`.page[data-page="${page}"]`);
        def.render(host, ctx, opts || {});
    }

    async function refresh(page) {
        const res = await XS.rpc('board', ctx.board.spot.id);
        if (res.ok && res.data) {
            ctx.board = res.data;
            paintChrome();
        }
        if (page !== false) go(page || ctx.page);
    }

    function open(data) {
        root = XS.$('#laptop');
        ctx.board = data.board;
        ctx.hour = data.hour ?? 12;
        ctx.open = true;
        scale();

        root.innerHTML = `
            <div class="stage"><div class="shell">
                <div class="topbar"></div>
                <div class="pages">${DOCK.map((d) => `<section class="page" data-page="${d.id}"></section>`).join('')}</div>
                <nav class="dock glass"></nav>
            </div></div>`;

        paintChrome();
        root.classList.add('open');
        go(ctx.board.run ? 'run' : 'loads');

        root.onclick = (e) => {
            if (e.target.closest('[data-close]')) return XS.close();
            const tab = e.target.closest('[data-page]');
            if (tab && tab.classList.contains('dk')) go(tab.dataset.page);
        };
    }

    function close() {
        ctx.open = false;
        if (root) root.classList.remove('open');
        Object.values(XS.Pages).forEach((p) => p.leave && p.leave());
    }

    return { open, close, go, refresh, ctx, paintChrome };
})();
