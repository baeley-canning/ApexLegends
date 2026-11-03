(function () {
  function pick(id, v) {
    var e = document.getElementById(id);
    if (!e) return id + '=MISSING';
    e.focus();
    e.value = v;
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    e.blur();
    return id + '=' + e.value;
  }
  var r = [];
  r.push(pick('clientreg_country-selctrl', 'NZ'));
  r.push(pick('clientreg_dobmonth-selctrl', '3'));
  r.push(pick('clientreg_dobday-selctrl', '14'));
  r.push(pick('clientreg_dobyear-selctrl', '1996'));
  var btn = Array.prototype.slice.call(document.querySelectorAll('button')).filter(function (b) {
    return /NEXT/i.test(b.innerText || '') && b.offsetParent;
  })[0];
  r.push('NEXT found=' + !!btn + ' disabled=' + (btn ? btn.disabled : 'n/a'));
  if (btn) btn.click();
  return r.join('\n');
})()
