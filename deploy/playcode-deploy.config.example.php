<?php
// Settings for playcode-deploy.php. Save as playcode-deploy.config.php next to it.
// Opened in a browser, this file shows nothing.
return array(
    // The GitHub repository and branch Playcode's Deploy pushes to.
    'repo' => 'OWNER/REPO',
    'branch' => 'gh-pages',

    // The folder, next to playcode-deploy.php, the site goes in: https://emothe.uv.es/edicion_estatica/
    'target' => 'edicion_estatica',

    // The SHA-256 of the deploy token. The token itself goes to Playcode, never here:
    //   TOKEN=$(openssl rand -hex 32); echo "$TOKEN"; printf %s "$TOKEN" | sha256sum
    'token_sha256' => '',

    // Only for a private repository: a read-only token for it.
    'github_token' => '',
);
