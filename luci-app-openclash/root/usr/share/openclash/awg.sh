#!/bin/sh
# Serialize values as data through the environment; never interpolate Ruby code.
openclash_awg_export() (
    local section="$1" awg_key awg_value
    for awg_key in wg_extra_blob awg_enable awg_options_blob awg_version \
        awg_jc awg_jmin awg_jmax awg_s1 awg_s2 awg_s3 awg_s4 \
        awg_h1 awg_h2 awg_h3 awg_h4 awg_i1 awg_i2 awg_i3 awg_i4 awg_i5 \
        awg_j1 awg_j2 awg_j3 awg_itime awg_header_protection_key \
        awg_content_padding_addition awg_rekey_after_time awg_rekey_timeout \
        awg_reject_after_time awg_keepalive_timeout awg_max_handshake_attempts \
        awg_random_trailers awg_disable_cookies; do
        config_get awg_value "$section" "$awg_key" ""
        export "OPENCLASH_AWG_${awg_key}=$awg_value"
    done
    ruby -E UTF-8 /usr/share/openclash/awg.rb
)
