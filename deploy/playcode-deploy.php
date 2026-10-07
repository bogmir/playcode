<?php
/*
 * Playcode's deploy endpoint on emothe.uv.es.
 *
 * Playcode's Deploy pushes the static site to a GitHub branch, then POSTs here. This
 * script downloads that branch as a zip and swaps it, whole, into one folder next to it
 * (`target` in the config). It writes nothing outside that folder, and never replaces a
 * folder it did not make: it leaves a `.playcode-site` marker in the ones it does.
 *
 *   POST /playcode-deploy.php          header X-Deploy-Token: <token>   deploys
 *   POST /playcode-deploy.php?check=1  same header                      reports the
 *                                                                       prerequisites, changes nothing
 *
 * Install: put this file and playcode-deploy.config.php (made from the .example) side
 * by side in the site's folder, fill in the config, then run the check.
 * Written for PHP 7.2 and later. Tested by deploy/test.sh.
 */

header('Content-Type: application/json');
@set_time_limit(300);
// A deploy keeps going if Playcode stops waiting for the answer.
ignore_user_abort(true);

$config = require __DIR__ . '/playcode-deploy.config.php';
$marker = '.playcode-site';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    fail(405, 'POST only');
}
if (!preg_match('/^[0-9a-f]{64}$/', $config['token_sha256'])) {
    fail(500, 'token_sha256 is not set in the config');
}
// Not Authorization: Apache drops that header before PHP sees it on many servers.
$token = isset($_SERVER['HTTP_X_DEPLOY_TOKEN']) ? $_SERVER['HTTP_X_DEPLOY_TOKEN'] : '';
if (!hash_equals($config['token_sha256'], hash('sha256', $token))) {
    fail(403, 'wrong token');
}
if (!preg_match('/^[A-Za-z0-9_-]+$/', $config['target'])) {
    fail(500, 'target must be a plain folder name');
}

$target = __DIR__ . '/' . $config['target'];
$url = source_url($config);

if (isset($_GET['check'])) {
    reply(200, array(
        'ok' => true,
        'php' => PHP_VERSION,
        'zip' => class_exists('ZipArchive'),
        'download' => function_exists('curl_init') ? 'curl' : (ini_get('allow_url_fopen') ? 'allow_url_fopen' : false),
        'folder_writable' => is_writable(__DIR__),
        'target' => $config['target'],
        'target_replaceable' => replaceable($target, $marker),
        'source' => $url,
        'source_reachable' => reachable($url, $config),
    ));
}

$lock = fopen(__DIR__ . '/.playcode-deploy.lock', 'c');
if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) {
    fail(409, 'a deploy is already running');
}
if (!replaceable($target, $marker)) {
    fail(409, $config['target'] . ' exists and was not made by this script; refusing to replace it');
}
if (!class_exists('ZipArchive')) {
    fail(500, 'the PHP zip extension is missing');
}

$new = $target . '.new';
$old = $target . '.old';
$zip_file = $target . '.zip';

// Leftovers of a deploy cut short.
remove($new);
remove($old);
remove($zip_file);

download($url, $zip_file, $config);

$zip = new ZipArchive();
if ($zip->open($zip_file) !== true) {
    remove($zip_file);
    fail(502, 'the download is not a zip');
}
for ($i = 0; $i < $zip->numFiles; $i++) {
    $name = $zip->getNameIndex($i);
    if (!allowed($name)) {
        $zip->close();
        remove($zip_file);
        fail(422, 'refused: the site contains ' . $name);
    }
}
// GitHub writes the commit's id as the archive's comment.
$commit = $zip->getArchiveComment();
$unpacked = mkdir($new) && $zip->extractTo($new);
$zip->close();
remove($zip_file);
if (!$unpacked) {
    remove($new);
    fail(500, 'could not unpack the site');
}

// GitHub's zip holds the branch in one top folder.
$top = array_values(array_diff(scandir($new), array('.', '..')));
if (count($top) !== 1 || !is_file($new . '/' . $top[0] . '/index.html')) {
    remove($new);
    fail(422, 'the branch has no index.html at its root');
}
$site = $new . '/' . $top[0];
touch($site . '/' . $marker);

// Two renames on one disk: visitors get the old site or the new one, never a mix.
if (file_exists($target) && !rename($target, $old)) {
    remove($new);
    fail(500, 'could not move the current site aside');
}
if (!rename($site, $target)) {
    if (file_exists($old)) {
        rename($old, $target);
    }
    remove($new);
    fail(500, 'could not move the new site in');
}
remove($new);
remove($old);

reply(200, array('ok' => true, 'target' => $config['target'], 'commit' => $commit ? $commit : null));


function reply($status, array $body)
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT), "\n";
    exit;
}

function fail($status, $error)
{
    reply($status, array('ok' => false, 'error' => $error));
}

// The folder may be replaced when it does not exist, is empty, or carries the marker.
function replaceable($dir, $marker)
{
    if (!file_exists($dir)) {
        return true;
    }
    if (!is_dir($dir) || is_link($dir)) {
        return false;
    }
    return file_exists($dir . '/' . $marker) || count(scandir($dir)) === 2;
}

// Only what a static site is made of: no path leaving the folder, and nothing the web
// server would run or obey (PHP and its kin, .htaccess, .user.ini).
function allowed($name)
{
    if ($name === '' || $name[0] === '/' || $name[0] === '\\' || strpos($name, '..') !== false || strpos($name, ':') !== false) {
        return false;
    }
    return !preg_match('#(^|/)(\.ht[^/]*|\.user\.ini|[^/]*\.(php[0-9]?|phtml|phar|pht|phps|cgi|pl|py|sh|shtml|asp|aspx|jsp))$#i', $name);
}

function source_url(array $config)
{
    // Any zip with the same layout instead of GitHub; deploy/test.sh uses it.
    if (!empty($config['zip_url'])) {
        return $config['zip_url'];
    }
    if (!preg_match('#^[\w.-]+/[\w.-]+$#', $config['repo']) || !preg_match('#^[\w./-]+$#', $config['branch'])) {
        fail(500, 'repo must be owner/name, and branch a branch name');
    }
    // A private repository is read through the API, with the token; a public one directly.
    return empty($config['github_token'])
        ? 'https://codeload.github.com/' . $config['repo'] . '/zip/refs/heads/' . $config['branch']
        : 'https://api.github.com/repos/' . $config['repo'] . '/zipball/' . $config['branch'];
}

function request_headers(array $config)
{
    $headers = array('User-Agent: playcode-deploy');
    if (!empty($config['github_token'])) {
        $headers[] = 'Authorization: Bearer ' . $config['github_token'];
    }
    return $headers;
}

function download($url, $dest, array $config)
{
    if (function_exists('curl_init')) {
        $file = fopen($dest, 'wb');
        $curl = curl_init($url);
        curl_setopt_array($curl, array(
            CURLOPT_FILE => $file,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_FAILONERROR => true,
            CURLOPT_HTTPHEADER => request_headers($config),
            CURLOPT_CONNECTTIMEOUT => 20,
            CURLOPT_TIMEOUT => 240,
        ));
        $done = curl_exec($curl);
        $error = curl_error($curl);
        curl_close($curl);
        fclose($file);
        if (!$done) {
            remove($dest);
            fail(502, 'download failed: ' . $error);
        }
        return;
    }
    if (!ini_get('allow_url_fopen')) {
        fail(500, 'needs the PHP curl extension, or allow_url_fopen');
    }
    $context = stream_context_create(array('http' => array(
        'header' => implode("\r\n", request_headers($config)),
        'timeout' => 240,
    )));
    if (!@copy($url, $dest, $context)) {
        remove($dest);
        fail(502, 'download failed');
    }
}

// true, or why not. Only curl can tell without downloading the whole site.
function reachable($url, array $config)
{
    if (!function_exists('curl_init')) {
        return null;
    }
    $curl = curl_init($url);
    curl_setopt_array($curl, array(
        CURLOPT_NOBODY => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_FAILONERROR => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => request_headers($config),
        CURLOPT_CONNECTTIMEOUT => 20,
        CURLOPT_TIMEOUT => 30,
    ));
    $ok = curl_exec($curl) !== false;
    $error = curl_error($curl);
    curl_close($curl);
    return $ok ? true : $error;
}

// A file, or a folder with everything in it. Only ever given the target's own
// .new, .old and .zip.
function remove($path)
{
    if (is_link($path) || is_file($path)) {
        unlink($path);
        return;
    }
    if (!is_dir($path)) {
        return;
    }
    $items = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );
    foreach ($items as $item) {
        if ($item->isDir() && !$item->isLink()) {
            rmdir($item->getPathname());
        } else {
            unlink($item->getPathname());
        }
    }
    rmdir($path);
}
