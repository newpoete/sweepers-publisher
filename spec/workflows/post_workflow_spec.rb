# frozen_string_literal: true

require 'yaml'

# The posting workflow's safety rules (sweepers-editor#129), checked so an edit
# can't quietly make a push post, or a manual run post by default.
RSpec.describe 'Post workflow' do
  def workflow
    path = File.join(ROOT, '.github', 'workflows', 'post.yml')
    YAML.safe_load_file(path, aliases: false)
  end

  # YAML 1.1 reads the bare key "on" as true.
  def triggers(data)
    data[true] || data['on']
  end

  describe 'triggers' do
    it 'runs only when started by hand, and a manual run is a dry run by default' do
      on = triggers(workflow)
      expect(on.keys).to eq(['workflow_dispatch'])
      expect(on.dig('workflow_dispatch', 'inputs', 'dry_run')).to include('type' => 'boolean', 'default' => true)
    end
  end

  describe 'secrets' do
    it 'gets only the app password, through the environment, and never the queue key' do
      text = File.read(File.join(ROOT, '.github', 'workflows', 'post.yml'))
      expect(text.scan(/secrets\.\w+/).uniq).to eq(['secrets.BLUESKY_APP_PASSWORD'])
      expect(workflow.dig('jobs', 'post', 'steps').find { |step| step['name'] == 'Post' }.dig('env', 'BLUESKY_APP_PASSWORD'))
        .to eq('${{ secrets.BLUESKY_APP_PASSWORD }}')
    end
  end

  describe 'concurrency' do
    it 'runs one post at a time, separately from the release, and never cancels one midway' do
      expect(workflow['concurrency']).to eq('group' => 'bluesky-post', 'cancel-in-progress' => false)
      expect(workflow['permissions']).to eq('contents' => 'read')
    end
  end
end
