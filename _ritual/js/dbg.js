(function () {
  var b = document.getElementById('basicInfoNextBtn');
  var o = [];
  o.push('url=' + location.href);
  o.push('href=' + (b ? b.getAttribute('href') : 'gone'));
  var f = document.getElementById('reg-form');
  o.push('form=' + (f ? f.getAttribute('action') : 'nof'));
  o.push('verification=' + (document.getElementById('reg-form-verification') || {}).value);
  var errs = [];
  document.querySelectorAll('[class*=error],[id*=error],[role=alert]').forEach(function (e) {
    var t = (e.innerText || '').trim();
    if (t && e.offsetParent) errs.push(t.slice(0, 80));
  });
  o.push('errors=' + JSON.stringify(errs));
  o.push('cap=' + (document.querySelector('iframe[src*=captcha],iframe[src*=arkose],iframe[src*=hcaptcha]') || {}).src);
  return o.join('\n');
})()
