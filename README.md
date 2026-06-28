# Jekyll Static Site Builder

#jekyll-ssb

A throwaway Jekyll image built on `ubuntu:latest`. Build it once, then mount whatever
site you're working on and it figures out the gems for you. There's no Gemfile baked
into the image, so the same build works for every project on your machine.

```sh
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll" <build-tag>
```

That's the whole idea: point it at a directory containing a Jekyll site and it serves
the site at <http://localhost:4000>.

## Why gems install at runtime

The entrypoint runs `bundle install` when the container starts, not when the image is
built. The upside is one image for all your sites. The downside is the image has to ship
a C toolchain (`gcc`, `make`, Ruby headers) so native extensions like `sassc`,
`eventmachine`, and `bigdecimal` can compile on first run.

If you care about a hardened, compiler-free runtime — for CI or anything that touches
production — this is the wrong image. Build per-site with the Gemfile present at build
time so gems are baked in and the toolchain can be dropped. The Dockerfile comments
point at that variant; ask if you want it.

## Building

```sh
docker build -t <build-tag> .
```

Optional build args:

| Arg | Default | Notes |
| --- | --- | --- |
| `JEKYLL_VERSION` | `4.4.1` | Fallback Jekyll used when the mounted site has no Gemfile |
| `APP_UID` / `APP_GID` | `10001` | UID/GID of the non-root `jekyll` user |
| `BUILD_DATE` / `VCS_REF` | — | Stamped into OCI image labels if you pass them |

`latest` is a moving target. For anything you need to reproduce later, pin a digest:

```sh
docker buildx imagetools inspect ubuntu:latest   # grab the sha256
# then in the Dockerfile:
# FROM ubuntu:latest@sha256:<digest>
```

## Running

The default `CMD` just forwards arguments to `jekyll serve`, so you can override them
on the command line:

```sh
# default host/port
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll" <build-tag>

# turn on live reload
docker run --rm -p 4000:4000 -p 35729:35729 \
  -v "$PWD:/srv/jekyll" <build-tag> --livereload

# drafts + incremental builds
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll" <build-tag> --drafts --incremental
```

Port 4000 is the site. Port 35729 is LiveReload — only needs publishing if you pass
`--livereload`.

### Where gems land

Bundler vendors gems to `/srv/jekyll/vendor/bundle`, which is inside your mounted
directory. Two consequences worth knowing:

- They survive container restarts, so you only pay the compile cost once per site.
- A `vendor/` folder shows up in your project. Add it to `.gitignore` and to
  `exclude:` in `_config.yml` so Jekyll doesn't try to build it.

## How it's put together

A few decisions baked into the Dockerfile, in case you're auditing it:

- Runs as an unprivileged user (`10001:10001`), not root.
- `tini` is PID 1 to forward signals and reap zombies; it hands off to the entrypoint.
- Unused language runtimes (Python, Node, Lua, Tcl, Go, Mono) are purged. Perl stays
  because git depends on it. Ruby stays for obvious reasons.
- setuid/setgid bits are stripped from every file to cut down the privilege-escalation
  surface.
- `HOME` and the Bundler config live on writable tmpfs, so the image works with a
  read-only root filesystem:

  ```sh
  docker run --rm --read-only -p 4000:4000 -v "$PWD:/srv/jekyll" <build-tag>
  ```

## Requirements

You need `docker-entrypoint.sh` in the build context next to the Dockerfile — it's what
runs the lock + install before serving. The build will fail at the `COPY` step without
it.

## License

MIT.
