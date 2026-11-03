(function () {
  var code = '087367';
  var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  var r = [];
  for (var i = 1; i <= 6; i++) {
    var e = document.getElementById('emailVerifyCode-' + i);
    if (!e) { r.push('miss' + i); continue; }
    e.focus();
    setter.call(e, code[i - 1]);
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    r.push(e.id + '=' + e.value);
  }
  var btn = document.getElementById('btnSendCode') || Array.prototype.filter.call(document.querySelectorAll('a,button'), function (b) { return /next/i.test(b.innerText || '') && b.offsetParent; })[0];
  r.push('btn=' + (btn ? btn.id : 'none'));
  if (btn) btn.click();
  return r.join('\n');
})()
