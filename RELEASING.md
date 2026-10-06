# Releasing Comcent CE

New installs (`install.sh`) get the **latest GitHub Release**. Merging to
`main` doesn't change what they get; releasing does. A release is always
made by hand, after a person has tested a fresh install of exactly what is
being released. **Nothing here runs automatically, and no test server is ever
created or left running by CI.**

## What CI does on its own

- Every PR to `main` runs the unit tests and the integration tests.
- Every push to `main` runs them again. When both pass, **Publish images**
  pushes that commit's images as `ghcr.io/comcent-io/comcent-ce-{server,webapp,sbc}`
  with the tags `:main` and `:sha-<7 chars>`. It never touches `:latest` or
  version tags.

So a commit has published images only if its tests passed.

## Release checklist

1. **Pick the commit.** Usually current `main`. On the Actions tab, check that
   *Unit test*, *Integration tests* and *Publish images* all passed for it.
   Note its short sha, e.g. `1a2b3c4`.

2. **Test a fresh install of it** on a throwaway Ubuntu server (a small cloud
   VM with a public IP, ports 80/443, 5060, 5063 and 19000-19100 open, and a
   DNS name pointing at it). Use the README's command, pinned to the commit:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/comcent-io/comcent-ce/main/install.sh \
     | COMCENT_VERSION=sha-1a2b3c4 bash
   ```

   Then fill in `.env`, `docker compose up -d`, and check:
   - the HTTPS certificate is issued and the site loads;
   - first-run setup: the token from `docker compose logs server | grep -A 10 "FIRST-RUN SETUP"`
     creates the admin account at `/setup`;
   - log in, create an organization, and the browser dialer registers;
   - a call through a SIP trunk rings the browser, with audio both ways, and
     its call story (with recording) appears.

3. **Destroy the server.** Don't leave it running.

4. **Release.** Actions → **Release** → *Run workflow*, with:
   - `version`: `vYYYY.MM.DD` for today (add `.1`, `.2` for another release
     the same day);
   - `sha`: the commit you tested (blank means current `main`, so fill it in if
     `main` has moved since).

   It checks the commit's images exist, tags them `:<version>` and `:latest`,
   tags the commit and creates the GitHub Release with generated notes. From
   then on `install.sh` installs that version.

## Not covered yet

FreeSWITCH (`freeswitch-ce`) and the voice bot (`go-voice-bot-ce`) are built
in their own repositories and still installed as `:latest`.
