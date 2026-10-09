require_relative '../luci-app-openclash/root/usr/share/openclash/awg_local'
require 'tmpdir'

node = YAML.safe_load(File.read('build/awg-import-test-values.json'), aliases: false)
config = {'proxies'=>[{'name'=>'Other','type'=>'direct'}, {'name'=>node['name'],'type'=>'direct'}],
          'proxy-groups'=>[{'name'=>'Main','type'=>'select','proxies'=>['Other',node['name']]},
                           {'name'=>'OtherGroup','type'=>'select','proxies'=>['Other']}],
          'rules'=>['MATCH,Main']}
original_rules = config['rules'].dup
2.times { OpenClashLocalWG.merge(config, [node]) }
proxy = config['proxies'].find { |p| p['name']==node['name'] }
raise unless config['proxies'].size==2 && proxy['type']=='wireguard'
raise unless proxy['amnezia-wg-option']['random-trailers']==false && proxy['amnezia-wg-option']['jc']==0
raise unless proxy['persistent-keepalive']==0 && proxy['allowed-ips']==['0.0.0.0/0','::/0']
raise unless proxy['ip']=='10.78.0.2' && proxy['port']==585 && proxy['private-key']==node['private_key']
raise unless config['proxy-groups'][0]['proxies'].count(node['name'])==1
raise if config['proxy-groups'][1]['proxies'].include?(node['name'])
raise unless config['rules']==original_rules
# Simulate replacing the subscription with a new document, then reapply locals.
fresh = {'proxies'=>[], 'proxy-groups'=>[{'name'=>'Main','proxies'=>['DIRECT']}], 'rules'=>['MATCH,DIRECT']}
OpenClashLocalWG.merge(fresh, [node])
raise unless fresh['proxies'].size==1 && fresh['proxy-groups'][0]['proxies'].include?(node['name'])
OpenClashLocalWG.merge(fresh, [node.merge('enabled'=>'0')])
raise unless fresh['proxies'].empty? && !fresh['proxy-groups'][0]['proxies'].include?(node['name'])
# No ruby-json package required; CLI accepts the LuCI JSON as safe YAML.
Dir.mktmpdir do |dir|
  path = File.join(dir,'runtime.yaml'); File.write(path,YAML.dump(config))
  input = File.read('build/awg-import-test-values.json')
  IO.popen(['ruby','luci-app-openclash/root/usr/share/openclash/awg_local.rb',path], 'w') { |io| io.write('['+input+']') }
  raise unless $?.success?
  raise unless YAML.safe_load(File.read(path), aliases:true)['proxies'].size==2
end
puts 'Local WireGuard merge: imported form -> YAML, subscription replacement, groups, idempotence and disabling passed'
