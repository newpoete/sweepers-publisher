// Specs for site/assets/javascripts/sweepers.js, run with Node's built-in runner:
//   node --test spec/javascripts/*.test.js
// Each example sets the reader's time zone (process.env.TZ) and a fixed moment.
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const Sweepers = require('../../site/assets/javascripts/sweepers.js');

function inZone(zone, isoInstant) {
  process.env.TZ = zone;
  return new Date(isoInstant);
}

function iso(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.year}-${pad(date.month)}-${pad(date.day)}`;
}

describe('Sweepers.shownDate', () => {
  describe('when the reader is west of UTC', () => {
    it("shows the reader's own date even after the UTC release", () => {
      // 16:53 PST on 11 November is 00:53 UTC on 12 November: the live site's snapshot moment.
      const now = inZone('America/Los_Angeles', '2026-11-12T00:53:00Z');
      assert.equal(iso(Sweepers.shownDate('today', now, '2026-11-12')), '2026-11-11');
      assert.equal(iso(Sweepers.shownDate('yesterday', now, '2026-11-12')), '2026-11-10');
    });

    it('turns over at local midnight', () => {
      const now = inZone('America/Los_Angeles', '2026-11-12T08:30:00Z'); // 00:30 PST, 12 November
      assert.equal(iso(Sweepers.shownDate('today', now, '2026-11-12')), '2026-11-12');
    });
  });

  describe('when the reader is east of UTC and the release has not run', () => {
    it('shows the release date, not the local date', () => {
      const now = inZone('Asia/Tokyo', '2026-11-12T23:00:00Z'); // 08:00 JST, 13 November
      assert.equal(iso(Sweepers.shownDate('today', now, '2026-11-12')), '2026-11-12');
      assert.equal(iso(Sweepers.shownDate('yesterday', now, '2026-11-12')), '2026-11-11');
    });
  });

  describe('when the reader is east of UTC and the release has run', () => {
    it('shows the local date', () => {
      const now = inZone('Asia/Tokyo', '2026-11-13T00:30:00Z'); // 09:30 JST, 13 November
      assert.equal(iso(Sweepers.shownDate('today', now, '2026-11-13')), '2026-11-13');
    });
  });

  describe('when the daily release is late', () => {
    it('keeps showing the last release date in UTC', () => {
      const now = inZone('UTC', '2026-11-13T00:45:00Z');
      assert.equal(iso(Sweepers.shownDate('today', now, '2026-11-12')), '2026-11-12');
    });
  });

  it('never shows a date after the release, in any zone, at any hour', () => {
    const zones = ['Pacific/Kiritimati', 'Asia/Tokyo', 'Europe/London', 'UTC', 'America/New_York', 'Pacific/Pago_Pago'];
    for (const zone of zones) {
      for (let hour = 0; hour < 48; hour += 1) {
        const now = inZone(zone, new Date(Date.UTC(2026, 10, 12, hour)).toISOString());
        const release = hour < 24 ? '2026-11-12' : '2026-11-13';
        const shown = iso(Sweepers.shownDate('today', now, release));
        assert.ok(shown <= release, `${zone} at +${hour}h showed ${shown} after release ${release}`);
      }
    }
  });

  describe('when today is 1 January', () => {
    it('shows 31 December of the previous year as yesterday', () => {
      const now = inZone('UTC', '2027-01-01T12:00:00Z');
      const yesterday = Sweepers.shownDate('yesterday', now, '2027-01-01');
      assert.equal(iso(yesterday), '2026-12-31');
      assert.equal(Sweepers.dayOfYear(yesterday), 366);
    });
  });
});

describe('Sweepers.dayOfYear', () => {
  it('numbers days on the 366-day canonical leap year, as Sweepers::Calendar', () => {
    const d = Sweepers.calendarDate;
    assert.equal(Sweepers.dayOfYear(d(2026, 1, 1)), 1);
    assert.equal(Sweepers.dayOfYear(d(2026, 2, 28)), 59);
    assert.equal(Sweepers.dayOfYear(d(2028, 2, 29)), 60);
    assert.equal(Sweepers.dayOfYear(d(2027, 3, 1)), 61);
    assert.equal(Sweepers.dayOfYear(d(2026, 11, 12)), 317);
    assert.equal(Sweepers.dayOfYear(d(2026, 12, 31)), 366);
  });
});

describe('Sweepers.headingParts and Sweepers.title', () => {
  it("format the date as the live site's heading and title", () => {
    const date = Sweepers.calendarDate(2026, 11, 12);
    assert.deepEqual(Sweepers.headingParts(date), { dayOfWeek: 'Thursday', dayOfMonth: '12', month: 'November', year: '2026' });
    assert.equal(Sweepers.title(date), 'Sweepers Calendar for 12th of November');
  });

  it('use English ordinals, including the teens', () => {
    const ordinals = [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(Sweepers.ordinal);
    assert.deepEqual(ordinals, ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
  });
});

describe('Sweepers.selectionDayFromPath', () => {
  it('reads the day from a selection URL, with or without the staging prefix or .html', () => {
    assert.equal(Sweepers.selectionDayFromPath('/sweepers-publisher/selection/314'), 314);
    assert.equal(Sweepers.selectionDayFromPath('/selection/7.html'), 7);
    assert.equal(Sweepers.selectionDayFromPath('/selection/366/'), 366);
  });

  describe('when the path is not a selection of a valid day', () => {
    it('returns null', () => {
      for (const path of ['/selection/0', '/selection/367', '/selection/abc', '/selections', '/today']) {
        assert.equal(Sweepers.selectionDayFromPath(path), null, path);
      }
    });
  });
});

describe('Sweepers.findSelection', () => {
  it("finds a selection by day, or null when the day isn't a current selection", () => {
    const selections = [{ day_of_year: 314, date: '2026-11-09', snippet: 'a' }, { day_of_year: 301, date: '2026-10-27', snippet: 'b' }];
    assert.equal(Sweepers.findSelection(selections, 301).date, '2026-10-27');
    assert.equal(Sweepers.findSelection(selections, 300), null);
  });
});

describe('Sweepers.clockText', () => {
  it("shows the reader's local time and zone", () => {
    const now = inZone('America/Los_Angeles', '2026-11-12T00:53:08Z');
    assert.equal(Sweepers.clockText(now), '2026-11-11 16:53:08 PST');
  });
});
