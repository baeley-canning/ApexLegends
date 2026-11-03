(function () {
  var o = [];
  document.querySelectorAll('select').forEach(function (e, i) {
    o.push('SEL ' + i + ' name=' + e.name + ' id=' + e.id + ' vis=' + (e.offsetParent ? 1 : 0));
    Array.prototype.slice.call(e.options, 0, 8).forEach(function (op) {
      o.push('   opt "' + op.value + '" ' + op.text);
    });
  });
  document.querySelectorAll('button').forEach(function (e, i) {
    o.push('BTN ' + i + ' id=' + e.id + ' vis=' + (e.offsetParent ? 1 : 0) + ' txt=' + (e.innerText || '').trim());
  });
  o.push('URL ' + location.href);
  return o.join('\n');
})()
