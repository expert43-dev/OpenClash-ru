require 'yaml'
require_relative 'awg'

module OpenClashLocalWG
  def self.proxy(node)
    extra = YAML.safe_load(node['other_parameters'].to_s, aliases: false) || {}
    raise ArgumentError, 'invalid additional parameters' unless extra.is_a?(Hash)
    result = OpenClashAWG.export_values(node).merge(extra)
    { 'name' => 'name', 'server' => 'server', 'wg_ip' => 'ip', 'wg_ipv6' => 'ipv6',
      'private_key' => 'private-key', 'public_key' => 'public-key', 'preshared_key' => 'pre-shared-key',
      'interface_name' => 'interface-name', 'dialer_proxy' => 'dialer-proxy' }.each do |source, target|
      result[target] = node[source] if node[source] && !node[source].empty?
    end
    result['type'], result['udp'] = 'wireguard', node['udp'] != 'false'
    %w[port wg_mtu routing_mark].each do |field|
      value = node[field]
      next if value.nil? || value.empty?
      raise ArgumentError, 'invalid number' unless value.match?(/\A\d+\z/)
      result[{ 'wg_mtu' => 'mtu', 'routing_mark' => 'routing-mark' }.fetch(field, field)] = Integer(value, 10)
    end
    dns = node['wg_dns']
    result['dns'] = dns.is_a?(Array) ? dns : dns.split(/[\s,]+/) if dns && !dns.empty?
    raise ArgumentError, 'incomplete local profile' unless %w[name server port private-key public-key].all? { |k| result.key?(k) }
    result
  end

  def self.merge(config, nodes)
    return config if nodes.empty?
    raise ArgumentError, 'invalid config' unless config.is_a?(Hash)
    proxies = config['proxies'] ||= []
    groups = config['proxy-groups'] || []
    raise ArgumentError, 'invalid config' unless proxies.is_a?(Array) && groups.is_a?(Array)
    names = nodes.map { |n| n['name'] }
    raise ArgumentError, 'duplicate local names' unless names.uniq.size == names.size
    nodes.each do |node|
      name = node['name']
      # Remove a stale subscription copy even when the retained node is disabled.
      proxies.reject! { |p| p['name'] == name }
      groups.each { |g| g['proxies']&.delete(name) }
      next if node['enabled'] == '0'
      proxies << proxy(node)
      patterns = Array(node['groups']).map { |p| p == 'all' ? nil : Regexp.new(p) }
      groups.each do |group|
        next unless patterns.any? { |p| p.nil? || p.match?(group['name'].to_s) }
        (group['proxies'] ||= []) << name
        group['proxies'].uniq!
      end
    end
    groups.each do |group|
      group['proxies'] << 'DIRECT' if group['proxies'].is_a?(Array) && group['proxies'].empty? && Array(group['use']).empty?
    end
    config
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    # JSON emitted by LuCI is a YAML subset; ruby-json is not an OpenClash dependency.
    nodes = YAML.safe_load(STDIN.read, aliases: false)
    raise ArgumentError unless nodes.is_a?(Array)
    unless nodes.empty?
      path = ARGV.fetch(0)
      config = YAML.safe_load(File.read(path), aliases: true)
      result = OpenClashLocalWG.merge(config, nodes)
      temporary = path + '.local-wg.tmp'
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0600) { |f| f.write(YAML.dump(result)) }
      File.rename(temporary, path)
    end
  rescue StandardError
    warn 'Local WireGuard profiles could not be merged; check node settings and proxy groups.'
    exit 1
  end
end
