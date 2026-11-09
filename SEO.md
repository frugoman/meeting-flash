# MeetingFlash SEO (2026-11-09)

Site: https://meetingflash.frusoft.dev (GitHub Pages, `main` /docs, CNAME present, HTTPS enforced). Notes live here, not in `docs/`, so they are not published.

## Audit (seo-audit.mjs, local server of docs/)
- Before: 10/21. After: 18/21.
- Remaining fails are n/a by design: hreflang (English only), apple-itunes-app and App Store link (Mac app, not on the App Store).

## Done
canonical, SoftwareApplication JSON-LD (macOS 14+, free, downloadUrl), full Twitter/OG tags, keyword-led title, robots.txt, sitemap.xml, 404.html, one guide linked from the footer.

## Keyword research (WebSearch, qualitative; no volume data until Search Console)
Demand is real but crowded: In Your Face, Chime, Calerto, Here Goes, Slapss, LoudCue, Bonk, MeetingBar (v4.8 full-screen), Chimr, Alert Sign, BigReminder. Searchers compare apps and ask about Focus mode, Exchange sync and screen sharing. MeetingFlash's edge: free, open source, per-output sound and Wi-Fi rules, any calendar via macOS Calendar.

Candidate guides, ranked:
1. Full-screen meeting alert on Mac (WRITTEN: /guides/full-screen-meeting-alert-mac/)
2. Mac Calendar notifications not showing / missed (troubleshooting: Focus, Alerts style, Exchange sync)
3. Meeting reminders for ADHD / hyperfocus on Mac
4. Best Mac meeting reminder apps compared (honest comparison; highest intent, needs care)
5. Outlook/Exchange meetings not alerting on Mac (add account to Internet Accounts)
6. Mute meeting alerts on office Wi-Fi / only on AirPods
Skip: anything needing volume claims. Re-rank with `gsc-report.mjs opps` after ~4 weeks.
Unverified in the guide: whether alerts appear over Focus, full-screen apps or screen sharing; test and add before claiming.

## Live (2026-11-09)
Pushed to main as cbe306d; live audit of https://meetingflash.frusoft.dev: 18/21. Home, guide, sitemap.xml, robots.txt all 200.
