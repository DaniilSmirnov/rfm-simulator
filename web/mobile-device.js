/* Touch laptops with a fine pointer keep the desktop layout; iPads in
 * desktop Safari mode are recognised by their Mac UA plus touch points. */
const RallyDevice = {
  isMobile(nav = navigator, media = window.matchMedia.bind(window)) {
    const ua = nav.userAgent || '';
    return Boolean(nav.userAgentData?.mobile || /Android|iPhone|iPad|iPod/i.test(ua)
      || (/Macintosh/i.test(ua) && nav.maxTouchPoints > 1)
      || (nav.maxTouchPoints > 0 && media('(pointer: coarse)').matches));
  },
  configure(config) {
    config.args.push('--', '--room-server=' + location.origin);
    if (!this.isMobile()) return;
    config.args.push('--mobile-controls');
    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overscrollBehavior = 'none';
    document.getElementById('canvas').style.touchAction = 'none';
  },
};
