/**
 * WDOS icon system — inline SVG glyphs in a solid, Font Awesome-like
 * style. Self-hosted in code: no fonts, no CDN, works offline, and
 * inherits color from CSS via currentColor.
 */
const PATHS = {
  home: 'M12 3 2.5 11h2.3v8.5h5.7v-5.5h3v5.5h5.7V11h2.3L12 3z',
  users: 'M8 11a3.2 3.2 0 1 0 0-6.4A3.2 3.2 0 0 0 8 11zm8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM2 19.4c0-3.2 2.7-5.4 6-5.4s6 2.2 6 5.4v.6H2v-.6zm13.4.6c.1-2.3-.8-4.2-2.2-5.5.9-.3 1.8-.5 2.8-.5 2.9 0 6 1.8 6 5.4v.6h-6.6z',
  userplus: 'M9 11.5A3.7 3.7 0 1 0 9 4a3.7 3.7 0 0 0 0 7.5zM2 20c0-3.6 3.1-6 7-6s7 2.4 7 6v.5H2V20zm16-9V8.5h-2.5v-2H18V4h2v2.5h2.5v2H20V11h-2z',
  sitemap: 'M9.5 3h5v4h-1.5v2.5H19a1.5 1.5 0 0 1 1.5 1.5v3H22v4h-5v-4h1.5v-2.5h-13V14H7v4H2v-4h1.5v-3A1.5 1.5 0 0 1 5 9.5h6V7H9.5V3zM9.5 14h5v4h-5v-4z',
  tasks: 'M4 4.5h3.5V8H4V4.5zm5.5 1h10.5v1.8H9.5V5.5zM4 10.2h3.5v3.5H4v-3.5zm5.5 1h10.5V13H9.5v-1.8zM4 16h3.5v3.5H4V16zm5.5 1h10.5v1.8H9.5V17zM4.6 6.9 3.5 5.8l.8-.8.3.3 1-1 .8.8-1.8 1.8z',
  calendar: 'M7 2h2v2h6V2h2v2h3a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h3V2zm-2 7v10h14V9H5zm2 2.5h3v3H7v-3z',
  chart: 'M3 3h2v16h16v2H3V3zm4 9h3v5H7v-5zm5-6h3v11h-3V6zm5 3h3v8h-3V9z',
  megaphone: 'M20 3v14l-7-3H7a3 3 0 0 1 0-6V8l13-5zM7 15h2.5l1 5H8l-1-5z',
  sliders: 'M3 6h11v2H3V6zm14 0h4v2h-4V6zm-2-2h2v6h-2V4zM3 12h4v2H3v-2zm8 0h10v2H11v-2zM7 10h2v6H7v-6zm-4 8h13v2H3v-2zm15 0h3v2h-3v-2zm-2-2h2v6h-2v-6z',
  signout: 'M4 3h8v2H6v14h6v2H4V3zm11.5 4 4.5 5-4.5 5-1.4-1.4 2.1-2.6H9v-2h7.2l-2.1-2.6L15.5 7z',
  pin: 'M12 2a7 7 0 0 0-7 7c0 4.9 5.7 11.4 6.4 12.2a.8.8 0 0 0 1.2 0C13.3 20.4 19 13.9 19 9a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5z',
  file: 'M6 2h8l4 4v16H6V2zm7 1.5V7h3.5L13 3.5zM8.5 11h7v1.5h-7V11zm0 3.5h7V16h-7v-1.5z',
  check: 'M9.5 16.2 5.3 12l-1.4 1.4 5.6 5.6 10-10L18.1 7.6l-8.6 8.6z',
  folder: 'M3 5a2 2 0 0 1 2-2h4.6l2 2H19a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5z',
  search: 'M10 3a7 7 0 1 0 4.3 12.5l4.6 4.6 1.4-1.4-4.6-4.6A7 7 0 0 0 10 3zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z',
  book: 'M6 2h13v17.5c0 .8-.7 1.5-1.5 1.5H6a3 3 0 0 1-3-3V5a3 3 0 0 1 3-3zm0 2a1 1 0 0 0-1 1v11.3c.3-.2.6-.3 1-.3h12V4H6zm0 14a1 1 0 0 0 0 2h11.5v-2H6z',
  sun: 'M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zM11 2h2v3h-2V2zm0 17h2v3h-2v-3zM2 11h3v2H2v-2zm17 0h3v2h-3v-2zM4.9 3.5 7 5.6 5.6 7 3.5 4.9l1.4-1.4zm14.2 0 1.4 1.4L18.4 7 17 5.6l2.1-2.1zM5.6 17 7 18.4l-2.1 2.1-1.4-1.4L5.6 17zm12.8 0 2.1 2.1-1.4 1.4-2.1-2.1 1.4-1.4z',
  moon: 'M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5 8.5 8.5 0 1 0 20.5 14.5z',
  bell: 'M12 2a6 6 0 0 0-6 6v3.5L4 15v2h16v-2l-2-3.5V8a6 6 0 0 0-6-6zm-2.5 16a2.5 2.5 0 0 0 5 0h-5z',
  clip: 'M16.5 6.5v9a4.5 4.5 0 0 1-9 0V6a3 3 0 0 1 6 0v9a1.5 1.5 0 0 1-3 0V7H9v8a3 3 0 0 0 6 0V6a4.5 4.5 0 0 0-9 0v9.5a6 6 0 0 0 12 0v-9h-1.5z',
  menu: 'M3 6h18v2H3V6zm0 5h18v2H3v-2zm0 5h18v2H3v-2z',
  briefcase: 'M9 4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2h4a2 2 0 0 1 2 2v4h-8v-1.5h-2V12H3V8a2 2 0 0 1 2-2h4V4zm2 2h2V4h-2v2zM3 13.5h8V15h2v-1.5h8V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5.5z',
  support: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 6a4 4 0 1 1 0 8 4 4 0 0 1 0-8zM12 4c1.5 0 2.9.4 4.1 1.1l-2.2 2.2a4 4 0 0 0-3.8 0L7.9 5.1A7.9 7.9 0 0 1 12 4zM4 12c0-1.5.4-2.9 1.1-4.1l2.2 2.2a4 4 0 0 0 0 3.8l-2.2 2.2A7.9 7.9 0 0 1 4 12zm8 8a7.9 7.9 0 0 1-4.1-1.1l2.2-2.2a4 4 0 0 0 3.8 0l2.2 2.2A7.9 7.9 0 0 1 12 20zm6.9-3.9-2.2-2.2a4 4 0 0 0 0-3.8l2.2-2.2a7.9 7.9 0 0 1 0 8.2z',
  shield: 'M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3zm-1.5 13.6-3.2-3.2 1.4-1.4 1.8 1.8 4.3-4.3 1.4 1.4-5.7 5.7z',
  heart: 'M12 21S3.5 15.6 1.9 10.8C.7 7.2 3 4 6.2 4c2.2 0 3.9 1.2 4.8 2.9h2C13.9 5.2 15.6 4 17.8 4 21 4 23.3 7.2 22.1 10.8 20.5 15.6 12 21 12 21z',
};

export function icon(name, size = 18) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', String(size));
  svg.setAttribute('height', String(size));
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('fill', 'currentColor');
  svg.style.display = 'inline-block';
  svg.style.verticalAlign = '-0.15em';
  const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  p.setAttribute('d', PATHS[name] ?? PATHS.file);
  svg.append(p);
  return svg;
}
