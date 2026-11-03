(function () {
  var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  function put(id, v) {
    var e = document.getElementById(id);
    if (!e) return id + '=miss';
    e.focus();
    setter.call(e, v);
    e.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    e.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
    e.blur();
    return id + '=' + e.value;
  }
  var r = [];
  r.push(put('originId', 'kern30120'));
  r.push(put('password', '7sp0OTh5RBydZQ64j1vX!Q7z'));
  var cb = document.getElementById('readAccept');
  if (cb && !cb.checked) { cb.click(); }
  r.push('checked=' + (cb ? cb.checked : 'nocb'));
  var b = document.getElementById('basicInfoNextBtn');
  r.push('btn=' + (b ? b.innerText.trim() : 'none'));
  if (b) b.click();
  return r.join('\n');
})()
