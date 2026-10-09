/* Local Amnezia/WireGuard import. No network requests or executable config. */
(function(root) {
    'use strict';
    var LIMIT = 262144;
    var optionNames = ('Jc Jmin Jmax S1 S2 S3 S4 H1 H2 H3 H4 I1 I2 I3 I4 I5 J1 J2 J3 Itime ' +
        'HeaderProtectionKey ContentPaddingAddition RekeyAfterTime RekeyTimeout RejectAfterTime ' +
        'KeepaliveTimeout MaxHandshakeAttempts RandomTrailers DisableCookies').split(' ');
    var normalized = function(s) { return s.toLowerCase().replace(/[-_]/g, ''); };
    var fieldNames = {};
    optionNames.forEach(function(name) {
        fieldNames[normalized(name)] = 'awg_' + name.replace(/([a-z])([A-Z])/g, '$1_$2').toLowerCase();
    });
    function fail(code) { throw new Error(code); }
    function scalar(value) {
        if (!['string', 'number', 'boolean'].includes(typeof value)) fail('INVALID');
        var text = String(value);
        if (/[\x00-\x1f\x7f]/.test(text) || text.length > 8192) fail('INVALID');
        return text;
    }
    function integer(value, min, max) {
        value = scalar(value);
        if (!/^\d+$/.test(value) || Number(value) < min || Number(value) > max) fail('INVALID');
        return value;
    }
    function key(value) {
        value = scalar(value);
        if (!/^[A-Za-z0-9+/]{43}=$/.test(value) || atob(value).length !== 32) fail('INVALID');
        return value;
    }
    function ip(value) {
        if (/^\d+\.\d+\.\d+\.\d+$/.test(value)) return value.split('.').every(function(n) { return Number(n) <= 255; });
        if (!/^[\da-f:]+$/i.test(value) || value.indexOf(':') < 0) return false;
        try { return new URL('http://[' + value + ']/').hostname.length > 0; } catch (_) { return false; }
    }
    function cidr(value) {
        var parts = value.split('/');
        if (parts.length > 2 || !ip(parts[0])) fail('INVALID');
        if (parts.length === 2) integer(parts[1], 0, parts[0].includes(':') ? 128 : 32);
        return parts[0];
    }
    function list(value) { return scalar(value).split(',').map(function(v) { return v.trim(); }).filter(Boolean); }
    function range(value, max) {
        var parts = scalar(value).split('-');
        if (parts.length > 2) fail('INVALID');
        parts.forEach(function(p) { integer(p, 0, max); });
        if (parts.length === 2 && Number(parts[0]) > Number(parts[1])) fail('INVALID');
    }
    function parseConf(text, metadata) {
        metadata = metadata || {};
        if (text.length > LIMIT || text.includes('\0')) fail('TOO_LARGE');
        var sections = [], section;
        text.replace(/^\uFEFF/, '').split(/\r?\n/).forEach(function(line) {
            line = line.trim();
            if (!line || /^[#;]/.test(line)) return;
            var heading = line.match(/^\[(Interface|Peer)\]\s*(?:[#;].*)?$/i);
            if (heading) { section = {type: heading[1].toLowerCase(), values: Object.create(null)}; sections.push(section); return; }
            var setting = line.match(/^([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(.*?)\s*$/);
            if (!section || !setting) fail('INVALID');
            var name = normalized(setting[1]);
            if (Object.prototype.hasOwnProperty.call(section.values, name)) fail('DUPLICATE_FIELD');
            section.values[name] = scalar(setting[2].replace(/\s+[#;].*$/, ''));
        });
        var interfaces = sections.filter(function(s) { return s.type === 'interface'; });
        var peers = sections.filter(function(s) { return s.type === 'peer'; });
        if (peers.length > 1) fail('MULTIPLE_PEERS');
        if (interfaces.length !== 1 || peers.length !== 1) fail('INVALID');
        var a = interfaces[0].values, b = peers[0].values;
        var allowedA = ['privatekey', 'address', 'dns', 'mtu', 'listenport', 'table', 'saveconfig', 'protocolversion', 'version'];
        Object.keys(a).forEach(function(k) { if (!allowedA.includes(k) && !fieldNames[k]) fail('UNSUPPORTED_FIELD'); });
        Object.keys(b).forEach(function(k) { if (!['publickey', 'presharedkey', 'endpoint', 'allowedips', 'persistentkeepalive'].includes(k)) fail('UNSUPPORTED_FIELD'); });
        var endpoint = (b.endpoint || '').match(/^(?:\[([\da-f:]+)\]|([^\s:\[\]/?#]+)):(\d+)$/i);
        if (!endpoint || (endpoint[1] && !ip(endpoint[1]))) fail('INVALID');
        var fields = {type: 'wireguard', server: endpoint[1] || endpoint[2], port: integer(endpoint[3], 1, 65535),
            private_key: key(a.privatekey), public_key: key(b.publickey), preshared_key: b.presharedkey ? key(b.presharedkey) : '',
            wg_ip: '', wg_ipv6: '', wg_dns: '', wg_mtu: '', awg_enable: '0', awg_version: '2', awg_local: '1'};
        list(a.address).forEach(function(address) {
            var addressIp = cidr(address), field = addressIp.includes(':') ? 'wg_ipv6' : 'wg_ip';
            if (fields[field]) fail('MULTIPLE_ADDRESSES');
            fields[field] = addressIp;
        });
        if (!fields.wg_ip && !fields.wg_ipv6) fail('INVALID');
        if (a.dns) { var dns = list(a.dns); if (!dns.every(ip)) fail('INVALID'); fields.wg_dns = dns.join(','); }
        var mtu = a.mtu !== undefined ? a.mtu : metadata.mtu;
        if (mtu !== undefined && mtu !== '') fields.wg_mtu = integer(mtu, 576, 65535);
        Object.keys(fieldNames).forEach(function(k) { fields[fieldNames[k]] = ''; });
        Object.keys(a).forEach(function(k) {
            if (!fieldNames[k]) return;
            var value = a[k]; fields.awg_enable = '1';
            if (/^(jc|jmin|jmax|s[1-4]|itime)$/.test(k)) integer(value, 0, 65535);
            if (/^h[1-4]$/.test(k)) range(value, 4294967295);
            if (k === 'contentpaddingaddition') range(value, 65535);
            if (k === 'headerprotectionkey') key(value);
            if (/^(rekeyaftertime|rekeytimeout|rejectaftertime|keepalivetimeout|maxhandshakeattempts)$/.test(k)) integer(value, 0, 4294967295);
            if (k === 'randomtrailers' || k === 'disablecookies') {
                if (!/^(true|false|0|1)$/i.test(value)) fail('INVALID');
                value = /^(true|1)$/i.test(value) ? 'true' : 'false';
            }
            fields[fieldNames[k]] = value;
        });
        if (a.jmin !== undefined && a.jmax !== undefined && Number(a.jmin) > Number(a.jmax)) fail('INVALID');
        var version = a.protocolversion || a.version || metadata.version;
        var v3 = Object.keys(a).some(function(k) { return /^(headerprotectionkey|contentpaddingaddition|rekeyaftertime|rekeytimeout|rejectaftertime|keepalivetimeout|maxhandshakeattempts|randomtrailers|disablecookies)$/.test(k); });
        if (version !== undefined && version !== '') {
            version = scalar(version);
            if (!/^(1(?:\.[05])?|2(?:\.0)?|3(?:\.[01])?)$/.test(version)) fail('VERSION');
            fields.awg_version = version.startsWith('3') ? '3' : (version === '1' || version === '1.0' ? '1' : '2');
            if (v3 && fields.awg_version !== '3') fail('VERSION');
        } else if (v3) fields.awg_version = '3';
        // Without an explicit version and without v3-only fields, keep legacy mode.
        var extras = {};
        if (b.allowedips) { extras['allowed-ips'] = list(b.allowedips); extras['allowed-ips'].forEach(cidr); }
        if (b.persistentkeepalive !== undefined) extras['persistent-keepalive'] = Number(integer(b.persistentkeepalive, 0, 65535));
        extras['remote-dns-resolve'] = false;
        fields.other_parameters = Object.keys(extras).map(function(k) { return '    ' + k + ': ' + JSON.stringify(extras[k]); }).join('\n');
        fields.name = scalar(metadata.name || 'AmneziaWG');
        return {fields: fields, name: fields.name, endpoint: b.endpoint,
            warning: !version && fields.awg_enable === '1' && !v3 ? 'CHECK_VERSION' : ''};
    }
    function object(value) {
        if (typeof value === 'string') { try { value = JSON.parse(value); } catch (_) { fail('INVALID'); } }
        if (!value || typeof value !== 'object' || Array.isArray(value)) fail('INVALID');
        return value;
    }
    function fromJson(value, filename) {
        var data = object(value), result = [];
        if (data.configVersion || data.api_config || data.apiConfig) fail('SUBSCRIPTION');
        function add(protocol, parent, name) {
            var last = protocol.last_config !== undefined ? protocol.last_config : protocol;
            if (typeof last === 'string' && /^\s*\[Interface\]/i.test(last)) last = {config: last};
            last = object(last);
            if (typeof last.config !== 'string') return;
            var metadata = {name: name, version: last.protocol_version || protocol.protocol_version || parent.protocol_version,
                mtu: last.mtu};
            if (!metadata.version && /awg3/.test(parent.container || '')) metadata.version = '3';
            // Amnezia keeps some protocol fields beside the INI, especially MTU.
            // Fill absent INI options; reject conflicts instead of losing settings.
            var conf = last.config, extra = [];
            optionNames.forEach(function(keyName) {
                if (last[keyName] === undefined) return;
                var found = conf.match(new RegExp('^\\s*' + keyName + '\\s*=\\s*(.*)$', 'im'));
                var v = scalar(last[keyName]);
                if (!found) extra.push(keyName + ' = ' + v);
                else if (found[1].trim() !== v) fail('CONFLICT');
            });
            conf = conf.replace(/(^\s*\[Interface\][^\n]*\n)/im, function(heading) { return heading + extra.join('\n') + '\n'; });
            result.push(parseConf(conf, metadata));
        }
        if (Array.isArray(data.containers)) {
            if (data.containers.length > 32) fail('TOO_LARGE');
            data.containers.forEach(function(container) {
                container = object(container);
                Object.keys(container).filter(function(k) { return /^(awg\d*|amnezia-awg\d*|wireguard)$/.test(k); }).forEach(function(k) {
                    var protocol = object(container[k]);
                    add(protocol, container, (data.description || filename || 'AmneziaWG') + (data.containers.length > 1 ? ' · ' + (container.container || k) : ''));
                });
            });
        } else if (data.config || data.last_config) add(data, data, data.description || filename || 'AmneziaWG');
        if (!result.length) fail('NO_PROFILE');
        return result;
    }
    async function decodeLink(text) {
        var encoded = text.replace(/^vpn:\/\//i, '').trim();
        if (!/^[A-Za-z0-9_+/-]+={0,2}$/.test(encoded)) fail('INVALID');
        var bytes;
        try { bytes = Uint8Array.from(atob(encoded.replace(/-/g, '+').replace(/_/g, '/')), function(c) { return c.charCodeAt(0); }); }
        catch (_) { fail('INVALID'); }
        // Amnezia also accepts Base64 JSON without qCompress.
        if (bytes[0] === 123) return new TextDecoder('utf-8', {fatal:true}).decode(bytes);
        if (bytes.length < 6) fail('INVALID');
        var expected = new DataView(bytes.buffer).getUint32(0, false);
        if (expected > LIMIT) fail('TOO_LARGE');
        if (typeof DecompressionStream === 'undefined') fail('BROWSER');
        var reader = new Blob([bytes.subarray(4)]).stream().pipeThrough(new DecompressionStream('deflate')).getReader();
        var chunks = [], total = 0;
        try {
            while (true) {
                var item = await reader.read(); if (item.done) break;
                total += item.value.length;
                if (total > LIMIT || total > expected) { await reader.cancel(); fail('TOO_LARGE'); }
                chunks.push(item.value);
            }
        } catch (error) { if (error.message === 'TOO_LARGE') throw error; fail('INVALID'); }
        if (total !== expected) fail('INVALID');
        var decoded = new Uint8Array(total), offset = 0;
        chunks.forEach(function(chunk) { decoded.set(chunk, offset); offset += chunk.length; });
        return new TextDecoder('utf-8', {fatal:true}).decode(decoded);
    }
    async function parse(text, filename) {
        if (typeof text !== 'string' || text.length > LIMIT) fail('TOO_LARGE');
        text = text.replace(/^\uFEFF/, '').trim();
        if (/^vpn:\/\//i.test(text)) text = await decodeLink(text);
        if (/^\s*\{/.test(text)) return fromJson(text, filename);
        return [parseConf(text, {name: filename || 'AmneziaWG'})];
    }
    var api = {parse: parse, parseConf: parseConf, limit: LIMIT, fields: Object.values(fieldNames)};
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    else root.OpenClashAWGImport = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
