#!/usr/bin/env bash
# Entrypoint for the Jekyll dev image.
# If a Gemfile is present in the mounted site, lock + install its gems at
# RUNTIME (no committed Gemfile.lock required), then `bundle exec jekyll serve`.
# All arguments (e.g. --host / --port) are forwarded to `jekyll serve`.
set -euo pipefail

if [[ -f "Gemfile" ]]; then
  if bundle check >/dev/null 2>&1; then
    echo "[entrypoint] gems already installed (vendored) — skipping install"
  else
    echo "[entrypoint] Gemfile found — locking + installing gems at runtime"
    echo "[entrypoint]   BUNDLE_PATH=${BUNDLE_PATH:-<bundler default>}"
    # `bundle lock` generates the lockfile if absent (and records the Linux
    # platforms); `bundle install` then installs and compiles the gems. Neither
    # requires a pre-existing, committed Gemfile.lock.
    bundle lock --add-platform x86_64-linux aarch64-linux || true
    bundle install --retry=3
  fi
  echo "[entrypoint] starting: bundle exec jekyll serve $*"
  exec bundle exec jekyll serve "$@"
else
  echo "[entrypoint] no Gemfile in /srv/jekyll — using the Jekyll bundled in the image"
  echo "[entrypoint] starting: jekyll serve $*"
  exec jekyll serve "$@"
fi
