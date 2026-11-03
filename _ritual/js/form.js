(function () {
  var o = [];
  document.querySelectorAll('input,button,a').forEach(function (e, i) {
    o.push(i + '|' + e.tagName + '|type=' + (e.type || '') + '|id=' + e.id + '|vis=' + (e.offsetParent ? 1 : 0) + '|val=' + (e.value || '').slice(0, 40) + '|txt=' + (e.innerText || '').trim().slice(0, 20));
  });
  return o.join('\n');
})()
