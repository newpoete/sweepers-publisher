/*
 * Sweepers Calendar: fills a page with the leaf for the reader's date.
 *
 * Each page's <body> says which leaf it shows (data-page="today" or
 * "yesterday") and where the site root is, relative to the page (data-root).
 *
 * The date a page shows is the reader's local date, capped at the latest
 * release date (release.json): releases run just after 00:00 UTC, so a reader
 * east of UTC sees the release's date until the next release runs, and a
 * reader west of UTC always sees their own date. Nothing after the release
 * date is ever released, so nothing after it is ever fetched.
 *
 * The date functions are pure and exported for Node (spec/javascripts/).
 */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.Sweepers = api;
    if (typeof document !== 'undefined') {
      document.addEventListener('DOMContentLoaded', function () { api.start(document, window); });
    }
  }
})(this, function () {
  'use strict';

  var CANONICAL_YEAR = 2000;
  var MS_PER_DAY = 86400000;
  var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
                'September', 'October', 'November', 'December'];

  // Calendar dates are plain {year, month (1-12), day} objects, so no time
  // zone or daylight-saving shift can move them.
  function calendarDate(year, month, day) {
    var utc = new Date(Date.UTC(year, month - 1, day));
    return { year: utc.getUTCFullYear(), month: utc.getUTCMonth() + 1, day: utc.getUTCDate() };
  }

  // The reader's local calendar date for a moment (a JS Date).
  function localDate(now) {
    return calendarDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  // "2026-11-12" -> {year: 2026, month: 11, day: 12}
  function parseDate(iso) {
    var parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
    if (!parts) { throw new Error('Bad date: ' + iso); }
    return calendarDate(Number(parts[1]), Number(parts[2]), Number(parts[3]));
  }

  function compare(a, b) {
    return (a.year - b.year) || (a.month - b.month) || (a.day - b.day);
  }

  function addDays(date, days) {
    return calendarDate(date.year, date.month, date.day + days);
  }

  // Canonical day of year (1-366) on the leap year 2000, as Sweepers::Calendar.
  function dayOfYear(date) {
    return (Date.UTC(CANONICAL_YEAR, date.month - 1, date.day) - Date.UTC(CANONICAL_YEAR, 0, 1)) / MS_PER_DAY + 1;
  }

  // The date the Today page shows: the reader's date, capped at the release.
  function todayShown(now, releaseIso) {
    var local = localDate(now);
    var release = parseDate(releaseIso);
    return compare(local, release) > 0 ? release : local;
  }

  // The date a page shows: "today" or "yesterday".
  function shownDate(page, now, releaseIso) {
    var today = todayShown(now, releaseIso);
    return page === 'yesterday' ? addDays(today, -1) : today;
  }

  function weekday(date) {
    return DAYS[new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay()];
  }

  function ordinal(day) {
    var teen = day % 100 >= 11 && day % 100 <= 13;
    var suffix = teen ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[day % 10] || 'th');
    return day + suffix;
  }

  // "Thursday, 12 November 2026", split into the live site's spans.
  function headingParts(date) {
    return { dayOfWeek: weekday(date), dayOfMonth: String(date.day), month: MONTHS[date.month - 1], year: String(date.year) };
  }

  // "Sweepers Calendar for 12th of November"
  function title(date) {
    return 'Sweepers Calendar for ' + ordinal(date.day) + ' of ' + MONTHS[date.month - 1];
  }

  function pad(n) {
    return (n < 10 ? '0' : '') + n;
  }

  // "2026-11-11 16:53:08 PST": the reader's local time and zone, for the footer.
  function clockText(now) {
    var zone = '';
    try {
      var parts = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' }).formatToParts(now);
      parts.forEach(function (part) { if (part.type === 'timeZoneName') { zone = part.value; } });
    } catch (e) { zone = ''; }
    var stamp = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate()) + ' ' +
                pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds());
    return zone ? stamp + ' ' + zone : stamp;
  }

  // Browser only: fetch JSON relative to the site root; null when missing.
  function getJson(rootPath, path) {
    return fetch(rootPath + '/' + path, { cache: 'no-cache' }).then(function (response) {
      if (response.status === 404) { return null; }
      if (!response.ok) { throw new Error(path + ': HTTP ' + response.status); }
      return response.json();
    });
  }

  function showLeaf(doc, date, leaf) {
    var parts = headingParts(date);
    var heading = doc.getElementById('leaf-date');
    heading.querySelector('.day_of_week').textContent = parts.dayOfWeek;
    heading.querySelector('.day_of_month').textContent = parts.dayOfMonth;
    heading.querySelector('.full_month').textContent = parts.month;
    heading.querySelector('.year').textContent = parts.year;
    heading.hidden = false;
    // Leaf HTML comes from the editor and is trusted, as Flask's `| safe` was.
    doc.getElementById('leaf-text').innerHTML = leaf ? leaf.html : '';
    doc.title = title(date);
  }

  function showError(doc) {
    doc.getElementById('leaf-text').innerHTML =
      '<p class="leaf-error">The leaf could not be loaded. Please try again later.</p>';
  }

  function startClock(doc, win) {
    var clock = doc.querySelector('.livestamp');
    if (!clock) { return; }
    var tick = function () { clock.textContent = clockText(new Date()); };
    tick();
    win.setInterval(tick, 1000);
  }

  function start(doc, win) {
    var body = doc.body;
    var rootPath = body.getAttribute('data-root') || '.';
    var page = body.getAttribute('data-page');
    startClock(doc, win);
    var year = doc.querySelector('.copyright-year');
    if (year) { year.textContent = String(new Date().getFullYear()); }
    if (page !== 'today' && page !== 'yesterday') { return; }

    getJson(rootPath, 'release.json').then(function (release) {
      if (!release) { throw new Error('release.json missing'); }
      var date = shownDate(page, new Date(), release.date);
      return getJson(rootPath, 'leaves/' + dayOfYear(date) + '.json').then(function (leaf) {
        showLeaf(doc, date, leaf);
      });
    }).catch(function () { showError(doc); });
  }

  return {
    calendarDate: calendarDate, localDate: localDate, parseDate: parseDate, addDays: addDays,
    dayOfYear: dayOfYear, todayShown: todayShown, shownDate: shownDate, weekday: weekday,
    ordinal: ordinal, headingParts: headingParts, title: title, clockText: clockText, start: start
  };
});
