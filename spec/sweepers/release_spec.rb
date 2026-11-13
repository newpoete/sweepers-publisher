# frozen_string_literal: true

RSpec.describe Sweepers::Release do
  describe '.new' do
    context 'when a leaf is invalid' do
      it 'raises InvalidLeaf naming the problem' do
        leaf = build_leaf(1)
        expect { release_on('2026-11-12', leaf.merge('version' => 2)) }.to raise_error(described_class::InvalidLeaf, /version/)
        expect { release_on('2026-11-12', build_leaf(367)) }.to raise_error(described_class::InvalidLeaf, /outside 1-366/)
        expect { release_on('2026-11-12', leaf.merge('html' => '')) }.to raise_error(described_class::InvalidLeaf, /html/)
        expect { release_on('2026-11-12', leaf.merge('score' => '9')) }.to raise_error(described_class::InvalidLeaf, /score/)
        expect { release_on('2026-11-12', leaf.merge('published_at' => 'soon')) }.to raise_error(described_class::InvalidLeaf)
        expect { release_on('2026-11-12', leaf.except('draft_id')) }.to raise_error(described_class::InvalidLeaf, /draft_id/)
      end
    end

    context 'when two leaves share a day' do
      it 'raises InvalidLeaf' do
        expect { release_on('2026-11-12', build_leaf(5), build_leaf(5)) }.to raise_error(described_class::InvalidLeaf, /two leaves for day 5/)
      end
    end
  end

  describe '#released_leaves' do
    it 'releases today, yesterday, the day before and the selections only' do
      leaves = (1..366).map { |day| build_leaf(day, score: day == 300 ? 9 : 5) }
      expect(released_days(release_on('2026-11-12', *leaves))).to eq([300, 315, 316, 317])
    end

    it 'never releases a day after the release date' do
      leaves = (318..366).map { |day| build_leaf(day, score: 10) } + [build_leaf(317)]
      expect(released_days(release_on('2026-11-12', *leaves))).to eq([317])
    end

    context 'when the release date moves to the next day' do
      it "releases that day's leaf" do
        leaf = build_leaf(318)
        expect(released_days(release_on('2026-11-12', leaf))).to be_empty
        expect(released_days(release_on('2026-11-13', leaf))).to eq([318])
      end
    end

    context 'when a day has no leaf' do
      it 'releases nothing for it' do
        expect(released_days(release_on('2026-11-12', build_leaf(316)))).to eq([316])
      end
    end

    context 'when the release falls on 1 January' do
      it 'releases 31 and 30 December as the two days before' do
        release = release_on('2027-01-01', build_leaf(1), build_leaf(365), build_leaf(366), build_leaf(364))
        expect(released_days(release)).to eq([1, 365, 366])
      end
    end

    context 'when the release falls on 1 March of a non-leap year' do
      it 'treats 28 February as yesterday and never releases day 60' do
        release = release_on('2027-03-01', build_leaf(58), build_leaf(59), build_leaf(60), build_leaf(61))
        expect(released_days(release)).to eq([58, 59, 61])
      end
    end

    context 'when the release falls on 29 February' do
      it 'releases day 60 as today' do
        expect(released_days(release_on('2028-02-29', build_leaf(60)))).to eq([60])
      end
    end
  end

  describe '#selections' do
    it 'keeps the best 7 scoring 8 or more and lists them newest first' do
      # Days 300-316 before 2026-11-12 (day 317). Scores 6 + day % 5: 10s on 314, 309, 304;
      # 9s on 313, 308, 303; the newest 8 is 312.
      leaves = (300..316).map { |day| build_leaf(day, score: 6 + (day % 5)) }
      days = release_on('2026-11-12', *leaves).selections.map { |s| s.leaf.day_of_year }
      expect(days).to eq([314, 313, 312, 309, 308, 304, 303])
    end

    it "leaves out today's leaf, low scores and days more than 90 days back" do
      leaves = [build_leaf(317, score: 10), build_leaf(316, score: 7), build_leaf(227, score: 10), build_leaf(226, score: 10)]
      days = release_on('2026-11-12', *leaves).selections.map { |s| s.leaf.day_of_year }
      expect(days).to eq([227]) # day 227 is exactly 90 days back; 226 is 91
    end

    it 'lists each selection under the most recent date its day fell on' do
      selection = release_on('2026-11-12', build_leaf(314, score: 10)).selections.first
      expect(selection.date).to eq(Date.new(2026, 11, 9))
    end

    context 'when the window spans the new year' do
      it 'includes December leaves, dated in the previous year' do
        selections = release_on('2027-01-05', build_leaf(360, score: 9), build_leaf(3, score: 8)).selections
        expect(selections.map { |s| [s.leaf.day_of_year, s.date] }).to eq([[3, Date.new(2027, 1, 3)], [360, Date.new(2026, 12, 25)]])
      end
    end
  end

  describe '#files' do
    it 'never writes a leaf for a day after the release date' do
      leaves = [build_leaf(317), build_leaf(318, score: 10, html: '<p>FUTURE</p>'), build_leaf(1, score: 10, html: '<p>FUTURE</p>')]
      files = release_on('2026-11-12', *leaves).files
      expect(files.values.join).not_to include('FUTURE')
      expect(files).to have_key('leaves/317.json')
    end

    it 'writes release.json with today and yesterday' do
      record = JSON.parse(release_on('2027-01-01').files['release.json'])
      expect(record).to include('date' => '2027-01-01', 'day_of_year' => 1,
                                'yesterday' => { 'date' => '2026-12-31', 'day_of_year' => 366 })
    end

    it 'writes each released leaf as its day and html only' do
      leaf_file = JSON.parse(release_on('2026-11-12', build_leaf(317)).files['leaves/317.json'])
      expect(leaf_file).to eq('day_of_year' => 317, 'html' => "<p>leaf 317</p>\n")
    end

    it 'writes a sitemap of https URLs including each selection' do
      sitemap = release_on('2026-11-12', build_leaf(314, score: 10)).files['sitemap.txt'].lines.map(&:chomp)
      expected = %w[today yesterday selections selection/314].map { |path| "#{described_class::DEFAULT_BASE_URL}/#{path}" }
      expect(sitemap).to eq(expected)
    end

    it 'writes robots.txt allowing all crawlers and pointing to the sitemap' do
      robots = release_on('2026-11-12').files['robots.txt']
      expect(robots).to eq("User-agent: *\nDisallow:\n\nSitemap: #{described_class::DEFAULT_BASE_URL}/sitemap.txt\n")
    end

    context 'when a selection has a snippet' do
      it 'uses the snippet instead of the leaf text' do
        leaf = build_leaf(316, score: 9, html: '<p>full text</p>', snippet: 'short')
        expect(JSON.parse(release_on('2026-11-12', leaf).files['selections.json']).first['snippet']).to eq('short')
      end
    end

    context 'when the queue is empty' do
      it 'writes only release.json, an empty selections.json, the sitemap and robots.txt' do
        files = release_on('2026-11-12').files
        expect(files.keys).to contain_exactly('release.json', 'selections.json', 'sitemap.txt', 'robots.txt')
        expect(JSON.parse(files['selections.json'])).to eq([])
      end
    end
  end

  describe '#write' do
    it 'builds the site with its pages, data files and selection pages' do
      Dir.mktmpdir do |dir|
        out = File.join(dir, 'site')
        release_on('2026-11-12', build_leaf(314, score: 10), build_leaf(317))
          .write(out, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data'), templates_dir: File.join(ROOT, 'templates'))
        paths = %w[release.json selections.json sitemap.txt robots.txt mountweazel.json leaves/314.json leaves/317.json
                   selection/314.html selections.html today.html mountweazel.html calendar/mountweazel.html 404.html]
        expect(paths.reject { |path| File.exist?(File.join(out, path)) }).to be_empty
        expect(File.exist?(File.join(out, 'selection.html'))).to be(false)
        expect(File.read(File.join(out, '404.html'))).to include('<base href="/sweepers-publisher/">')
        expect(File.exist?("#{out}.partial")).to be(false)
      end
    end

    context 'when the output directory already exists' do
      it 'refuses to write' do
        Dir.mktmpdir do |dir|
          release = release_on('2026-11-12')
          expect { release.write(dir, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data'), templates_dir: File.join(ROOT, 'templates')) }
            .to raise_error(ArgumentError, /already exists/)
        end
      end
    end
  end

  describe '#not_found_page' do
    it "sets the page's base to the site root's path from the base URL" do
      template = '<base href="{{base_path}}/">'
      staging = described_class.new([], date: Date.new(2026, 11, 12), base_url: 'https://newpoete.github.io/sweepers-publisher/')
      domain = described_class.new([], date: Date.new(2026, 11, 12), base_url: 'https://sweeperscalendar.com')
      expect(staging.not_found_page(template)).to eq('<base href="/sweepers-publisher/">')
      expect(domain.not_found_page(template)).to eq('<base href="/">')
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
