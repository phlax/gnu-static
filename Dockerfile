# syntax=docker/dockerfile:1.7
#
# gnu-static -- a FROM scratch image containing nothing but the static GNU
# userland binaries produced by build/build-one.sh.
#
# Consumers should:  COPY --from=ghcr.io/phlax/gnu-static:<tag> /bin/ /bin/
#
# This Dockerfile is intentionally trivial. The build is done outside in CI
# (one runner per tool, parallel) and the binaries are dropped into out/bin/
# before `docker build .` is invoked. That keeps build time and image
# concerns separate.

FROM scratch
COPY out/bin/ /bin/

# No ENTRYPOINT. This is a binary delivery image, not a runnable one.
# Verify with:  docker run --rm --entrypoint /bin/ls ghcr.io/phlax/gnu-static:<tag> /bin
