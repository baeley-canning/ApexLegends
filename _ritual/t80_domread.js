// t80_domread.js - harvest actionable DOM info from the current page.
(function () {
    var out = { url: location.href, title: document.title, inputs: [], buttons: [], links: [] };
    var els = document.querySelectorAll('input, textarea, select');
    for (var i = 0; i < els.length && i < 30; i++) {
        var e = els[i];
        out.inputs.push({
            tag: e.tagName.toLowerCase(),
            type: e.type || '',
            id: e.id || '',
            name: e.name || '',
            placeholder: e.placeholder || '',
            aria: e.getAttribute('aria-label') || '',
            visible: !!(e.offsetWidth || e.offsetHeight),
            value: (e.type === 'password') ? '***' : (e.value || '').substring(0, 40)
        });
    }
    var btns = document.querySelectorAll('button, [role=button], wf-button, input[type=submit]');
    for (var j = 0; j < btns.length && j < 25; j++) {
        var b = btns[j];
        out.buttons.push({
            id: b.id || '', cls: (b.className || '').toString().substring(0, 50),
            txt: (b.textContent || b.innerText || b.value || '').trim().replace(/\s+/g, ' ').substring(0, 60),
            visible: !!(b.offsetWidth || b.offsetHeight), disabled: !!b.disabled
        });
    }
    var anch = document.querySelectorAll('a[href]');
    for (var k = 0; k < anch.length; k++) {
        var a = anch[k];
        var href = a.href || '';
        if (href.indexOf('create') >= 0 || (a.textContent || '').toLowerCase().indexOf('create') >= 0 ||
            (a.textContent || '').toLowerCase().indexOf('sign up') >= 0) {
            out.links.push({ href: href.substring(0, 120), txt: (a.textContent || '').trim().substring(0, 60) });
        }
    }
    return JSON.stringify(out);
})();
