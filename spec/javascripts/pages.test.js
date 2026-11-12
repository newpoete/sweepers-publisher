// Specs for the pure helpers in site/assets/javascripts/pages.js:
//   node --test spec/javascripts/*.test.js
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const Pages = require('../../site/assets/javascripts/pages.js');

describe('Pages.selectionDayFromPath', () => {
  it('reads the day from a selection URL, with or without the staging prefix or .html', () => {
    assert.equal(Pages.selectionDayFromPath('/sweepers-publisher/selection/314'), 314);
    assert.equal(Pages.selectionDayFromPath('/selection/7.html'), 7);
    assert.equal(Pages.selectionDayFromPath('/selection/366/'), 366);
  });

  describe('when the path is not a selection of a valid day', () => {
    it('returns null', () => {
      for (const path of ['/selection/0', '/selection/367', '/selection/abc', '/selections', '/today']) {
        assert.equal(Pages.selectionDayFromPath(path), null, path);
      }
    });
  });
});

describe('Pages.findSelection', () => {
  it("finds a selection by day, or null when the day isn't a current selection", () => {
    const selections = [{ day_of_year: 314, date: '2026-11-09', snippet: 'a' }, { day_of_year: 301, date: '2026-10-27', snippet: 'b' }];
    assert.equal(Pages.findSelection(selections, 301).date, '2026-10-27');
    assert.equal(Pages.findSelection(selections, 300), null);
  });
});

describe('Pages.mountweazelDate', () => {
  it("dates the mountweazel 22 May of the given date's year, as Flask did", () => {
    assert.deepEqual(Pages.mountweazelDate({ year: 2026, month: 11, day: 12 }), { year: 2026, month: 5, day: 22 });
    assert.deepEqual(Pages.mountweazelDate({ year: 2027, month: 1, day: 1 }), { year: 2027, month: 5, day: 22 });
  });
});
