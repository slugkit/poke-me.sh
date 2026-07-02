# poke-me.sh

A tiny, dependency-light CLI for sending push notifications through the
[poke-me](https://push-me.io) API with a **publish key**.

One shell script, `curl` + `jq`. No install step.

## Install

Grab the script and make it executable:

```sh
curl -fsSL https://raw.githubusercontent.com/slugkit/poke-me.sh/main/poke-me.sh -o poke-me.sh
chmod +x poke-me.sh
```

Or add it to a project as a git submodule:

```sh
git submodule add https://github.com/slugkit/poke-me.sh.git cli
./cli/poke-me.sh --help
```

Requires `curl` and `jq`.

## Usage

Set your publish key once (a secret `pk_…` key — keep it off the client):

```sh
export POKEME_API_KEY=pk_live_...
```

**Channel broadcast** — `POST /api/v1/publish`:

```sh
poke-me.sh --channel acme/news --title "Deploy done" --body "v1.4.2 is live"
```

**BYOA subject unicast** — `POST /api/v1/apps/{app}/notify`:

```sh
poke-me.sh --app lazy-sudoku --user rc-user-42 \
  --title "Re: your feedback" --body "Fixed in 1.4.2 — thanks!"
```

### Options

```
TARGET (exactly one)
  -c, --channel REF     channel slug or uuid
      --app APP         app slug or uuid          (with --user)
  -u, --user ID         external user id          (with --app)

MESSAGE
  -t, --title TEXT      required unless --silent
  -b, --body TEXT       required unless --silent
  -p, --priority LEVEL  low | normal | high | critical   (default: normal)
      --url URL         tap-action URL
      --extras JSON     a JSON object, e.g. '{"screen":"inbox"}'
      --silent          content-available push (no title/body shown)

AUTH & ENDPOINT
  -k, --key KEY         publish key (pk_…).   Default: $POKEME_API_KEY
      --base-url URL    API base.             Default: $POKEME_BASE_URL
                                              or https://push-me.io

OTHER
  -n, --dry-run         print the request and exit without sending
  -v, --verbose         print request/response details
  -h, --help  / --version
```

### Examples

```sh
# high-priority alert with a deep link and custom data
poke-me.sh -c ops/alerts -t "Disk 90%" -b "web-3 root fs" \
  -p high --url https://status.example.com --extras '{"host":"web-3"}'

# see the exact request without sending it
poke-me.sh -c acme/news -t hi -b there --dry-run

# point at staging
poke-me.sh --base-url https://dev.push-me.io -c test -t hi -b there
```

On success it prints `sent · id=… · sent_at=…` (and `· devices=N` for unicast).
On failure it prints the API error and exits non-zero.

## Environment

| Variable | Purpose |
|---|---|
| `POKEME_API_KEY` | Publish key (`pk_…`). Overridden by `--key`. |
| `POKEME_BASE_URL` | API base URL. Overridden by `--base-url`. Default `https://push-me.io`. |

## Licence

Apache 2.0 — see [LICENSE](LICENSE).
