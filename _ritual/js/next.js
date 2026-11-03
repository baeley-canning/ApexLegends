(function () {
  var b = document.getElementById('countryDobNextBtn');
  if (!b) return 'gone';
  ['mousedown', 'mouseup', 'click'].forEach(function (t) {
    b.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window }));
  });
  return 'clicked: ' + b.getAttribute('href');
})()
