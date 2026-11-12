# frozen_string_literal: true

RSpec.describe Sweepers::Release do
  describe '.new' do
    context 'when a leaf is invalid' do
      it 'raises InvalidLeaf naming the problem' do
        leaf = build_leaf(2026, 1)
        expect { release_on('2026-11-12', leaf.merge('version' => 2)) }.to raise_error(described_class::InvalidLeaf, /version/)
        expect { release_on('2026-11-12', build_leaf(2026, 367)) }.to raise_error(described_class::InvalidLeaf, /outside 1-366/)
        expect { release_on('2026-11-12', leaf.merge('html' => '')) }.to raise_error(described_class::InvalidLeaf, /html/)
        expect { release_on('2026-11-12', leaf.merge('score' => '9')) }.to raise_error(described_class::InvalidLeaf, /score/)
        expect { release_on('2026-11-12', leaf.merge('published_at' => 'soon')) }.to raise_error(described_class::InvalidLeaf)
        expect { release_on('2026-11-12', leaf.except('year')) }.to raise_error(described_class::InvalidLeaf, /year/)
      end
    end
  end

  describe '#leaves_by_day' do
    context 'when a leaf is dated the day after the release' do
      it 'withholds it, then releases it on its day' do
        leaf = build_leaf(2026, 318)
        expect(release_on('2026-11-12', leaf).leaves_by_day).not_to have_key(318)
        expect(release_on('2026-11-13', leaf).leaves_by_day).to have_key(318)
      end
    end

    context 'when a day has leaves from several years' do
      it 'picks the newest year' do
        release = release_on('2026-11-12', build_leaf(2019, 317, html: '<p>old</p>'), build_leaf(2026, 317, html: '<p>new</p>'))
        expect(release.leaves_by_day[317].html).to eq('<p>new</p>')
      end
    end

    context 'when only an old leaf exists for a day' do
      it 'keeps serving it, as Flask did' do
        release = release_on('2026-11-12', build_leaf(2015, 317, html: '<p>2015</p>'))
        expect(release.leaves_by_day[317].html).to eq('<p>2015</p>')
      end
    end

    context "when this year's leaf for a day is not yet due" do
      it "serves last year's leaf until then" do
        leaves = [build_leaf(2025, 318, html: '<p>2025</p>'), build_leaf(2026, 318, html: '<p>2026</p>')]
        expect(release_on('2026-11-12', *leaves).leaves_by_day[318].html).to eq('<p>2025</p>')
        expect(release_on('2026-11-13', *leaves).leaves_by_day[318].html).to eq('<p>2026</p>')
      end
    end

    context 'when a day was published twice in the same year' do
      it 'picks the latest publish' do
        first = build_leaf(2026, 300, html: '<p>first</p>', published_at: '2026-09-01T00:00:00Z')
        again = build_leaf(2026, 300, html: '<p>again</p>', published_at: '2026-10-01T00:00:00Z')
        expect(release_on('2026-11-12', first, again).leaves_by_day[300].html).to eq('<p>again</p>')
      end
    end

    context 'when the leaf is for day 60 in a non-leap year' do
      it 'releases it on 1 March' do
        leaf = build_leaf(2027, 60)
        expect(release_on('2027-02-28', leaf).leaves_by_day).not_to have_key(60)
        expect(release_on('2027-03-01', leaf).leaves_by_day).to have_key(60)
      end
    end

    context 'when the leaf is for day 60 in a leap year' do
      it 'releases it on 29 February' do
        leaf = build_leaf(2028, 60)
        expect(release_on('2028-02-28', leaf).leaves_by_day).not_to have_key(60)
        expect(release_on('2028-02-29', leaf).leaves_by_day).to have_key(60)
      end
    end
  end

  describe '#selections' do
    it 'keeps the best 7 scoring 8 or more and lists them newest first' do
      # Days 300-316 before 2026-11-12 (day 317). Scores 6 + day % 5: 10s on 314, 309, 304;
      # 9s on 313, 308, 303; the newest 8 is 312.
      leaves = (300..316).map { |day| build_leaf(2026, day, score: 6 + (day % 5)) }
      days = release_on('2026-11-12', *leaves).selections.map { |s| s.leaf.day_of_year }
      expect(days).to eq([314, 313, 312, 309, 308, 304, 303])
    end

    it "leaves out today's leaf, low scores and days more than 90 days back" do
      leaves = [build_leaf(2026, 317, score: 10), build_leaf(2026, 316, score: 7),
                build_leaf(2026, 227, score: 10), build_leaf(2026, 226, score: 10)]
      days = release_on('2026-11-12', *leaves).selections.map { |s| s.leaf.day_of_year }
      expect(days).to eq([227]) # day 227 is exactly 90 days back; 226 is 91
    end

    context 'when the recent days are served by old leaves' do
      it 'still selects them, listed under their most recent date' do
        selections = release_on('2026-11-12', build_leaf(2019, 314, score: 10)).selections
        expect(selections.map { |s| [s.leaf.day_of_year, s.date] }).to eq([[314, Date.new(2026, 11, 9)]])
      end
    end

    context 'when the window spans the new year' do
      it 'includes December leaves, dated in the previous year' do
        selections = release_on('2027-01-05', build_leaf(2026, 360, score: 9), build_leaf(2027, 3, score: 8)).selections
        expect(selections.map { |s| [s.leaf.day_of_year, s.date] }).to eq([[3, Date.new(2027, 1, 3)], [360, Date.new(2026, 12, 25)]])
      end
    end
  end

  describe '#files' do
    it 'never releases a leaf dated after the release date' do
      leaves = [build_leaf(2026, 317, score: 10), build_leaf(2026, 318, score: 10, html: '<p>FUTURE</p>'),
                build_leaf(2027, 1, score: 10, html: '<p>FUTURE</p>')]
      files = release_on('2026-11-12', *leaves).files
      expect(files.values.join).not_to include('FUTURE')
      expect(files).to have_key('leaves/317.json')
    end

    it 'writes release.json with today and yesterday' do
      record = JSON.parse(release_on('2027-01-01').files['release.json'])
      expect(record).to include('date' => '2027-01-01', 'day_of_year' => 1,
                                'yesterday' => { 'date' => '2026-12-31', 'day_of_year' => 366 })
    end

    it 'writes each leaf without its year, since pages show the release year' do
      leaf_file = JSON.parse(release_on('2026-11-12', build_leaf(2019, 317)).files['leaves/317.json'])
      expect(leaf_file).to eq('day_of_year' => 317, 'html' => "<p>leaf 2019-317</p>\n")
    end

    it 'writes a sitemap of https URLs including each selection' do
      sitemap = release_on('2026-11-12', build_leaf(2026, 314, score: 10)).files['sitemap.txt'].lines.map(&:chomp)
      expected = %w[today yesterday selections selection/314].map { |path| "#{described_class::DEFAULT_BASE_URL}/#{path}" }
      expect(sitemap).to eq(expected)
    end

    context 'when a selection has a snippet' do
      it 'uses the snippet instead of the leaf text' do
        leaf = build_leaf(2026, 316, score: 9, html: '<p>full text</p>', snippet: 'short')
        expect(JSON.parse(release_on('2026-11-12', leaf).files['selections.json']).first['snippet']).to eq('short')
      end
    end

    context 'when the queue is empty' do
      it 'writes only release.json, an empty selections.json and the sitemap' do
        files = release_on('2026-11-12').files
        expect(files.keys).to contain_exactly('release.json', 'selections.json', 'sitemap.txt')
        expect(JSON.parse(files['selections.json'])).to eq([])
      end
    end
  end

  describe '#write' do
    it 'builds the site with the shell, data files and selection pages' do
      Dir.mktmpdir do |dir|
        out = File.join(dir, 'site')
        release_on('2026-11-12', build_leaf(2026, 314, score: 10), build_leaf(2026, 317))
          .write(out, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data'))
        paths = %w[release.json selections.json sitemap.txt mountweazel.json leaves/314.json leaves/317.json
                   selection/314.html selection.html]
        expect(paths.reject { |path| File.exist?(File.join(out, path)) }).to be_empty
        expect(File.exist?("#{out}.partial")).to be(false)
      end
    end

    context 'when the output directory already exists' do
      it 'refuses to write' do
        Dir.mktmpdir do |dir|
          release = release_on('2026-11-12')
          expect { release.write(dir, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data')) }
            .to raise_error(ArgumentError, /already exists/)
        end
      end
    end
  end

  describe '.snippet' do
    it 'strips tags and decodes entities like Jinja striptags' do
      expect(described_class.snippet("<p>Don&#39;t <em>panic</em>.</p>\n")).to eq("Don't panic.")
    end

    context 'when the text is longer than 300 characters' do
      it 'cuts at a word boundary and appends " ..." like Jinja 2.8 truncate' do
        snippet = described_class.snippet("<p>#{(['word'] * 100).join(' ')}</p>")
        expect(snippet.length).to be <= 300
        expect(snippet).to end_with('word ...')
      end
    end
  end
end
