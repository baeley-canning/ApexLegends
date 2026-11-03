(function () {
  var e = document.getElementById('email');
  var b = document.getElementById('basicInfoNextBtn');
  if (e) {
    e.focus();
    ['keydown', 'keyup'].forEach(function (t) {
      e.dispatchEvent(new KeyboardEvent(t, { key: 'a', bubbles: true }));
    });
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    e.blur();
  }
  if (b) b.click();
  return 'clicked ' + location.href;
})()
