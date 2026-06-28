# syntax=docker/dockerfile:1.7

# =============================================================================
# Jekyll dev image on ubuntu:latest
# -----------------------------------------------------------------------------
# This image installs the MOUNTED site's gems at RUNTIME (via the entrypoint),
# so NO Gemfile is needed in the build context. Build it once, then mount any
# Jekyll site:   docker run -p 4000:4000 -v "$PWD:/srv/jekyll" <image>
#
# TRADE-OFF (read this): because gems are installed at container start, the
# image must keep a C toolchain (gcc/make + Ruby headers) so native extensions
# (bigdecimal, json, eventmachine, sassc, ...) can compile. That is LESS
# hardened than baking gems at build time. If you want a compiler-free runtime,
# build the image per-site with the Gemfile present at build time instead —
# ask and I'll provide that variant.
# =============================================================================
# Reproducibility: `latest` is mutable. For production pin a digest:
#   docker buildx imagetools inspect ubuntu:latest   # copy the sha256
#   FROM ubuntu:latest@sha256:<digest>
# =============================================================================
FROM ubuntu:latest

ARG BUILD_DATE
ARG VCS_REF
ARG JEKYLL_VERSION=4.4.1
LABEL org.opencontainers.image.title="jekyll-dev" \
      org.opencontainers.image.description="Ubuntu + Jekyll ${JEKYLL_VERSION}; installs the mounted site's gems at runtime" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${JEKYLL_VERSION}" \
      org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Bundler installs into a vendored path UNDER the mounted volume (/srv/jekyll),
# which is writable even with a read-only root FS and persists between runs.
# HOME + BUNDLE_APP_CONFIG live on the writable tmpfs.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_PATH=/srv/jekyll/vendor/bundle \
    BUNDLE_APP_CONFIG=/tmp/.bundle \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    HOME=/tmp
ENV PATH="${GEM_HOME}/bin:${PATH}"

# ---- Runtime + build toolchain ----------------------------------------------
# The toolchain is required so `bundle install` can compile native gems at
# container start. We still strip language runtimes we don't use.
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install --no-install-recommends \
        ruby ruby-dev \
        build-essential \
        git \
        pkg-config \
        libffi-dev zlib1g-dev libyaml-dev \
        ca-certificates \
        tini && \
    \
    # ---- Uninstall unneeded language runtimes -------------------------------
    # Ruby stays (Jekyll). Perl is KEPT because git depends on it (and perl-base
    # is Essential regardless). Python and other stray interpreters are removed.
    # Best-effort + idempotent; anything already absent is skipped.
    for pkg in \
        python3 python3-minimal python3.12 \
        libpython3.12-minimal libpython3.12-stdlib \
        tcl tcl8.6 lua5.4 mono-runtime nodejs \
        golang golang-go gccgo-go ; do \
        apt-get purge -y "$pkg" 2>/dev/null || true ; \
    done && \
    apt-get -y autoremove --purge && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
           /usr/share/doc/* /usr/share/man/*

# ---- Latest Bundler + a fallback Jekyll (for sites with no Gemfile) ----------
# `gem install bundler` (no version) pulls the newest release and never needs a
# Gemfile.lock.
RUN gem install --no-document bundler && \
    gem install --no-document jekyll -v "${JEKYLL_VERSION}"

# ---- Strip setuid/setgid bits (privilege-escalation surface) ----------------
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# ---- Entrypoint: locks + installs the mounted site's gems at runtime --------
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# ---- Unprivileged user ------------------------------------------------------
ARG APP_UID=10001
ARG APP_GID=10001
RUN groupadd --gid "${APP_GID}" --system jekyll && \
    useradd  --uid "${APP_UID}" --gid "${APP_GID}" --system \
             --no-create-home --shell /usr/sbin/nologin jekyll && \
    install -d -o "${APP_UID}" -g "${APP_GID}" -m 0755 /srv/jekyll

WORKDIR /srv/jekyll
USER ${APP_UID}:${APP_GID}

# jekyll serve listens on 4000; livereload (if enabled) on 35729.
EXPOSE 4000

# tini stays PID 1 (signal forwarding + zombie reaping) and hands off to the
# entrypoint, which installs gems (if a Gemfile is mounted) then serves.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]

# CMD carries ONLY the arguments forwarded to `jekyll serve`.
CMD ["--host", "0.0.0.0", "--port", "4000"]
