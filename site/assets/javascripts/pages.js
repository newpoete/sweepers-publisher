/*
 * Sweepers Calendar pages: fetch the released data and render each page.
 *
 * Each page's <body> says what it shows (data-page) and where the site root
 * is, relative to the page (data-root). Every page gets the footer clock and
 * year; then the page's own renderer runs:
 *   today, yesterday  the leaf for the date shown (see calendar.js)
 *   selections        the selections list
 *   selection         one selection, its day read from the URL
 *
 * Needs calendar.js loaded first (window.SweepersCalendar). The pure helpers
 * are exported for Node (spec/javascripts/pages.test.js).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./calendar.js'));
  } else {
    root.SweepersPages = factory(root.SweepersCalendar);
    if (typeof document !== 'undefined') {
      document.addEventListener('DOMContentLoaded', function () { root.SweepersPages.start(document, window); });
    }
  }
})(this, function (Calendar) {
  'use strict';

  // Pure helpers

  // The day of year in a selection page's URL: ".../selection/314" (or 314.html).
  function selectionDayFromPath(pathname) {
    var match = /\/selection\/(\d{1,3})(?:\.html)?\/?$/.exec(pathname);
    var day = match ? Number(match[1]) : NaN;
    return day >= 1 && day <= 366 ? day : null;
  }

  function findSelection(selections, day) {
    for (var i = 0; i < selections.length; i += 1) {
      if (selections[i].day_of_year === day) { return selections[i]; }
    }
    return null;
  }

  // Data: JSON relative to the site root; null when the file doesn't exist.

  function getJson(rootPath, path) {
    return fetch(rootPath + '/' + path, { cache: 'no-cache' }).then(function (response) {
      if (response.status === 404) { return null; }
      if (!response.ok) { throw new Error(path + ': HTTP ' + response.status); }
      return response.json();
    });
  }

  // Rendering

  function showLeaf(doc, date, leaf) {
    var parts = Calendar.headingParts(date);
    var heading = doc.getElementById('leaf-date');
    heading.querySelector('.day_of_week').textContent = parts.dayOfWeek;
    heading.querySelector('.day_of_month').textContent = parts.dayOfMonth;
    heading.querySelector('.full_month').textContent = parts.month;
    heading.querySelector('.year').textContent = parts.year;
    heading.hidden = false;
    // Leaf HTML comes from the editor and is trusted, as Flask's `| safe` was.
    doc.getElementById('leaf-text').innerHTML = leaf ? leaf.html : '';
    doc.title = Calendar.title(date);
  }

  function element(doc, tag, className, text) {
    var node = doc.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined) { node.textContent = text; }
    return node;
  }

  // One card in the live site's markup (without its score-N classes).
  function selectionCard(doc, rootPath, selection) {
    var parts = Calendar.headingParts(Calendar.parseDate(selection.date));
    var link = element(doc, 'a');
    link.href = rootPath + '/selection/' + selection.day_of_year;
    link.appendChild(element(doc, 'span', 'day_of_month', parts.dayOfMonth));
    link.appendChild(doc.createTextNode(' '));
    link.appendChild(element(doc, 'span', 'full_month', parts.month));
    link.appendChild(doc.createTextNode(' '));
    link.appendChild(element(doc, 'span', 'year', parts.year));
    var foot = element(doc, 'div', 'foot');
    foot.appendChild(link);
    var card = element(doc, 'div', 'selection');
    card.appendChild(element(doc, 'div', 'snippet', selection.snippet));
    card.appendChild(foot);
    return card;
  }

  function showSelections(doc, rootPath, selections) {
    var list = doc.getElementById('selection-list');
    list.textContent = '';
    if (!selections.length) {
      var none = element(doc, 'div', null, 'No selections found.');
      none.id = 'no-selections';
      list.appendChild(none);
      return;
    }
    selections.forEach(function (selection) { list.appendChild(selectionCard(doc, rootPath, selection)); });
  }

  function showError(doc, targetId, what) {
    doc.getElementById(targetId).innerHTML =
      '<p class="leaf-error">' + what + ' could not be loaded. Please try again later.</p>';
  }

  function startFooter(doc, win) {
    var year = doc.querySelector('.copyright-year');
    if (year) { year.textContent = String(new Date().getFullYear()); }
    var clock = doc.querySelector('.livestamp');
    if (!clock) { return; }
    var tick = function () { clock.textContent = Calendar.clockText(new Date()); };
    tick();
    win.setInterval(tick, 1000);
  }

  // Page renderers, by data-page.

  function renderLeafPage(page, doc, win, rootPath) {
    getJson(rootPath, 'release.json').then(function (release) {
      if (!release) { throw new Error('release.json missing'); }
      var date = Calendar.shownDate(page, new Date(), release.date);
      return getJson(rootPath, 'leaves/' + Calendar.dayOfYear(date) + '.json').then(function (leaf) {
        showLeaf(doc, date, leaf);
      });
    }).catch(function () { showError(doc, 'leaf-text', 'The leaf'); });
  }

  function renderSelectionsPage(page, doc, win, rootPath) {
    getJson(rootPath, 'selections.json').then(function (selections) {
      showSelections(doc, rootPath, selections || []);
    }).catch(function () { showError(doc, 'selection-list', 'The selections'); });
  }

  function renderSelectionPage(page, doc, win, rootPath) {
    var day = selectionDayFromPath(win.location.pathname);
    getJson(rootPath, 'selections.json').then(function (selections) {
      var selection = day && findSelection(selections || [], day);
      if (!selection) { throw new Error('not a current selection: ' + day); }
      return getJson(rootPath, 'leaves/' + day + '.json').then(function (leaf) {
        showLeaf(doc, Calendar.parseDate(selection.date), leaf);
      });
    }).catch(function () { showError(doc, 'leaf-text', 'The leaf'); });
  }

  var RENDERERS = {
    today: renderLeafPage,
    yesterday: renderLeafPage,
    selections: renderSelectionsPage,
    selection: renderSelectionPage
  };

  function start(doc, win) {
    var page = doc.body.getAttribute('data-page');
    var rootPath = doc.body.getAttribute('data-root') || '.';
    startFooter(doc, win);
    if (RENDERERS[page]) { RENDERERS[page](page, doc, win, rootPath); }
  }

  return { selectionDayFromPath: selectionDayFromPath, findSelection: findSelection, start: start };
});
