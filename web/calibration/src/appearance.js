// Host appearance overrides the OS media query when the user chooses a theme.
(() => {
  const media = matchMedia('(prefers-color-scheme: dark)');
  let host = null;
  const apply = () => { document.documentElement.dataset.appearance = host || (media.matches ? 'dark' : 'light'); };
  window.set149Appearance = value => { host = value === 'light' || value === 'dark' ? value : null; apply(); };
  media.addEventListener('change', apply);
  apply();
})();
