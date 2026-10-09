const assert = require('node:assert/strict');
const zlib = require('node:zlib');
const fs = require('node:fs');
const api = require('../luci-app-openclash/root/www/luci-static/resources/openclash/js/awg-import.js');
const key = Buffer.alloc(32, 1).toString('base64');
const conf = `[Interface]\nPrivateKey = ${key}\nAddress = 10.78.0.2/32, fd01::2/128\nDNS = 1.1.1.1, 2606:4700:4700::1111\nJc = 0\nJmin = 10\nJmax = 20\nS1 = 0\nH1 = 100-200\nI1 = <b 0x1234>\nHeaderProtectionKey = ${key}\nRandomTrailers = false\nDisableCookies = 1\nRekeyAfterTime = 0\nContentPaddingAddition = 0-5\n\n[Peer]\nPublicKey = ${key}\nPresharedKey = ${key}\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = [2001:db8::1]:585\nPersistentKeepalive = 0\n`;
function link(data, compressed=true) {
    const bytes = Buffer.from(JSON.stringify(data));
    let packed = bytes;
    if (compressed) { const header = Buffer.alloc(4); header.writeUInt32BE(bytes.length); packed = Buffer.concat([header, zlib.deflateSync(bytes)]); }
    return 'vpn://' + packed.toString('base64url');
}
function share(text=conf) {
    return {description: 'Проверка <script>', containers: [{container:'amnezia-awg2', awg:{protocol_version:'3.1', last_config:JSON.stringify({config:text, mtu:'1376', RandomTrailers:false})}}]};
}
(async function() {
    const r = (await api.parse('\uFEFF' + conf, 'Тест'))[0];
    assert.equal(r.fields.wg_ip, '10.78.0.2'); assert.equal(r.fields.wg_ipv6, 'fd01::2');
    assert.equal(r.fields.server, '2001:db8::1'); assert.equal(r.fields.port, '585');
    assert.equal(r.fields.awg_jc, '0'); assert.equal(r.fields.awg_rekey_after_time, '0');
    assert.equal(r.fields.awg_random_trailers, 'false'); assert.equal(r.fields.awg_disable_cookies, 'true');
    assert.equal(r.fields.awg_version, '3'); assert.equal(r.fields.awg_local, '1');
    assert.match(r.fields.other_parameters, /persistent-keepalive: 0/);
    for (const compressed of [true,false]) {
        const imported = (await api.parse(link(share(), compressed)))[0];
        assert.equal(imported.fields.wg_mtu, '1376'); assert.equal(imported.name, 'Проверка <script>');
        assert.equal(imported.fields.awg_random_trailers, 'false');
    }
    const multi = share(); multi.containers.push({container:'amnezia-awg', awg:{last_config:conf}});
    assert.equal((await api.parse(link(multi))).length, 2);
    const plainWG = conf.replace(/^(?:Jc|Jmin|Jmax|S1|H1|I1|HeaderProtectionKey|RandomTrailers|DisableCookies|RekeyAfterTime|ContentPaddingAddition).*\n/gm, '');
    assert.equal((await api.parse(plainWG))[0].fields.awg_enable, '0');
    const legacy = plainWG.replace('[Peer]', 'Jc = 0\nH1 = 100\n[Peer]');
    const old = (await api.parse(legacy))[0]; assert.equal(old.fields.awg_version, '2'); assert.equal(old.warning, 'CHECK_VERSION');
    await assert.rejects(api.parse(conf + '\n[Peer]\nPublicKey = ' + key), /MULTIPLE_PEERS/);
    await assert.rejects(api.parse(conf.replace('Address =', 'PrivateKey = ' + key + '\nAddress =')), /DUPLICATE_FIELD/);
    await assert.rejects(api.parse(conf.replace('[Peer]', 'PostUp = reboot\n[Peer]')), /UNSUPPORTED_FIELD/);
    await assert.rejects(api.parse(conf.replace('RandomTrailers = false', 'RandomTrailers = nope')), /INVALID/);
    await assert.rejects(api.parse(conf.replace('Address = 10.78.0.2/32', 'Address = 999.0.0.2/32')), /INVALID/);
    await assert.rejects(api.parse(conf.replace('Jmax = 20', 'Jmax = 2')), /INVALID/);
    await assert.rejects(api.parse(link({api_config:{key:'subscription'}})), /SUBSCRIPTION/);
    await assert.rejects(api.parse(link({containers:[]})), /NO_PROFILE/);
    await assert.rejects(api.parse('vpn://not-a-config'), /TOO_LARGE|INVALID/);
    await assert.rejects(api.parse('x'.repeat(api.limit + 1)), /TOO_LARGE/);
    const bomb = Buffer.concat([Buffer.from([0,0,0,1]), zlib.deflateSync(Buffer.alloc(api.limit+1,65))]);
    await assert.rejects(api.parse('vpn://' + bomb.toString('base64url')), /TOO_LARGE/);
    const badSize = Buffer.concat([Buffer.from([0,0,0,5]), zlib.deflateSync(Buffer.from('{}'))]);
    await assert.rejects(api.parse('vpn://' + badSize.toString('base64url')), /INVALID/);
    const conflict = share(); const config = JSON.parse(conflict.containers[0].awg.last_config); config.RandomTrailers=true;
    conflict.containers[0].awg.last_config=JSON.stringify(config);
    await assert.rejects(api.parse(link(conflict)), /CONFLICT/);
    // Export synthetic form values for the independent Ruby/YAML integration test.
    fs.mkdirSync('build', {recursive:true});
    fs.writeFileSync('build/awg-import-test-values.json', JSON.stringify({...r.fields, config:'test.yaml', groups:['^Main$'], enabled:'1'}));
    console.log('AWG file/link import: Qt compression, Unicode, IPv6, v3/legacy, zero/false, malformed/oversize input and subscription keys passed');
})().catch(error => { console.error(error); process.exit(1); });
