XS.close = () => {
    XS.Paths.reset();
    XS.Laptop.close();
    if (XS.Builder) XS.Builder.close();
    if (XS.Admin) XS.Admin.close();
    XS.post('close');
};

window.addEventListener('message', (event) => {
    const { action } = event.data || {};
    const data = XS.fix(event.data ? event.data.data : null);

    if (data && data.config) Object.assign(XS.state.config, data.config);

    switch (action) {
        case 'laptop': XS.Laptop.open(data); break;
        case 'builder': XS.Builder.open(data); break;
        case 'admin': XS.Admin.open(data); break;
        case 'close':
            XS.Paths.reset();
            XS.Laptop.close();
            if (XS.Builder) XS.Builder.close();
            if (XS.Admin) XS.Admin.close();
            break;
        case 'hide': XS.$$('.cab').forEach((n) => n.classList.add('hide')); break;
        case 'unhide': XS.$$('.cab').forEach((n) => n.classList.remove('hide')); break;
        case 'hud': XS.Hud.update(data); break;
        case 'receipt': XS.Receipt.show(data); break;
        case 'path': XS.Paths.store(data); break;
        case 'crew': if (XS.Pages.loads) XS.Pages.loads.crew(data); break;
        default: break;
    }
});

window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (XS.$('#modal').classList.contains('open')) return;
    if (XS.$$('.cab.open').length) XS.close();
});
