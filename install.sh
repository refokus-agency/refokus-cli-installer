#!/bin/bash
# Refokus installer: gets a macOS laptop ready for the refokus CLI.
#
#   curl -fsSL https://raw.githubusercontent.com/refokus-agency/refokus-cli-installer/main/install.sh | bash
#
# 1. Installs the GitHub CLI (gh) into ~/.refokus/bin when it is missing or
#    older than MIN_GH_VERSION.
# 2. Logs gh in to github.com with the `repo` and `workflow` scopes.
# 3. Downloads the refokus binary from the latest refokus-cli release with
#    the user's own gh login (the repo is private) into ~/.refokus/bin.
# 4. Adds ~/.refokus/bin to PATH in ~/.zprofile, once.
# 5. Runs `refokus setup`.
#
# Every step is skipped when already done, so running it again is safe.
# This script holds no token and reads none: gh keeps the login.
#
# Written for /bin/bash 3.2, the version macOS ships.

set -euo pipefail

readonly MIN_GH_VERSION="2.87.0"
readonly CLI_REPO="refokus-agency/refokus-cli"
readonly BIN_DIR="$HOME/.refokus/bin"
readonly PROFILE="$HOME/.zprofile"
readonly PATH_MARKER="# Added by the Refokus installer"
# shellcheck disable=SC2016 # Written to ~/.zprofile as is, expanded there.
readonly PATH_LINE='export PATH="$HOME/.refokus/bin:$PATH"'

WORK_DIR=""

say() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

# Prints the gh and refokus architecture names for this Mac, separated by a space.
detect_arch() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This installer supports macOS only."
  local machine
  machine="$(uname -m)"
  # A shell running under Rosetta on Apple Silicon reports x86_64.
  if [[ "$machine" == "x86_64" && "$(sysctl -in sysctl.proc_translated)" == "1" ]]; then
    machine="arm64"
  fi
  case "$machine" in
    arm64) echo "arm64 arm64" ;;
    x86_64) echo "amd64 x64" ;;
    *) fail "Unsupported Mac architecture: $machine." ;;
  esac
}

# True when version $1 is at least version $2. Both are MAJOR.MINOR.PATCH;
# a suffix such as -rc.1 on $1 is ignored.
version_at_least() {
  local found minimum i f m
  IFS=. read -r -a found <<<"${1%%-*}"
  IFS=. read -r -a minimum <<<"$2"
  for i in 0 1 2; do
    f="${found[i]:-0}"
    m="${minimum[i]:-0}"
    [[ "$f" =~ ^[0-9]+$ ]] || return 1
    if ((10#$f > 10#$m)); then return 0; fi
    if ((10#$f < 10#$m)); then return 1; fi
  done
  return 0
}

# Prints the version of the gh on PATH, or nothing when there is none.
gh_version() {
  if command -v gh >/dev/null 2>&1; then
    gh --version 2>/dev/null | sed -n 's/^gh version \([^ ]*\).*/\1/p' || true
  fi
}

install_gh() {
  local arch="$1" tag version name
  # The public cli/cli release needs no login; the redirect names the latest tag.
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)"
  tag="${tag##*/}"
  version="${tag#v}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Could not find the latest GitHub CLI release (got \"$tag\")."
  name="gh_${version}_macOS_${arch}"

  say "Installing the GitHub CLI $version into $BIN_DIR"
  local base="https://github.com/cli/cli/releases/download/$tag"
  curl -fsSL -o "$WORK_DIR/$name.zip" "$base/$name.zip"
  curl -fsSL -o "$WORK_DIR/checksums.txt" "$base/gh_${version}_checksums.txt"
  grep " $name.zip\$" "$WORK_DIR/checksums.txt" >"$WORK_DIR/expected.txt" ||
    fail "The GitHub CLI release has no checksum for $name.zip."
  (cd "$WORK_DIR" && shasum -a 256 -c expected.txt >/dev/null) ||
    fail "The downloaded GitHub CLI does not match its published checksum."
  unzip -q "$WORK_DIR/$name.zip" -d "$WORK_DIR"
  mv -f "$WORK_DIR/$name/bin/gh" "$BIN_DIR/gh"
}

ensure_gh() {
  local arch="$1" found
  found="$(gh_version)"
  if [[ -n "$found" ]] && version_at_least "$found" "$MIN_GH_VERSION"; then
    say "Using the GitHub CLI $found at $(command -v gh)"
    return
  fi
  if [[ -n "$found" ]]; then
    say "The GitHub CLI at $(command -v gh) is $found; refokus needs $MIN_GH_VERSION or newer."
  fi
  install_gh "$arch"
  hash -r
  found="$(gh_version)"
  if [[ -z "$found" ]] || ! version_at_least "$found" "$MIN_GH_VERSION"; then
    fail "The GitHub CLI in $BIN_DIR did not report version $MIN_GH_VERSION or newer."
  fi
}

# gh asks questions on the terminal; under `curl | bash` stdin is the script.
require_terminal() {
  { : </dev/tty; } 2>/dev/null ||
    fail "Run this installer from a Terminal window: logging in to GitHub needs your input."
}

ensure_gh_login() {
  local status scopes
  if ! status="$(gh auth status --active --hostname github.com 2>&1)"; then
    require_terminal
    say "Logging in to GitHub. Follow the steps gh shows."
    gh auth login --hostname github.com --git-protocol https --web --scopes workflow </dev/tty
    return
  fi
  scopes="$(printf '%s\n' "$status" | sed -n 's/.*Token scopes:\(.*\)/\1/p')"
  if [[ "$scopes" == *"'repo'"* && "$scopes" == *"'workflow'"* ]]; then
    say "Already logged in to GitHub with the repo and workflow scopes"
    return
  fi
  require_terminal
  say "Adding the repo and workflow scopes to your GitHub login. Follow the steps gh shows."
  gh auth refresh --hostname github.com --scopes repo,workflow </dev/tty
}

ensure_refokus() {
  local arch="$1" asset="refokus-darwin-$1"
  if [[ -x "$BIN_DIR/refokus" ]]; then
    say "refokus is already installed at $BIN_DIR/refokus (run \`refokus update\` to update it)"
    return
  fi
  say "Downloading refokus from the latest $CLI_REPO release"
  gh release download --repo "$CLI_REPO" --pattern "$asset" --dir "$WORK_DIR" ||
    fail "Could not download $asset from $CLI_REPO. Check that your GitHub account (\`gh auth status\`) can see that repository."
  chmod 755 "$WORK_DIR/$asset"
  mv -f "$WORK_DIR/$asset" "$BIN_DIR/refokus"
}

ensure_path_in_profile() {
  if [[ -f "$PROFILE" ]] && grep -qF "$PATH_MARKER" "$PROFILE"; then
    return
  fi
  say "Adding $BIN_DIR to PATH in $PROFILE"
  printf '\n%s\n%s\n' "$PATH_MARKER" "$PATH_LINE" >>"$PROFILE"
}

main() {
  local arches gh_arch refokus_arch
  arches="$(detect_arch)"
  gh_arch="${arches% *}"
  refokus_arch="${arches#* }"

  # Use the login gh stores, never a token from the environment.
  unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN

  mkdir -p "$BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) export PATH="$BIN_DIR:$PATH" ;;
  esac
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/refokus-install.XXXXXX")"
  trap cleanup EXIT

  ensure_gh "$gh_arch"
  ensure_gh_login
  ensure_refokus "$refokus_arch"
  ensure_path_in_profile

  cleanup
  trap - EXIT
  say "Running refokus setup. Open a new Terminal window afterwards to use \`refokus\`."
  exec "$BIN_DIR/refokus" setup
}

# Everything above only defines functions, so bash has read the whole script
# before anything runs, even when it arrives through a pipe.
main "$@"
