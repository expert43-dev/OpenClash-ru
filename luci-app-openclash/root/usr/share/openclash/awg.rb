# AmneziaWG options shared by the YAML import and export paths.
require 'yaml'

module OpenClashAWG
  INTEGER_KEYS = %w[version jc jmin jmax s1 s2 s3 s4 itime].freeze
  BOOLEAN_KEYS = %w[random-trailers disable-cookies].freeze
  STRING_KEYS = %w[h1 h2 h3 h4 i1 i2 i3 i4 i5 j1 j2 j3
                   header-protection-key content-padding-addition rekey-after-time
                   rekey-timeout reject-after-time keepalive-timeout
                   max-handshake-attempts].freeze
  KEYS = (INTEGER_KEYS + BOOLEAN_KEYS + STRING_KEYS).freeze
  # These fields are already emitted by yml_proxys_set.sh.
  BASE_KEYS = %w[name type server port ip ipv6 private-key public-key pre-shared-key
                 preshared-key dns mtu udp interface-name routing-mark dialer-proxy smux
                 amnezia-wg-option].freeze

  def self.option_name(key)
    'awg_' + key.tr('-', '_')
  end

  # Quote for libuci's batch parser, not a shell. No interpolation or evaluation.
  def self.uci_quote(value)
    raise ArgumentError, 'multiline AWG value' if value.match?(/[\r\n\x00]/)
    '"' + value.gsub(/[\\"]/) { |char| '\\' + char } + '"'
  end

  def self.import_values(proxy)
    extras = proxy.reject { |key, _| BASE_KEYS.include?(key) }
    values = { 'wg_extra_blob' => [YAML.dump(extras)].pack('m0') }
    values['wg_has_peers'] = proxy['peers'].is_a?(Array) && !proxy['peers'].empty? ? '1' : '0'
    options = proxy['amnezia-wg-option']
    values['awg_enable'] = options.is_a?(Hash) ? '1' : '0'
    return values unless options.is_a?(Hash)

    values['awg_options_blob'] = [YAML.dump(options)].pack('m0')
    KEYS.each do |key|
      next unless options.key?(key)
      values[option_name(key)] = options[key].to_s
    end
    # Missing version means the legacy implementation, never automatically v3.
    values['awg_version'] ||= '2'
    values
  end

  def self.import_commands(prefix, proxy)
    import_values(proxy).map { |key, value| prefix + key + '=' + uci_quote(value) }
  end

  # Use core Ruby Base64 packing and the YAML dependency already shipped by OpenClash.
  # A one-line blob survives libuci; safe_load prevents Ruby object deserialization.
  def self.decode_hash(value)
    return {} if value.nil? || value.empty?
    result = YAML.safe_load(value.unpack1('m0'), aliases: true)
    raise ArgumentError, 'expected AWG object' unless result.is_a?(Hash)
    result
  end

  def self.export_values(values)
    result = decode_hash(values['wg_extra_blob']).reject { |key, _| BASE_KEYS.include?(key) }
    return result unless values['awg_enable'] == '1'

    options = decode_hash(values['awg_options_blob'])
    KEYS.each do |key|
      value = values[option_name(key)]
      # Keep explicitly empty packet signatures from an imported configuration.
      if value.nil? || value.empty?
        options.delete(key) unless options[key] == '' && STRING_KEYS.include?(key)
      elsif INTEGER_KEYS.include?(key)
        raise ArgumentError, "invalid AWG #{key}" unless value.match?(/\A\d+\z/)
        options[key] = Integer(value, 10)
      elsif BOOLEAN_KEYS.include?(key)
        raise ArgumentError, "invalid AWG #{key}" unless %w[true false].include?(value)
        options[key] = value == 'true'
      else
        raise ArgumentError, "multiline AWG #{key}" if value.match?(/[\r\n\x00]/)
        options[key] = value
      end
    end
    options['version'] ||= 2
    raise ArgumentError, 'invalid AWG version' unless [1, 2, 3].include?(options['version'])
    if options['version'] == 3
      # v1.5-only signatures are incompatible with v3; retain them in UCI for switching back.
      %w[j1 j2 j3 itime].each { |key| options.delete(key) }
    else
      %w[header-protection-key content-padding-addition rekey-after-time rekey-timeout
         reject-after-time keepalive-timeout max-handshake-attempts random-trailers
         disable-cookies].each { |key| options.delete(key) }
    end
    result['amnezia-wg-option'] = options
    result
  end

  def self.yaml_fragment(values)
    result = export_values(values)
    return '' if result.empty?
    YAML.dump(result).sub(/\A---\s*\n/, '').lines.map { |line| '    ' + line }.join
  end
end

if __FILE__ == $PROGRAM_NAME
  values = ENV.select { |key, _| key.start_with?('OPENCLASH_AWG_') }
              .transform_keys { |key| key.delete_prefix('OPENCLASH_AWG_') }
  print OpenClashAWG.yaml_fragment(values)
end
