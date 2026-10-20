#!/bin/bash
# Functional check of REA's lanes on the Mac. Run: bash ~/Desktop/AI-Server/rea-setup/verify-rea-mac-lanes.sh
# Inputs are tiny self-made files, a built-in macOS app (read only), REA's digest-pinned public Android
# fixture, and a throwaway headless Chrome on a temporary profile (your real Chrome profile is untouched).
set -uo pipefail
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-$HOME/tools/ghidra_12.1.4_PUBLIC}"
export REA_WABT_BIN_DIRECTORY="${REA_WABT_BIN_DIRECTORY:-$HOME/tools/wabt-1.0.42/bin}"
export REA_JADX_MCP_JAR="${REA_JADX_MCP_JAR:-$HOME/tools/jadx-headless-mcp/jadx-headless-mcp-0.7.1-all.jar}"
W="$(mktemp -d)/lanes"; mkdir -p "$W"; cd "$W"
pass=0; fail=0
check() { # name, expected-substring, command...
  local name="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -eq 0 ] && grep -qF -- "$want" <<<"$out" && grep -q '"evidence_id"' <<<"$out"; then
    printf 'PASS  %-22s %s\n' "$name" "$(grep -o '"evidence_id":"ev_[0-9a-f]\{12\}' <<<"$out" | head -1 | cut -d'"' -f4)…"; pass=$((pass+1))
  else
    printf 'FAIL  %-22s rc=%s %s\n' "$name" "$rc" "$(tr '\n' ' ' <<<"$out" | cut -c1-220)"; fail=$((fail+1))
  fi
}

printf '%s\n' '#include <stdio.h>' '#include <string.h>' \
  'static int checksum(const char *s){int h=7;while(*s)h=h*31+(unsigned char)*s++;return h;}' \
  'int verify_license(const char *k){return strlen(k)==8&&checksum(k)==0x5f3a91c2;}' \
  'int main(int c,char**v){puts(c>1&&verify_license(v[1])?"licensed":"trial");return 0;}' > hello.c
clang -O1 -o hello hello.c

# 1. Ghidra native decompile (locally built mac_arm_64 decompiler)
check ghidra-decompile 0x5f3a91c2 rea decompile "$W/hello" _verify_license --provider ghidra --format json
# 2-4. Apple binaries and bundles (built-in parsers, read only)
check macho arm64 rea inspect-macho "$W/hello" --format json
check plist com.apple.calculator rea inspect-plist /System/Applications/Calculator.app --format json
check app-artifact Calculator rea inspect-artifact /System/Applications/Calculator.app --format json
# 5. SQLite snapshot (Node's built-in SQLite)
python3 -c "import sqlite3; c=sqlite3.connect('app.db'); c.execute('create table users(id integer primary key, name text)'); c.execute(\"insert into users(name) values ('alice'),('bob')\"); c.commit()"
check sqlite alice rea inspect-sqlite-database "$W/app.db" --table users --format json
# 6. JavaScript / Electron-style app tree (static, nothing executes)
mkdir -p jsapp && cd jsapp
printf '%s\n' '{"name":"demo-app","version":"1.0.0","main":"main.js"}' > package.json
printf '%s\n' "const { app, ipcMain } = require('electron');" "ipcMain.handle('notes:search', async (_e, q) => q.toLowerCase());" "app.whenReady();" > main.js
printf '%s\n' "const { contextBridge, ipcRenderer } = require('electron');" "contextBridge.exposeInMainWorld('notes', { search: (q) => ipcRenderer.invoke('notes:search', q) });" > preload.js
cd "$W"
check javascript-app notes:search rea analyze-javascript-application "$W/jsapp" --format json
# 7. WASM (WABT 1.0.42)
printf '%s\n' '(module (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))' > add.wat
"$REA_WABT_BIN_DIRECTORY/wat2wasm" add.wat -o add.wasm
check wasm-artifact '"add"' rea inspect-wasm-artifact "$W/add.wasm" --format json
# 8. Android APK via JADX (REA's digest-pinned Appium ApiDemos fixture)
(cd "$HOME/Desktop/AI-Server/rea" && npm run --silent fixtures:android >/dev/null 2>&1)
check android-package io.appium.android.apis rea inspect-android-package "$HOME/Desktop/AI-Server/rea/_reference/apk-integration/ApiDemos-debug.apk" --format json
# 9. Browser lane: throwaway headless Chrome on a temporary profile + loopback CDP
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  # REA lists only http(s) page targets, so serve the test page from a loopback HTTP server
  mkdir -p www && printf '%s\n' '<title>rea-lane-check</title><p>hello</p>' > www/index.html
  if lsof -nP -iTCP:8767 -iTCP:9333 -sTCP:LISTEN >/dev/null 2>&1; then echo "FAIL  browser-targets        test ports 8767/9333 already in use (leftover process?)"; fail=$((fail+1)); else
  # start python directly (no subshell) so $! is the server itself and kill really stops it
  # plain TCPServer: http.server's HTTPServer does a reverse-DNS lookup before listening, which hangs ~35 s when the LAN DNS is slow
  python3 -c "import functools,http.server,socketserver; socketserver.TCPServer.allow_reuse_address=True; socketserver.TCPServer(('127.0.0.1',8767), functools.partial(http.server.SimpleHTTPRequestHandler, directory='www')).serve_forever()" >/dev/null 2>&1 & HTTP=$!
  for i in $(seq 1 50); do curl -s -m 1 -o /dev/null http://127.0.0.1:8767/ && break; sleep 0.2; done
  trap 'kill $HTTP ${CH:-} 2>/dev/null' EXIT
  "$CHROME" --headless=new --remote-debugging-port=9333 --user-data-dir="$W/chrome-profile" --no-first-run http://127.0.0.1:8767/ >/dev/null 2>&1 & CH=$!
  sleep 4
  out="$(rea list-browser-targets http://127.0.0.1:9333 --format json 2>&1)"
  if grep -q 'rea-lane-check' <<<"$out"; then echo "PASS  browser-targets        headless Chrome page visible over CDP"; pass=$((pass+1)); else echo "FAIL  browser-targets        $(tr '\n' ' ' <<<"$out" | cut -c1-200)"; fail=$((fail+1)); fi
  kill $CH $HTTP 2>/dev/null; wait $CH $HTTP 2>/dev/null
  fi
fi
rm -rf "$(dirname "$W")"
echo "---- $pass passed, $fail failed"
