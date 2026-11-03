(function () {
  var code = '087367';
  var boxes = Array.prototype.filter.call(document.querySelectorAll('input'), function (e) {
    return e.offsetParent && (e.type === 'text' || e.type === 'tel' || e.type === 'number');
  });
  var r = ['boxes=' + boxes.length];
  boxes.forEach(function (e, i) {
    e.focus();
    var ch = code[i] || '';
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(e, ch);
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    e.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
    r.push(e.id + '=' + e.value);
  });
  var btn = Array.prototype.filter.call(document.querySelectorAll('a,button'), function (b) {
    return /next/i.test(b.innerText || '') && b.offsetParent;
  })[0];
  r.push('btn=' + (btn ? btn.id : 'none'));
  if (btn) btn.click();
  return r.join('\n');
})()
