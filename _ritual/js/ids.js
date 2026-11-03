(function () {
  var o = [];
  document.querySelectorAll('input,button,a[role=button],span[role=checkbox],input[type=checkbox]').forEach(function (e) {
    o.push(e.tagName + ' type=' + (e.type || '') + ' id=' + e.id + ' name=' + e.name + ' vis=' + (e.offsetParent ? 1 : 0));
  });
  return o.join('\n');
})()
