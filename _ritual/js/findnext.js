(function () {
  var o = [];
  document.querySelectorAll('a,button,input[type=submit],span,div').forEach(function (e) {
    var t = (e.innerText || e.value || '').trim();
    if (t.length && t.length < 20 && /next|sign|continue/i.test(t) && e.offsetParent) {
      o.push(e.tagName + ' id=' + e.id + ' cls=' + (e.className || '').toString().slice(0, 60) + ' txt=' + t);
    }
  });
  o.push('---forms---');
  document.querySelectorAll('form').forEach(function (f, i) {
    o.push('FORM ' + i + ' id=' + f.id + ' action=' + f.action);
  });
  return o.join('\n');
})()
