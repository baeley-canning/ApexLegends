(function () {
  var f = document.querySelector('form');
  if (f) { f.submit(); return 'submitted ' + f.id; }
  return 'noform';
})()
