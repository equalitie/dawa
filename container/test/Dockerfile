# The image the CI `test` job runs in.
#
# WHY THIS EXISTS
#
# The test job needs a C toolchain and a set of -dev headers to build native
# gems plus sqlite3. Installing those with apt on every pipeline run costs a
# round-trip to the Debian mirrors on every job, and caching the .deb files does
# not help much: apt still has to fetch the package index before it can decide
# nothing changed.
#
# This test image removes that cost. This image must be rebuilt when the package
# list changes, but it will change infrequently and the pipeline runs often.
#
# WHAT THIS IS NOT
#
# It is NOT the app image (`/Dockerfile`). It contains no app code at all.
# It is just a baseline debian image that tests can be run in.
#
# Note the apt lists are NOT deleted here, unlike in the app image. A job that needs one
# extra package can then install it without an `apt-get update` round-trip, which is the
# whole reason this image exists.
#

ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:${RUBY_VERSION}-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential \
        git \
        libssl-dev \
        libyaml-dev \
        pkg-config \
        libsodium-dev \
        libvips \
        sqlite3 && \
    rm -rf /var/cache/apt/archives/*

# A no-op layer
CMD ["/bin/bash"]
