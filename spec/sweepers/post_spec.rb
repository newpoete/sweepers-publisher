# frozen_string_literal: true

RSpec.describe Sweepers::Post do
  describe '.from_leaf' do
    it 'posts a short real leaf whole, as plain text with its apostrophe decoded' do
      post = described_class.from_leaf(parity_html(317), date: Date.new(2026, 11, 12))
      expect(post.text).to eq("Every cliff is a historical timeline that refutes most people's core beliefs.")
      expect(post.cut?).to be(false)
    end

    it 'cuts only the parity leaf over 300 graphemes, and every post fits' do
      posts = parity_leaves.to_h { |leaf| [leaf['day_of_year'], described_class.from_leaf(leaf['html'], date: Date.new(2026, 11, 12))] }
      expect(posts.select { |_, post| post.cut? }.keys).to eq([316])
      posts.each_value { |post| expect(described_class.fits?(post.text)).to be(true) }
    end

    context 'when the leaf is too long for one post' do
      it 'cuts it at the last word break that fits and ends it with an ellipsis' do
        text = described_class.from_leaf(parity_html(316), date: Date.new(2026, 11, 11)).text
        expect(text).to start_with('There is a correlation between that sense of well being')
        expect(text).to end_with('…')
        expect(text.grapheme_clusters.size).to be <= 300
        expect(text).not_to include('  ')
        full = described_class.plain_text(parity_html(316))
        expect(full).to start_with(text.chomp('…'))
        expect(full[text.chomp('…').length]).to match(/[\s,;:]/)
      end
    end

    context 'when the cut would end on joining punctuation' do
      it 'drops the punctuation before the ellipsis' do
        html = "<p>#{'word ' * 58}stop, extraordinarily</p>" # the cut falls inside the last word
        text = described_class.from_leaf(html, date: Date.new(2026, 11, 16)).text
        expect(text).to end_with('stop…')
      end
    end
  end

  describe '.plain_text' do
    it 'keeps paragraphs apart with a blank line and <br> as a line break' do
      html = "<p>First  line.<br>Second line.</p>\n<p>New paragraph.</p>\n"
      expect(described_class.plain_text(html)).to eq("First line.\nSecond line.\n\nNew paragraph.")
    end

    it 'drops tags and comments, and decodes numeric and named entities' do
      html = '<p><em>Less</em> is &#39;more&#39; &amp; more&nbsp;&mdash; or &hellip;<!-- note --></p>'
      expect(described_class.plain_text(html)).to eq("Less is 'more' & more — or …")
    end
  end

  describe '.fit' do
    it 'keeps a text of exactly 300 graphemes whole' do
      text = 'a' * 300
      expect(described_class.fit(text)).to eq(text)
    end

    context 'when the text is one grapheme over' do
      it 'cuts back to the last word break, keeping a word that ends exactly at the limit' do
        text = "#{'abcd ' * 60}x"
        expect(text.grapheme_clusters.size).to eq(301)
        expect(described_class.fit(text)).to eq("#{('abcd ' * 60).strip}…")
      end
    end

    context 'when the text is one word too long to fit' do
      it 'cuts the word, which is all it can do' do
        expect(described_class.fit('a' * 400)).to eq("#{'a' * 299}…")
      end
    end

    context 'when the text has emoji and combining marks' do
      it 'counts each as one grapheme, as Bluesky does' do
        family = "\u{1F468}‍\u{1F469}‍\u{1F467}" # one grapheme, 18 bytes
        accented = "é" # é as e + combining acute: one grapheme
        expect(described_class.fit("#{family} #{accented} " * 75)).to eq("#{family} #{accented} " * 75)
        long = described_class.fit("#{family} #{accented} " * 76)
        expect(long.grapheme_clusters.size).to be <= 300
        expect(long).to end_with("#{accented}…")
      end
    end

    context 'when 300 graphemes would be over 3,000 bytes' do
      it 'cuts by bytes as well' do
        heavy = "e#{"́" * 20}" # one grapheme, 41 bytes
        text = described_class.fit(([heavy] * 100).join(' '))
        expect(text.bytesize).to be <= 3000
        expect(text).to end_with("#{heavy}…")
      end
    end
  end

  describe '#card_description' do
    it "is the entry's date as the site's heading writes it, with no leading zero" do
      expect(described_class.new('x', date: Date.new(2026, 11, 16)).card_description).to eq('Monday, 16 November 2026')
      expect(described_class.new('x', date: Date.new(2026, 11, 2)).card_description).to eq('Monday, 2 November 2026')
    end
  end

  describe '#record' do
    it 'is a post with the text only, in English, and a link card to the home page' do
      record = described_class.from_leaf(parity_html(275), date: Date.new(2026, 11, 16)).record
      expect(record).to eq(
        '$type' => 'app.bsky.feed.post',
        'text' => 'All statement is overstatement.',
        'langs' => ['en'],
        'embed' => {
          '$type' => 'app.bsky.embed.external',
          'external' => { 'uri' => 'https://sweeperscalendar.com', 'title' => 'The Sweepers Calendar',
                          'description' => 'Monday, 16 November 2026' }
        }
      )
      expect(record['text']).not_to match(%r{https?://|sweeperscalendar|2026})
    end

    context 'when given the uploaded card image' do
      it 'adds it to the card as its thumb' do
        thumb = { '$type' => 'blob', 'ref' => { '$link' => 'bafkrei-example' }, 'mimeType' => 'image/jpeg', 'size' => 100 }
        record = described_class.new('x', date: Date.new(2026, 11, 16)).record(thumb: thumb)
        expect(record.dig('embed', 'external', 'thumb')).to eq(thumb)
      end
    end
  end

  def parity_leaves
    JSON.parse(File.read(File.join(FIXTURES, 'parity-leaves.json')))['leaves']
  end

  def parity_html(day)
    parity_leaves.find { |leaf| leaf['day_of_year'] == day }.fetch('html')
  end
end
