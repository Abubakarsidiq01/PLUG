# Bruno environments

`staging.bru` holds a cloudflared Quick Tunnel URL (see ADR-004), not a standing
staging host. It changes every time Person One restarts the tunnel. Before a joint
checkpoint, Person One sends the current URL, and you pass it on the command line
rather than editing the file:

```powershell
cd tests/api
& "../../tools/bruno/node_modules/.bin/bru.cmd" run auth --env staging --env-var "baseUrl=https://CURRENT-API-TUNNEL.trycloudflare.com"
```

Keep `.bru` environment files to the `vars { }` block only. Bruno CLI 4.1 refuses to
load an environment file that contains `#` comment lines.
