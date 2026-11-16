(() => {
  const links = [...document.querySelectorAll('.stage-nav a[href^="#"]')];
  const targets = links.map(link => document.querySelector(link.getAttribute('href'))).filter(Boolean);
  if ('IntersectionObserver' in window && targets.length) {
    const observer = new IntersectionObserver(entries => {
      const visible = entries.filter(entry => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      links.forEach(link => link.removeAttribute('aria-current'));
      const active = links.find(link => link.getAttribute('href') === `#${visible.target.id}`);
      if (active) active.setAttribute('aria-current', 'location');
    }, {rootMargin: '-25% 0px -60% 0px', threshold: [0.01, 0.25, 0.5]});
    targets.forEach(target => observer.observe(target));
  }
})();

