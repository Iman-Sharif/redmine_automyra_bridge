require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeUrlValidatorTest < ActiveSupport::TestCase
  test 'permits valid HTTPS URL resolving to public IP' do
    Resolv.stubs(:getaddresses).with('example.com').returns(['93.184.216.34'])
    assert AutomyraBridge::UrlValidator.safe?('https://example.com/api')
  end

  test 'blocks HTTP by default' do
    Resolv.stubs(:getaddresses).with('example.com').returns(['93.184.216.34'])
    assert_not AutomyraBridge::UrlValidator.safe?('http://example.com/api')
    validator = AutomyraBridge::UrlValidator.new('http://example.com/api')
    validator.safe?
    assert_match(/HTTP URLs are disabled/, validator.error)
  end

  test 'permits HTTP when explicitly allowed' do
    Resolv.stubs(:getaddresses).with('example.com').returns(['93.184.216.34'])
    assert AutomyraBridge::UrlValidator.safe?('http://example.com/api', 'allow_http_outbound' => 'true')
  end

  test 'blocks loopback IPv4' do
    Resolv.stubs(:getaddresses).with('localhost').returns(['127.0.0.1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://localhost/api')
    validator = AutomyraBridge::UrlValidator.new('https://localhost/api')
    validator.safe?
    assert_match(/blocked address/, validator.error)
  end

  test 'blocks loopback IPv6' do
    Resolv.stubs(:getaddresses).with('localhost').returns(['::1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://localhost/api')
    validator = AutomyraBridge::UrlValidator.new('https://localhost/api')
    validator.safe?
    assert_match(/blocked address/, validator.error)
  end

  test 'blocks private IPv4 10.x.x.x' do
    Resolv.stubs(:getaddresses).with('internal.corp').returns(['10.0.0.5'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://internal.corp/api')
  end

  test 'blocks private IPv4 172.16.x.x' do
    Resolv.stubs(:getaddresses).with('internal.corp').returns(['172.16.0.1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://internal.corp/api')
  end

  test 'blocks private IPv4 192.168.x.x' do
    Resolv.stubs(:getaddresses).with('internal.corp').returns(['192.168.1.1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://internal.corp/api')
  end

  test 'blocks link-local 169.254.x.x' do
    Resolv.stubs(:getaddresses).with('metadata.local').returns(['169.254.169.254'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://metadata.local/api')
  end

  test 'blocks IPv6 unique local fc00::/7' do
    Resolv.stubs(:getaddresses).with('internal.local').returns(['fc00::1234'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://internal.local/api')
  end

  test 'blocks IPv6 link-local fe80::/10' do
    Resolv.stubs(:getaddresses).with('internal.local').returns(['fe80::1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://internal.local/api')
  end

  test 'blocks metadata endpoint resolving to link-local' do
    Resolv.stubs(:getaddresses).with('169.254.169.254').returns(['169.254.169.254'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://169.254.169.254/latest/meta-data/')
  end

  test 'blocks carrier grade nat and documentation ranges' do
    Resolv.stubs(:getaddresses).with('shared.example').returns(['100.64.0.1'])
    Resolv.stubs(:getaddresses).with('docs.example').returns(['192.0.2.1'])

    assert_not AutomyraBridge::UrlValidator.safe?('https://shared.example/api')
    assert_not AutomyraBridge::UrlValidator.safe?('https://docs.example/api')
  end

  test 'blocks DNS rebinding when connected peer is private' do
    http = Object.new
    socket = Object.new
    io = Object.new

    http.instance_variable_set(:@socket, socket)
    socket.stubs(:io).returns(io)
    io.stubs(:peeraddr).returns(['AF_INET', 443, 'localhost', '127.0.0.1'])

    error = assert_raises(ArgumentError) { AutomyraBridge::UrlValidator.validate_connected_peer!(http) }
    assert_match(/connected peer is a blocked address/, error.message)
  end

  test 'allows connected peer when address is public' do
    http = Object.new
    socket = Object.new
    io = Object.new

    http.instance_variable_set(:@socket, socket)
    socket.stubs(:io).returns(io)
    io.stubs(:peeraddr).returns(['AF_INET', 443, 'example.com', '93.184.216.34'])

    assert AutomyraBridge::UrlValidator.validate_connected_peer!(http)
  end

  test 'blocks non-resolving hostname' do
    Resolv.stubs(:getaddresses).with('does-not-resolve.test').returns([])
    assert_not AutomyraBridge::UrlValidator.safe?('https://does-not-resolve.test/api')
    validator = AutomyraBridge::UrlValidator.new('https://does-not-resolve.test/api')
    validator.safe?
    assert_match(/did not resolve/, validator.error)
  end

  test 'blocks invalid URI' do
    assert_not AutomyraBridge::UrlValidator.safe?('not a url')
    validator = AutomyraBridge::UrlValidator.new('not a url')
    validator.safe?
    assert_match(/invalid/, validator.error)
  end

  test 'validates all resolved addresses' do
    Resolv.stubs(:getaddresses).with('multi.example').returns(['93.184.216.34', '127.0.0.1'])
    assert_not AutomyraBridge::UrlValidator.safe?('https://multi.example/api')
  end

  test 'dangerous? is inverse of safe?' do
    Resolv.stubs(:getaddresses).with('example.com').returns(['93.184.216.34'])
    validator = AutomyraBridge::UrlValidator.new('https://example.com/api')
    assert validator.safe?
    assert_not validator.dangerous?
  end

  test 'validate! returns URI for safe URL' do
    Resolv.stubs(:getaddresses).with('example.com').returns(['93.184.216.34'])
    uri = AutomyraBridge::UrlValidator.validate!('https://example.com/api')
    assert_equal URI.parse('https://example.com/api'), uri
  end

  test 'validate! raises for unsafe URL' do
    Resolv.stubs(:getaddresses).with('localhost').returns(['127.0.0.1'])
    assert_raises(ArgumentError) { AutomyraBridge::UrlValidator.validate!('https://localhost/api') }
  end

  test 'respects host allowlist when configured' do
    Resolv.stubs(:getaddresses).with('allowed.example').returns(['93.184.216.34'])
    Resolv.stubs(:getaddresses).with('other.example').returns(['93.184.216.35'])
    assert AutomyraBridge::UrlValidator.safe?('https://allowed.example/api', 'allowed_outbound_hosts' => 'allowed.example')
    assert_not AutomyraBridge::UrlValidator.safe?('https://other.example/api', 'allowed_outbound_hosts' => 'allowed.example')
  end

  test 'blocks missing hostname' do
    assert_not AutomyraBridge::UrlValidator.safe?('https:///path')
    validator = AutomyraBridge::UrlValidator.new('https:///path')
    validator.safe?
    assert_match(/hostname/, validator.error)
  end
end
