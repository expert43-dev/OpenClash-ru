require 'yaml'
require 'tmpdir'
require 'shellwords'
require_relative '../luci-app-openclash/root/usr/share/openclash/awg'

def check(condition, message)
  raise message unless condition
end

fixture = {
  'type' => 'wireguard', 'name' => 'AWG 3.1',
  'allowed-ips' => ['0.0.0.0/0', '::/0'], 'persistent-keepalive' => 25,
  'peers' => [{ 'server' => '192.0.2.1', 'public-key' => 'public',
                'allowed-ips' => ['0.0.0.0/0'] }],
  'amnezia-wg-option' => {
    'version' => 3, 'jc' => 0, 'jmin' => 500, 'jmax' => 900,
    's1' => 30, 's2' => 40, 's3' => 0, 's4' => 8,
    'h1' => '123456-123459', 'h2' => '67543', 'h3' => '123123', 'h4' => '32345',
    'i1' => '<b 0xf6ab3267fa><t><r 10>', 'i2' => '<b 0xf6ab><r 100>',
    'i3' => '', 'i4' => '', 'i5' => '',
    'header-protection-key' => 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
    'content-padding-addition' => '0-32', 'rekey-after-time' => '120',
    'rekey-timeout' => '5', 'reject-after-time' => '180',
    'keepalive-timeout' => '10', 'max-handshake-attempts' => '18',
    'random-trailers' => true, 'disable-cookies' => false,
    'future-option' => { 'value' => 'literal "quote", \\path, ${no_expansion}' }
  }
}
values = OpenClashAWG.import_values(fixture)
result = OpenClashAWG.export_values(values)
check(result['amnezia-wg-option'] == fixture['amnezia-wg-option'], 'AWG 3.1 round trip')
check(result['peers'] == fixture['peers'], 'multi-peer preservation')
check(result['allowed-ips'] == fixture['allowed-ips'], 'allowed IP preservation')
check(result['persistent-keepalive'] == 25, 'keepalive preservation')
fragment = OpenClashAWG.yaml_fragment(values)
check(YAML.safe_load(fragment) == result, 'generated YAML types and escaping')
check(fragment.include?('disable-cookies: false'), 'explicit false was lost')
check(result['amnezia-wg-option']['jc'] == 0, 'explicit zero was lost')
check(OpenClashAWG.export_values(values.merge('awg_enable' => '0'))['amnezia-wg-option'].nil?, 'disable AWG')
check(OpenClashAWG.export_values(values.merge('awg_h1' => ''))['amnezia-wg-option']['h1'].nil?, 'clear field')
legacy = OpenClashAWG.import_values('type' => 'wireguard', 'amnezia-wg-option' => { 'jc' => 1 })
check(legacy['awg_version'] == '2', 'legacy imported as version 3')
check(OpenClashAWG.yaml_fragment(OpenClashAWG.import_values('type' => 'wireguard')).empty?, 'plain WireGuard changed')
check(!OpenClashAWG.export_values(values.merge('awg_version' => '2'))['amnezia-wg-option'].key?('random-trailers'), 'v3 fields in legacy config')
check(!OpenClashAWG.export_values(values.merge('awg_j1' => 'test'))['amnezia-wg-option'].key?('j1'), 'v1.5 fields in v3 config')
begin
  OpenClashAWG.export_values(values.merge('awg_version' => '3.1'))
  raise 'fractional version accepted'
rescue ArgumentError
end
begin
  OpenClashAWG.import_commands('set openclash.test.', 'amnezia-wg-option' => { 'i1' => "a\nb" })
  raise 'UCI command injection accepted'
rescue ArgumentError
end
check(OpenClashAWG.uci_quote('a"b\\c${x}') == '"a\\"b\\\\c${x}"', 'UCI quoting')

# Exercise the actual server writer, including its multi-peer guard and YAML nesting.
Dir.mktmpdir('openclash-awg-test') do |dir|
  share = File.expand_path('../luci-app-openclash/root/usr/share/openclash', __dir__)
  writer = File.read(File.join(share, 'yml_proxys_set.sh'))
               .split("yml_servers_set()\n", 2).last.split("\nyml_servers_name_get()", 2).first
  helper = File.read(File.join(share, 'awg.sh')).sub('/usr/share/openclash/awg.rb', File.join(share, 'awg.rb'))
  fixture_values = values.merge('enabled' => '1', 'config' => 'all', 'type' => 'wireguard',
                                'name' => 'AWG 3.1', 'wg_ip' => '10.0.0.2',
                                'private_key' => 'private', 'preshared_key' => 'shared', 'udp' => 'true')
  config_get = "config_get() { case \"$3\" in\n" + fixture_values.map do |key, value|
    "#{key}) export \"$1=\"#{Shellwords.escape(value)} ;;\n"
  end.join + "*) export \"$1=$4\" ;;\nesac; }\nconfig_get_bool() { config_get \"$@\"; }\n"
  output = File.join(dir, 'servers.yaml')
  script = "#!/bin/bash\n" + config_get + "LOG_OUT() { :; }\nLOG_ERROR() { exit 7; }\n" + helper +
           "\nSERVER_FILE=#{Shellwords.escape(output)}\nservers_name=/dev/null\nCONFIG_NAME=test.yaml\n" +
           "yml_servers_set()\n" + writer + "\nprintf 'proxies:\\n' > \"$SERVER_FILE\"\nyml_servers_set test\n"
  path = File.join(dir, 'writer.sh')
  File.write(path, script)
  check(system('bash', path), 'server writer failed')
  node = YAML.safe_load_file(output)['proxies'].first
  check(node['amnezia-wg-option'] == fixture['amnezia-wg-option'], 'writer AWG round trip')
  check(node['peers'] == fixture['peers'], 'writer dropped peer-only node')
  check(node['pre-shared-key'] == 'shared' && !node.key?('preshared-key'), 'wrong preshared key spelling')
end

# The integration test uses these public fixture values with libuci on the router.
if ARGV[0] == '--uci-fixture'
  puts YAML.dump({ 'proxy' => fixture, 'values' => values,
                       'commands' => OpenClashAWG.import_commands('set openclash.awgtest.', fixture) })
else
  puts 'AWG import/export tests passed (3.1, legacy, WireGuard, peers, zero/false, escaping)'
end
