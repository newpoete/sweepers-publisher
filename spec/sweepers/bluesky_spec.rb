# frozen_string_literal: true

RSpec.describe Sweepers::Bluesky do
  describe '#did' do
    it 'resolves the handle through the public API' do
      http = instance_double(Sweepers::HTTP)
      allow(http).to receive(:get_json)
        .with('https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle', { handle: 'sweeperscalendar.com' })
        .and_return('did' => 'did:plc:calendar')
      expect(described_class.new('sweeperscalendar.com', http: http).did).to eq('did:plc:calendar')
    end
  end

  describe '#posts_on' do
    it "returns only the account's own posts created on that UTC date" do
      http = feed_http(
        feed_item('own today', '2026-11-16T13:30:05.123Z'),
        feed_item('reposted', '2026-11-16T09:00:00Z', reason: { '$type' => 'app.bsky.feed.defs#reasonRepost' }),
        feed_item("someone else's", '2026-11-16T10:00:00Z', author: 'did:plc:other'),
        feed_item('own yesterday', '2026-11-15T23:59:59Z')
      )
      posts = described_class.new('sweeperscalendar.com', http: http).posts_on(Date.new(2026, 11, 16))
      expect(posts.map { |post| post.dig('record', 'text') }).to eq(['own today'])
    end

    context 'when a post was made late in the Pacific evening' do
      it 'counts it on the next UTC date' do
        http = feed_http(feed_item('evening', '2026-11-15T20:30:00-08:00')) # 04:30 UTC on the 16th
        bluesky = described_class.new('sweeperscalendar.com', http: http)
        expect(bluesky.posts_on(Date.new(2026, 11, 16)).size).to eq(1)
        expect(bluesky.posts_on(Date.new(2026, 11, 15))).to be_empty
      end
    end
  end

  describe '#login' do
    it 'signs in at the entryway and keeps neither the password nor the token in view' do
      http = instance_double(Sweepers::HTTP)
      allow(http).to receive(:post_json)
        .with('https://bsky.social/xrpc/com.atproto.server.createSession', { identifier: 'sweeperscalendar.com', password: 'app-pass' })
        .and_return(session)
      bluesky = described_class.new('sweeperscalendar.com', http: http)
      expect(bluesky.login('app-pass')).to eq('did' => 'did:plc:calendar', 'handle' => 'sweeperscalendar.com')
      expect(bluesky.logged_in?).to be(true)
      expect(bluesky.inspect).to eq('#<Sweepers::Bluesky sweeperscalendar.com (signed in)>')
      expect(bluesky.inspect).not_to include('app-pass', 'secret-token')
    end

    context 'when the password is wrong' do
      it "raises an error that names the account and Bluesky's reason, not the password" do
        http = instance_double(Sweepers::HTTP)
        allow(http).to receive(:post_json)
          .and_raise(Sweepers::HTTP::Error.new(401, 'AuthenticationRequired', 'Invalid identifier or password'))
        bluesky = described_class.new('sweeperscalendar.com', http: http)
        expect { bluesky.login('wrong-pass') }.to raise_error(described_class::Error) { |error|
          expect(error.message).to include('sweeperscalendar.com', 'AuthenticationRequired')
          expect(error.message).not_to include('wrong-pass')
        }
      end
    end
  end

  describe '#upload_blob' do
    it 'uploads the bytes with the session token and returns the blob' do
      http = signed_in_http
      blob = { '$type' => 'blob', 'ref' => { '$link' => 'bafkrei-card' }, 'mimeType' => 'image/jpeg', 'size' => 3 }
      allow(http).to receive(:post_bytes)
        .with('https://bsky.social/xrpc/com.atproto.repo.uploadBlob', 'jpg', content_type: 'image/jpeg', token: 'secret-token')
        .and_return('blob' => blob)
      bluesky = described_class.new('sweeperscalendar.com', http: http)
      bluesky.login('app-pass')
      expect(bluesky.upload_blob('jpg', 'image/jpeg')).to eq(blob)
    end

    context 'when not signed in' do
      it 'raises without calling the network' do
        http = instance_double(Sweepers::HTTP)
        expect { described_class.new('sweeperscalendar.com', http: http).upload_blob('jpg', 'image/jpeg') }
          .to raise_error(described_class::Error, /not signed in/)
      end
    end
  end

  describe '#create_post' do
    it "creates the record in the account's repo, stamped with createdAt, and returns its URI" do
      http = signed_in_http
      record = { '$type' => 'app.bsky.feed.post', 'text' => 'All statement is overstatement.' }
      expected = { repo: 'did:plc:calendar', collection: 'app.bsky.feed.post',
                   record: record.merge('createdAt' => '2026-11-16T13:30:05.123Z') }
      allow(http).to receive(:post_json)
        .with('https://bsky.social/xrpc/com.atproto.repo.createRecord', expected, token: 'secret-token')
        .and_return('uri' => 'at://did:plc:calendar/app.bsky.feed.post/3abc', 'cid' => 'bafyrei-post', 'commit' => {})
      bluesky = described_class.new('sweeperscalendar.com', http: http)
      bluesky.login('app-pass')
      created = bluesky.create_post(record, now: Time.utc(2026, 11, 16, 13, 30, 5.123r))
      expect(created).to eq('uri' => 'at://did:plc:calendar/app.bsky.feed.post/3abc', 'cid' => 'bafyrei-post')
    end
  end

  describe '.web_url' do
    it "is the post's bsky.app address" do
      expect(described_class.web_url('sweeperscalendar.com', 'at://did:plc:calendar/app.bsky.feed.post/3abc'))
        .to eq('https://bsky.app/profile/sweeperscalendar.com/post/3abc')
    end
  end

  def session
    { 'did' => 'did:plc:calendar', 'handle' => 'sweeperscalendar.com', 'accessJwt' => 'secret-token', 'refreshJwt' => 'refresh' }
  end

  def signed_in_http
    http = instance_double(Sweepers::HTTP)
    allow(http).to receive(:post_json).with(%r{createSession}, anything).and_return(session)
    http
  end

  def feed_http(*items)
    http = instance_double(Sweepers::HTTP)
    allow(http).to receive(:get_json).with(/resolveHandle/, anything).and_return('did' => 'did:plc:calendar')
    allow(http).to receive(:get_json)
      .with('https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed',
            { actor: 'did:plc:calendar', filter: 'posts_no_replies', limit: 10 })
      .and_return('feed' => items)
    http
  end

  def feed_item(text, created_at, author: 'did:plc:calendar', reason: nil)
    item = { 'post' => { 'uri' => "at://#{author}/app.bsky.feed.post/#{text.hash.abs}", 'author' => { 'did' => author },
                         'record' => { 'text' => text, 'createdAt' => created_at } } }
    item['reason'] = reason if reason
    item
  end
end
