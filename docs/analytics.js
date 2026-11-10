/*
 * Frusoft marketing-site analytics (GA4 via gtag, Consent Mode v2, default DENIED).
 * Spec and rules: ~/.claude/skills/frusoft-playbook/reference/analytics.md
 *
 * Usage (every public page of a marketing site, not inside the app SPA):
 *   <script defer src="/analytics.js" data-mid="G-XXXXXXXXXX"></script>
 * Copy this file unchanged to the site as `analytics.js` (same origin, so CSP 'self' covers it).
 * CSP additions it needs: script-src https://www.googletagmanager.com ;
 *   connect-src https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com ; img-src https://*.google-analytics.com
 *
 * Events (the ONLY ones sent besides GA4's automatic page_view):
 *   cta_click  {cta_type: app_store|play_store|download|login|signup, cta_destination: host+path, page_path}
 *   guide_read {guide_slug}   fired once at 50% scroll on /guides|/guias pages
 * Never sent: names, emails, user ids, form contents, free text, query strings beyond utm_*, ad ids.
 */
(function () {
  'use strict';
  var script = document.currentScript;
  var MID = script && script.getAttribute('data-mid');
  if (!MID || !/^G-[A-Z0-9]+$/.test(MID)) return;
  if (navigator.doNotTrack === '1' || window.doNotTrack === '1') return; // respect DNT: send nothing

  var KEY = 'frusoft_consent'; // 'granted' | 'denied'
  var lang = (document.documentElement.lang || 'en').slice(0, 2).toLowerCase();
  var T = lang === 'es'
    ? { msg: 'Usamos analítica anónima para mejorar este sitio.', ok: 'Aceptar', no: 'Rechazar' }
    : { msg: 'We use anonymous analytics to improve this site.', ok: 'Accept', no: 'Decline' };

  function read() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function write(v) { try { localStorage.setItem(KEY, v); } catch (e) {} }

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = window.gtag || gtag;

  gtag('consent', 'default', {
    analytics_storage: 'denied', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied',
    wait_for_update: 500
  });
  var saved = read();
  if (saved === 'granted') gtag('consent', 'update', { analytics_storage: 'granted' });

  gtag('js', new Date());
  gtag('config', MID, {
    anonymize_ip: true,
    allow_google_signals: false,
    allow_ad_personalization_signals: false
  });
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(MID);
  document.head.appendChild(s);

  // ---- consent banner (only until the visitor chooses) ----
  function banner() {
    var b = document.createElement('div');
    b.setAttribute('role', 'dialog');
    b.setAttribute('aria-label', 'Analytics');
    b.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:2147483000;max-width:560px;margin:0 auto;' +
      'background:#1c1c1e;color:#fff;font:14px/1.4 system-ui,-apple-system,Segoe UI,sans-serif;padding:12px 14px;border-radius:12px;' +
      'box-shadow:0 6px 24px rgba(0,0,0,.28);display:flex;gap:10px;align-items:center;flex-wrap:wrap';
    var p = document.createElement('span'); p.textContent = T.msg; p.style.flex = '1 1 220px';
    function btn(label, primary, val) {
      var x = document.createElement('button'); x.type = 'button'; x.textContent = label;
      x.style.cssText = 'cursor:pointer;border:0;border-radius:8px;padding:8px 14px;font:inherit;font-weight:600;' +
        (primary ? 'background:#fff;color:#111' : 'background:transparent;color:#fff;border:1px solid rgba(255,255,255,.4)');
      x.onclick = function () {
        write(val);
        if (val === 'granted') gtag('consent', 'update', { analytics_storage: 'granted' });
        b.parentNode && b.parentNode.removeChild(b);
      };
      return x;
    }
    b.appendChild(p); b.appendChild(btn(T.no, false, 'denied')); b.appendChild(btn(T.ok, true, 'granted'));
    document.body.appendChild(b);
  }
  if (!saved) {
    if (document.body) banner(); else document.addEventListener('DOMContentLoaded', banner);
  }

  // ---- events ----
  function ctaType(a) {
    var h = a.href || '';
    if (/apps\.apple\.com/.test(h)) return 'app_store';
    if (/play\.google\.com/.test(h)) return 'play_store';
    if (/\.(dmg|zip|pkg)(\?|$)|github\.com\/[^/]+\/[^/]+\/releases|brew\.sh|homebrew/i.test(h)) return 'download';
    var t = a.getAttribute('data-cta');
    return t || null;
  }
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href],[data-cta]') : null;
    if (!a) return;
    var type = ctaType(a);
    if (!type) return;
    var dest = ''; try { var u = new URL(a.href, location.href); dest = u.host + u.pathname; } catch (err) {}
    gtag('event', 'cta_click', { cta_type: type, cta_destination: dest, page_path: location.pathname });
  }, true);

  var guide = location.pathname.match(/\/(?:guides|guias|guia)\/([^/]+)/);
  if (guide) {
    var fired = false;
    window.addEventListener('scroll', function () {
      if (fired) return;
      var h = document.documentElement;
      var depth = (window.scrollY + window.innerHeight) / Math.max(h.scrollHeight, 1);
      if (depth >= 0.5) { fired = true; gtag('event', 'guide_read', { guide_slug: guide[1] }); }
    }, { passive: true });
  }
})();
