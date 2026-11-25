# refokus-cli-installer

Gets a Mac ready to use the Refokus CLI (`refokus`). Open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/refokus-agency/refokus-cli-installer/main/install.sh | bash
```

You need a GitHub account that belongs to the `refokus-agency` organization.
The installer opens your browser once to log you in to GitHub.

## What it does

[`install.sh`](install.sh) runs these steps, and skips each one that is
already done, so running it again is safe:

1. Checks that the machine is a Mac (Apple Silicon or Intel).
2. Installs the GitHub CLI (`gh`) into `~/.refokus/bin` when it is missing or
   older than 2.87.0. It downloads the public release from
   [cli/cli](https://github.com/cli/cli/releases) and checks it against the
   release's published checksums. A newer `gh` you already have is reused.
3. Logs `gh` in to github.com with the `repo` and `workflow` scopes
   (`gh auth login --web`), or adds the missing scopes to an existing login
   (`gh auth refresh`).
4. Downloads the `refokus` binary for your Mac from the latest
   [refokus-cli](https://github.com/refokus-agency/refokus-cli) release into
   `~/.refokus/bin/refokus`. That repository is private, so the download uses
   your own `gh` login.
5. Adds `~/.refokus/bin` to your `PATH` in `~/.zprofile`, once, under the
   comment `# Added by the Refokus installer`.
6. Runs `refokus setup`.

Open a new Terminal window afterwards so `refokus` is on your `PATH`. Update
the CLI later with `refokus update`.

## What goes where

| Path                     | What                                             |
| ------------------------ | ------------------------------------------------ |
| `~/.refokus/bin/refokus` | The Refokus CLI                                  |
| `~/.refokus/bin/gh`      | The GitHub CLI, only when the installer added it |
| `~/.zprofile`            | Two lines that put `~/.refokus/bin` on `PATH`    |

Your GitHub login is stored by `gh` (in the macOS keychain), never by this
script. The script holds no token and ignores `GH_TOKEN` and `GITHUB_TOKEN`.

## Uninstall

1. Delete the binaries: `rm -rf ~/.refokus/bin`
2. Remove the two lines under `# Added by the Refokus installer` from
   `~/.zprofile`.
3. Optional: log `gh` out with `gh auth logout --hostname github.com`.

`refokus setup` also clones the Refokus Home repository into `~/Refokus` and
installs its Claude Code plugins there. Delete `~/Refokus` to remove them.

## Development

CI runs `shellcheck` on `install.sh` and `secretlint` on every file. Run
`shellcheck install.sh` locally before you push. `install.sh` targets
`/bin/bash` 3.2, the version macOS ships.
