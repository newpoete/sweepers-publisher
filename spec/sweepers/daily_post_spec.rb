# frozen_string_literal: true

RSpec.describe Sweepers::DailyPost do
  describe '#run' do
    context 'when today is released, has a leaf and is not yet posted' do
      it "posts the leaf with the card image and returns the post's address" do
        http = site_http
        bluesky = bluesky_double
        thumb = { '$type' => 'blob', 'ref' => { '$link' => 'bafkrei-card' } }
        allow(bluesky).to receive(:login).with('app-pass')
        allow(bluesky).to receive(:upload_blob).with(File.binread(described_class::CARD_IMAGE), 'image/jpeg').and_return(thumb)
        allow(bluesky).to receive(:create_post) do |record|
          expect(record['text']).to eq('All statement is overstatement.')
          expect(record.dig('embed', 'external')).to include('description' => 'Monday, 16 November 2026', 'thumb' => thumb)
          { 'uri' => 'at://did:plc:calendar/app.bsky.feed.post/3abc', 'cid' => 'bafyrei' }
        end
        result = described_class.new(bluesky, http: http).run(today: Date.new(2026, 11, 16), dry_run: false, app_password: 'app-pass')
        expect(result.status).to eq(:posted)
        expect(result.url).to eq('https://bsky.app/profile/sweeperscalendar.com/post/3abc')
        expect(bluesky).to have_received(:create_post).once
      end
    end

    context 'when it is a dry run' do
      it 'returns the post it would make, and signs in to nothing and writes nothing' do
        bluesky = bluesky_double
        result = described_class.new(bluesky, http: site_http).run(today: Date.new(2026, 11, 16), dry_run: true)
        expect(result.status).to eq(:would_post)
        expect(result.post.text).to eq('All statement is overstatement.')
        expect(result.post.card_description).to eq('Monday, 16 November 2026')
      end
    end

    context 'when the account already posted today' do
      it 'posts nothing and points to the existing post' do
        existing = { 'uri' => 'at://did:plc:calendar/app.bsky.feed.post/3old' }
        bluesky = bluesky_double(posted_today: [existing])
        result = described_class.new(bluesky, http: site_http).run(today: Date.new(2026, 11, 16), dry_run: false, app_password: 'app-pass')
        expect(result.status).to eq(:skipped)
        expect(result.message).to include('already posted today')
        expect(result.url).to eq('https://bsky.app/profile/sweeperscalendar.com/post/3old')
      end
    end

    context 'when the live release is not for today' do
      it 'posts nothing and says why, without reading the leaf or the feed' do
        http = instance_double(Sweepers::HTTP)
        allow(http).to receive(:get_json).with('https://sweeperscalendar.com/release.json')
                                         .and_return('date' => '2026-11-15', 'day_of_year' => 320)
        result = described_class.new(bluesky_double, http: http).run(today: Date.new(2026, 11, 16), dry_run: false)
        expect(result.status).to eq(:skipped)
        expect(result.message).to eq("The live release is for 2026-11-15, not today (2026-11-16), so there's nothing to post yet.")
      end
    end

    context 'when today has no leaf' do
      it 'posts nothing and says why' do
        http = site_http(leaf: nil)
        result = described_class.new(bluesky_double, http: http).run(today: Date.new(2026, 11, 16), dry_run: false)
        expect(result.status).to eq(:skipped)
        expect(result.message).to eq("Today (2026-11-16, day 321) has no leaf, so there's nothing to post.")
      end
    end

    context 'when posting with no app password' do
      it 'raises before signing in' do
        run = -> { described_class.new(bluesky_double, http: site_http).run(today: Date.new(2026, 11, 16), dry_run: false) }
        expect(&run).to raise_error(Sweepers::Bluesky::Error, /no app password/)
      end
    end
  end

  describe 'CARD_IMAGE' do
    it 'is a JPEG under the 1 MB limit for a card image' do
      bytes = File.binread(described_class::CARD_IMAGE)
      expect(bytes.byteslice(0, 3).bytes).to eq([0xFF, 0xD8, 0xFF])
      expect(bytes.bytesize).to be < 1_000_000
    end
  end

  # The live site for 2026-11-16 (day 321), with today's leaf or none.
  def site_http(leaf: { 'day_of_year' => 321, 'html' => "<p>All statement is overstatement.</p>\n" })
    http = instance_double(Sweepers::HTTP)
    allow(http).to receive(:get_json).with('https://sweeperscalendar.com/release.json')
                                     .and_return('date' => '2026-11-16', 'day_of_year' => 321)
    allow(http).to receive(:get_json).with('https://sweeperscalendar.com/leaves/321.json', not_found: :nil).and_return(leaf)
    http
  end

  # A Bluesky client that has no post today, unless told otherwise. Any call not
  # stubbed (login, upload_blob, create_post) fails the example.
  def bluesky_double(posted_today: [])
    bluesky = instance_double(Sweepers::Bluesky, handle: 'sweeperscalendar.com')
    allow(bluesky).to receive(:posts_on).with(Date.new(2026, 11, 16)).and_return(posted_today)
    bluesky
  end
end
