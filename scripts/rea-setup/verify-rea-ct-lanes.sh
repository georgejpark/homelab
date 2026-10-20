#!/bin/bash
# Functional check of REA's lanes inside CT 101 "rea". Run as george: ssh rea 'bash -s' < verify-rea-ct-lanes.sh
# Every input is a tiny self-made test file (or REA's own digest-pinned public Android fixture), so nothing untrusted runs.
set -uo pipefail
W="$HOME/e2e/lanes"; rm -rf "$W"; mkdir -p "$W"; cd "$W"
pass=0; fail=0
check() { # name, expected-substring, command...
  local name="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -eq 0 ] && grep -qF -- "$want" <<<"$out" && grep -q '"evidence_id"' <<<"$out"; then
    printf 'PASS  %-24s %s\n' "$name" "$(grep -o '"evidence_id":"ev_[0-9a-f]\{12\}' <<<"$out" | head -1 | cut -d'"' -f4)…"; pass=$((pass+1))
  else
    printf 'FAIL  %-24s rc=%s %s\n' "$name" "$rc" "$(tr '\n' ' ' <<<"$out" | cut -c1-220)"; fail=$((fail+1))
  fi
}

# Shared test inputs
printf '%s\n' '#include <stdio.h>' '#include <string.h>' \
  'static int checksum(const char *s){int h=7;while(*s)h=h*31+(unsigned char)*s++;return h;}' \
  'int verify_license(const char *k){return strlen(k)==8&&checksum(k)==0x5f3a91c2;}' \
  'int main(int c,char**v){puts(c>1&&verify_license(v[1])?"licensed":"trial");return 0;}' > hello.c
gcc -O1 -o hello hello.c

# 1. Ghidra native decompile
check ghidra-decompile 0x5f3a91c2 rea decompile "$W/hello" verify_license --provider ghidra --format json

# 2. ELF layout (pwntools 4.15.0)
check elf-layout verify_license rea inspect-binary-layout "$W/hello" --format json

# 3. Recorded crash: core of our own null-deref program, written by gdb's generate-core-file
printf '%s\n' 'int main(void){volatile int *p=0; return *p;}' > crasher.c && gcc -O0 -g -o crasher crasher.c
gdb -q -batch -ex run -ex "generate-core-file $W/crash.core" ./crasher >/dev/null 2>&1
check recorded-crash SIGSEGV rea inspect-recorded-crash "$W/crash.core" --format json

# 4. EVM: hand-assembled dispatcher for selector 0x6d4ce63c (get())
printf '%s' 60003560e01c80636d4ce63c14601457600080fd5b60005460005260206000f3 > get.hex
check evm-interface 6d4ce63c rea inspect-evm-interface "$W/get.hex" hex --format json

# 5. Firmware regions: padding + gzip stream + zip archive + ELF
head -c 4096 /dev/zero > fw.bin; gzip -c hello.c >> fw.bin; (zip -q - hello.c) >> fw.bin; cat hello >> fw.bin
check firmware-regions gzip rea inspect-firmware-regions "$W/fw.bin" --format json
missing=$("$REA_UNBLOB_COMMAND" --show-external-dependencies 2>&1 | grep -c '✗')
if [ "$missing" = 0 ]; then echo "PASS  unblob-extractors        all external extractors visible on this user's PATH"; pass=$((pass+1)); else echo "FAIL  unblob-extractors        $missing missing: $("$REA_UNBLOB_COMMAND" --show-external-dependencies 2>&1 | grep '✗' | awk '{print $1}' | tr '\n' ' ')"; fail=$((fail+1)); fi

# 6. pcap: one Ethernet/IPv4/UDP DNS query for rea.tools, written by Python
python3 - <<'EOF'
import struct
q = b'\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00' + b'\x03rea\x05tools\x00' + b'\x00\x01\x00\x01'
udp = struct.pack('!HHHH', 53000, 53, 8 + len(q), 0) + q
ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(udp), 1, 0, 64, 17, 0, bytes([10,10,0,109]), bytes([8,8,8,8])) + udp
eth = b'\x00\x11\x22\x33\x44\x55' + b'\x66\x77\x88\x99\xaa\xbb' + b'\x08\x00' + ip
with open('dns.pcap', 'wb') as f:
    f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
    f.write(struct.pack('<IIII', 1760000000, 0, len(eth), len(eth)) + eth)
EOF
check pcap-summary rea.tools rea inspect-pcap-capture "$W/dns.pcap" --format json
check packet-fields rea.tools rea inspect-packet-capture "$W/dns.pcap" --fields dns.qry.name --fields ip.dst --format json

# 7. Signals: decoder catalog + decode a sigrok demo-driver recording (synthetic, no hardware)
check signal-decoders uart rea inspect-signal-decoders --query uart --format json
sigrok-cli -d demo --samples 20000 -o "$W/demo.sr" >/dev/null 2>&1
check signal-decode decode rea decode-signal-recording "$W/demo.sr" --decoders "uart:rx=D0:baudrate=115200" --format json

# 8. WASM (WABT 1.0.42)
printf '%s\n' '(module (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))' > add.wat
"$REA_WABT_BIN_DIRECTORY/wat2wasm" add.wat -o add.wasm
check wasm-artifact '"add"' rea inspect-wasm-artifact "$W/add.wasm" --format json

# 9. mitmproxy capture: our own local HTTP server, fetched through mitmdump 12.2.3
python3 -c "import functools,http.server,socketserver; socketserver.TCPServer.allow_reuse_address=True; socketserver.TCPServer(('127.0.0.1',8765), functools.partial(http.server.SimpleHTTPRequestHandler, directory='.')).serve_forever()" >/dev/null 2>&1 & HTTP=$!  # TCPServer: no reverse-DNS stall
"$REA_MITMDUMP_COMMAND" -q --listen-host 127.0.0.1 -p 8766 -w "$W/flows.mitm" >/dev/null 2>&1 & MITM=$!
sleep 3; curl -s -o /dev/null -x http://127.0.0.1:8766 http://127.0.0.1:8765/add.wat; sleep 1
kill -INT $MITM; wait $MITM 2>/dev/null; kill $HTTP; wait $HTTP 2>/dev/null
check mitmproxy-capture add.wat rea inspect-web-network-capture "$W/flows.mitm" mitmproxy --format json

# 10. Android: REA's own digest-pinned public fixture (Appium ApiDemos 6.0.18) -> JADX + apktool
(cd /opt/rea && npm run --silent fixtures:android >/dev/null 2>&1)
APK=/opt/rea/_reference/apk-integration/ApiDemos-debug.apk
check android-package io.appium.android.apis rea inspect-android-package "$APK" --format json
check android-resources io.appium.android.apis rea decode-android-resources "$APK" --format json

# 11. Chromium headless as george (sandbox status decides whether REA_BROWSER_NO_SANDBOX is needed)
if chromium --headless=new --disable-gpu --dump-dom 'data:text/html,<p>sandbox-ok</p>' 2>/dev/null | grep -q sandbox-ok; then
  echo "PASS  chromium-sandboxed       headless Chromium works with its sandbox"; pass=$((pass+1))
elif chromium --headless=new --no-sandbox --disable-gpu --dump-dom 'data:text/html,<p>ok</p>' 2>/dev/null | grep -q ok; then
  echo "WARN  chromium-sandboxed       sandbox unavailable in this container; works with --no-sandbox (REA_BROWSER_NO_SANDBOX)"
else
  echo "FAIL  chromium                 headless Chromium does not start"; fail=$((fail+1))
fi

echo "---- $pass passed, $fail failed"
