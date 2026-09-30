XS.Rig = (() => {
    function tone(v) {
        if (v == null) return '#8b97ae';
        return v < 25 ? '#ff5d6c' : v < 50 ? '#ffb547' : '#3fe08f';
    }

    function pct(v) {
        return v == null ? '—' : `${Math.round(v)}%`;
    }

    function svg(parts = {}, opts = {}) {
        const p = parts || {};
        const trailer = opts.trailer;
        const eng = p.engine;
        const t = (v) => tone(v);

        return `
        <svg class="rig" viewBox="0 0 560 222" preserveAspectRatio="xMidYMid meet">
            <defs>
                <linearGradient id="rigBody" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#34405a"/><stop offset=".55" stop-color="#1b2233"/><stop offset="1" stop-color="#10151f"/></linearGradient>
                <linearGradient id="rigChrome" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e8eefb"/><stop offset=".5" stop-color="#7d8aa3"/><stop offset="1" stop-color="#cfd8ea"/></linearGradient>
                <linearGradient id="rigGlass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5ad8ff" stop-opacity=".55"/><stop offset="1" stop-color="#0d1d33" stop-opacity=".9"/></linearGradient>
                <radialGradient id="rigRim"><stop offset="0" stop-color="#e8eefb"/><stop offset=".7" stop-color="#7f8ba5"/><stop offset="1" stop-color="#3a4458"/></radialGradient>
                <filter id="rigGlow"><feGaussianBlur stdDeviation="3"/></filter>
            </defs>
            <ellipse cx="270" cy="194" rx="250" ry="9" fill="#000" opacity=".55"/>
            <rect x="248" y="12" width="9" height="112" rx="4.5" fill="url(#rigChrome)"/>
            <path d="M58 156 L58 108 Q60 94 76 92 L172 86 L180 156 Z" fill="url(#rigBody)" stroke="#38d9ff" stroke-opacity=".35"/>
            <rect x="46" y="98" width="14" height="52" rx="3" fill="url(#rigChrome)"/>
            <rect x="45" y="112" width="8" height="12" rx="2" fill="#38d9ff" filter="url(#rigGlow)" opacity=".8"/>
            <path d="M172 156 L172 86 L190 42 Q192 36 200 36 L266 36 L266 156 Z" fill="url(#rigBody)" stroke="#38d9ff" stroke-opacity=".35"/>
            <path d="M188 82 L202 48 L236 48 L236 82 Z" fill="url(#rigGlass)"/>
            <line x1="242" y1="52" x2="242" y2="150" stroke="#0a0e16" stroke-width="2"/>
            <path d="M266 156 L266 30 Q268 16 290 14 L346 14 L346 156 Z" fill="url(#rigBody)" stroke="#38d9ff" stroke-opacity=".35"/>
            <rect x="276" y="40" width="58" height="10" rx="3" fill="#0a0e16" opacity=".7"/>
            <rect x="40" y="150" width="420" height="10" rx="3" fill="#0c1018"/>
            <rect x="190" y="130" width="66" height="26" rx="13" fill="url(#rigChrome)"/>
            <rect x="364" y="140" width="50" height="10" rx="3" fill="${trailer ? '#8f7dff' : '#ffb547'}"/>
            <rect x="36" y="140" width="22" height="24" rx="5" fill="url(#rigChrome)"/>
            ${[108, 376, 444].map((cx) => `<g><circle cx="${cx}" cy="164" r="31" fill="#0a0d13" stroke="#2c3547" stroke-width="3"/><circle cx="${cx}" cy="164" r="15" fill="url(#rigRim)"/><circle cx="${cx}" cy="164" r="5" fill="#1b2233"/></g>`).join('')}
            <rect x="478" y="146" width="7" height="36" rx="2" fill="#0c1018"/>
            <g font-family="Inter, sans-serif" font-size="12" font-weight="600">
                <circle cx="118" cy="112" r="5" fill="${t(eng)}"/><circle cx="118" cy="112" r="10" fill="none" stroke="${t(eng)}" stroke-opacity=".4"/>
                <path d="M118 112 L118 30 L140 30" stroke="${t(eng)}" stroke-opacity=".6" fill="none"/>
                <text x="146" y="26" fill="#e9eefb">ENGINE <tspan fill="${t(eng)}">${pct(eng)}</tspan></text>
                <text x="146" y="41" fill="#8b97ae" font-size="11" font-weight="500">${XS.esc(opts.engineNote || (p.oil != null ? `Oil ${pct(p.oil)}` : 'Depot truck'))}</text>

                <circle cx="223" cy="143" r="5" fill="${t(p.fuel)}"/>
                <path d="M223 143 L223 210 L200 210" stroke="${t(p.fuel)}" stroke-opacity=".6" fill="none"/>
                <text x="194" y="214" text-anchor="end" fill="#e9eefb">FUEL <tspan fill="${t(p.fuel)}">${pct(p.fuel)}</tspan></text>

                <circle cx="108" cy="164" r="5" fill="${t(p.tyres)}"/>
                <path d="M100 172 L60 210 L40 210" stroke="${t(p.tyres)}" stroke-opacity=".6" fill="none"/>
                <text x="4" y="206" fill="#e9eefb" font-size="11">TYRES</text><text x="4" y="220" fill="${t(p.tyres)}" font-size="12">${pct(p.tyres)}</text>

                <circle cx="410" cy="164" r="5" fill="${t(p.brakes)}"/>
                <path d="M410 172 L410 210 L430 210" stroke="${t(p.brakes)}" stroke-opacity=".6" fill="none"/>
                <text x="436" y="214" fill="#e9eefb">BRAKES <tspan fill="${t(p.brakes)}">${pct(p.brakes)}</tspan></text>

                <circle cx="300" cy="96" r="5" fill="${t(opts.body)}"/>
                <path d="M300 96 L330 70 L420 70" stroke="${t(opts.body)}" stroke-opacity=".6" fill="none"/>
                <text x="426" y="66" fill="#e9eefb">BODY</text><text x="426" y="81" fill="${t(opts.body)}" font-size="11">${pct(opts.body)}</text>
            </g>
        </svg>`;
    }

    return { svg, tone };
})();
