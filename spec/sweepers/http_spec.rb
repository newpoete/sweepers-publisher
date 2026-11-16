# frozen_string_literal: true

RSpec.describe Sweepers::HTTP do
  describe '#get_json' do
    it 'sends the query and returns the parsed body' do
      requests = stub_net_http(response(Net::HTTPOK, '200', '{"did":"did:plc:calendar"}'))
      data = described_class.new.get_json('https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle',
                                          { handle: 'sweeperscalendar.com' })
      expect(data).to eq('did' => 'did:plc:calendar')
      expect(requests.first.path).to eq('/xrpc/com.atproto.identity.resolveHandle?handle=sweeperscalendar.com')
    end

    context 'when the file is missing and not_found is :nil' do
      it 'returns nil' do
        stub_net_http(response(Net::HTTPNotFound, '404', '<html>Page Not Found</html>'))
        expect(described_class.new.get_json('https://sweeperscalendar.com/leaves/60.json', not_found: :nil)).to be_nil
      end
    end
  end

  describe '#post_json' do
    it 'sends JSON with the bearer token' do
      requests = stub_net_http(response(Net::HTTPOK, '200', '{"uri":"at://x"}'))
      described_class.new.post_json('https://bsky.social/xrpc/com.atproto.repo.createRecord', { repo: 'did:plc:calendar' }, token: 'tok')
      expect(requests.first['Content-Type']).to eq('application/json')
      expect(requests.first['Authorization']).to eq('Bearer tok')
      expect(JSON.parse(requests.first.body)).to eq('repo' => 'did:plc:calendar')
    end

    context 'when the server refuses' do
      it "raises with the status and the server's reason, but nothing from the request" do
        stub_net_http(response(Net::HTTPUnauthorized, '401', '{"error":"AuthenticationRequired","message":"Invalid identifier or password"}'))
        call = -> { described_class.new.post_json('https://bsky.social/xrpc/x', { password: 'app-pass' }) }
        expect(&call).to raise_error(described_class::Error) { |error|
          expect(error.message).to eq('HTTP 401 AuthenticationRequired: Invalid identifier or password')
          expect(error.status).to eq(401)
          expect(error.code).to eq('AuthenticationRequired')
        }
      end
    end

    context 'when the response is not JSON' do
      it 'raises an error saying so' do
        stub_net_http(response(Net::HTTPBadGateway, '502', '<html>Bad gateway</html>'))
        expect { described_class.new.post_json('https://bsky.social/xrpc/x', {}) }
          .to raise_error(described_class::Error, 'HTTP 502: the response was not JSON')
      end
    end
  end

  describe '#post_bytes' do
    it 'sends the bytes with their type and the bearer token' do
      requests = stub_net_http(response(Net::HTTPOK, '200', '{"blob":{}}'))
      described_class.new.post_bytes('https://bsky.social/xrpc/com.atproto.repo.uploadBlob', 'jpg', content_type: 'image/jpeg', token: 'tok')
      expect(requests.first['Content-Type']).to eq('image/jpeg')
      expect(requests.first['Authorization']).to eq('Bearer tok')
      expect(requests.first.body).to eq('jpg')
    end
  end

  # Replaces the connection, so no request leaves the machine. Returns the list
  # the requests made are appended to.
  def stub_net_http(net_response)
    requests = []
    connection = instance_double(Net::HTTP)
    allow(connection).to receive(:request) { |req| requests << req; net_response }
    allow(Net::HTTP).to receive(:start).and_yield(connection)
    requests
  end

  def response(klass, code, body)
    net_response = klass.new('1.1', code, '')
    allow(net_response).to receive(:body).and_return(body)
    net_response
  end
end
