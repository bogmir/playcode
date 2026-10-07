#!/usr/bin/env bash
# Exercises playcode-deploy.php under PHP 7.2 with the zip and curl extensions, as on
# emothe.uv.es, against a mock of its folder holding WordPress and an older
# section that must survive every deploy. Needs docker and python3. Run: deploy/test.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
php_port=18080
zip_port=18099
container=playcode-deploy-test
# The PHP the server runs; PHP_IMAGE=wordpress:cli-php7.4 deploy/test.sh for another.
image=${PHP_IMAGE:-wordpress:cli-php7.2}

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  kill "$zip_server" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

site="$work/site"
zips="$work/zips"
mkdir -p "$site/biblioteca" "$zips"
echo '<?php // WordPress' > "$site/wp-config.php"
echo '<?php // WordPress' > "$site/index.php"
echo 'older section' > "$site/biblioteca/old.html"
cp "$here/playcode-deploy.php" "$site/"

token=s3cret
token_sha=$(printf %s "$token" | sha256sum | cut -d' ' -f1)

config() {
  cat > "$site/playcode-deploy.config.php" <<EOF
<?php
return array(
    'repo' => 'owner/repo', 'branch' => 'gh-pages', 'target' => '$1',
    'token_sha256' => '$token_sha', 'github_token' => '',
    'zip_url' => 'http://127.0.0.1:$zip_port/current.zip',
);
EOF
}

# The zips GitHub would serve: one top folder, the commit id as the archive comment.
python3 - "$zips" <<'EOF'
import sys, zipfile
out = sys.argv[1]
def make(name, files, comment=b""):
    with zipfile.ZipFile(f"{out}/{name}.zip", "w") as z:
        z.writestr("repo-gh-pages/", "")
        for path, body in files.items():
            z.writestr(path if path.startswith("../") else f"repo-gh-pages/{path}", body)
        z.comment = comment
make("v1", {"index.html": "v1", "plays/A/index.html": "A", "plays/B/index.html": "B"}, b"sha1")
make("v2", {"index.html": "v2", "plays/A/index.html": "A2"}, b"sha2")
make("php", {"index.html": "evil", "x.php": "<?php system($_GET[1]);"})
make("htaccess", {"index.html": "evil", "plays/.htaccess": "Options +ExecCGI"})
make("slip", {"index.html": "evil", "../escape.html": "out"})
make("noindex", {"readme.txt": "no index"})
EOF

(cd "$zips" && exec python3 -m http.server "$zip_port" --bind 127.0.0.1 >/dev/null 2>&1) &
zip_server=$!

docker run -d --name "$container" --network host --user "$(id -u):$(id -g)" \
  -v "$site:/site" --entrypoint php "$image" \
  -S "127.0.0.1:$php_port" -t /site >/dev/null

for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$php_port/" && break; sleep 0.1; done

failures=0
pass() { echo "ok    $1"; }
flunk() { echo "FAIL  $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else flunk "$1"; fi; }

# request METHOD TOKEN QUERY -> sets $status and $body
request() {
  status=$(curl -s -o "$work/body" -w '%{http_code}' -X "$1" -H "X-Deploy-Token: $2" \
    "http://127.0.0.1:$php_port/playcode-deploy.php$3")
  body=$(cat "$work/body")
}
serve() { cp "$zips/$1.zip" "$zips/current.zip"; }
untouched() {
  [ "$(cat "$site/wp-config.php")" = '<?php // WordPress' ] &&
    [ "$(cat "$site/biblioteca/old.html")" = 'older section' ]
}

config edicion
serve v1

request GET "$token" ""
check "a GET is refused" '[ "$status" = 405 ]'

request POST wrong ""
check "a wrong token is refused" '[ "$status" = 403 ] && [ ! -e "$site/edicion" ]'

request POST "$token" "?check=1"
check "the check reports zip, a writable folder and a reachable source" \
  '[ "$status" = 200 ] && grep -q "\"zip\": true" <<<"$body" &&
   grep -q "\"folder_writable\": true" <<<"$body" && grep -q "\"source_reachable\": true" <<<"$body"'
check "the check changes nothing" '[ ! -e "$site/edicion" ]'

request POST "$token" ""
check "a deploy puts the site in its folder and names the commit" \
  '[ "$status" = 200 ] && grep -q "sha1" <<<"$body" &&
   [ "$(cat "$site/edicion/index.html")" = v1 ] && [ -f "$site/edicion/plays/B/index.html" ]'
check "it marks the folder as its own" '[ -f "$site/edicion/.playcode-site" ]'
check "WordPress and the older section are untouched" 'untouched'

serve v2
request POST "$token" ""
check "a second deploy replaces the site and drops removed plays" \
  '[ "$status" = 200 ] && [ "$(cat "$site/edicion/index.html")" = v2 ] && [ ! -e "$site/edicion/plays/B" ]'

for bad in php htaccess slip noindex; do
  serve "$bad"
  request POST "$token" ""
  check "a $bad zip is refused and the site stays as it was" \
    '[ "$status" = 422 ] && [ "$(cat "$site/edicion/index.html")" = v2 ] && [ ! -e "$work/escape.html" ] && [ ! -e "$site/escape.html" ]'
done

check "no work files are left behind" \
  '[ ! -e "$site/edicion.new" ] && [ ! -e "$site/edicion.old" ] && [ ! -e "$site/edicion.zip" ]'

config biblioteca
serve v1
request POST "$token" ""
check "a folder it did not make is never replaced" '[ "$status" = 409 ] && untouched'

check "WordPress and the older section survived everything" 'untouched'

echo
if [ "$failures" = 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
