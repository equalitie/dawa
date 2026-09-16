# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      # for healthcheck:
      curl \
      # better memory management:
      libjemalloc2 \
      # image processing
      libvips \
      # for nacl gem:
      libsodium23 \
      # maybe not needed:
      sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libssl-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems
COPY Gemfile Gemfile.lock ./
COPY gems/ ./gems/
COPY engines/ ./engines/

RUN BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -1 | tr -d ' ') && \
    gem install bundler -v "$BUNDLER_VERSION"

RUN bundle install --jobs=4 --retry=3 && \
    # Generate binstubs for all executables
    bundle binstubs --all && \
    # Add the binstubs directory to PATH
    echo 'export PATH="./bin:$PATH"' >> ~/.bashrc && \
    # remove cache files
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# make system rake match Gemfile rake
RUN RAKE_VERSION=$(bundle exec rake --version | cut -d' ' -f3) && \
    gem install rake -v "$RAKE_VERSION" --no-document

# Install all source code
COPY . .

# Precompile bootsnap code for faster boot times.
RUN bundle exec bootsnap precompile --gemfile app/ lib/ gems/ engines/

# build static assets
RUN rake dawa:precompile

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 8080
ENV THRUSTER_HTTP_PORT=8080
CMD ["./bin/thrust", "./bin/rails", "server"]
