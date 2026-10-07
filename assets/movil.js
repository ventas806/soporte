/* ─────────────────────────────────────────────────────────────
   Vista celular — botón ☰ para abrir el menú lateral.
   Solo actúa en páginas que tienen .sidebar y NO traen su propio
   botón (recepción ya tiene .hamburger y se deja como está).
   ───────────────────────────────────────────────────────────── */
(function () {
  function init() {
    var sb = document.querySelector('.sidebar');
    if (!sb || document.querySelector('.hamburger') || document.querySelector('.movil-burger')) return;

    var ov = document.createElement('div');
    ov.className = 'movil-overlay';
    document.body.appendChild(ov);

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'movil-burger';
    btn.setAttribute('aria-label', 'Abrir menú');
    btn.textContent = '☰';

    var bar = document.querySelector('.main .topbar') || document.querySelector('.topbar');
    if (bar) {
      bar.insertBefore(btn, bar.firstChild);
    } else {
      btn.style.cssText = 'position:fixed;top:10px;left:10px;z-index:998;background:var(--bg2,#12161f)';
      document.body.appendChild(btn);
    }

    function abrir()  { sb.classList.add('movil-open');    ov.classList.add('show'); }
    function cerrar() { sb.classList.remove('movil-open'); ov.classList.remove('show'); }
    btn.addEventListener('click', abrir);
    ov.addEventListener('click', cerrar);
    // Al elegir una opción del menú, cerrarlo
    sb.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('a')) cerrar(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') cerrar(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
