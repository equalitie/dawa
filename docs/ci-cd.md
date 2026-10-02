# CI/CD

The pipeline is defined in `.gitlab-ci.yml` and has three stages: `image`, `test`, `build`.

## Jobs

* `build-test-image` (`image` stage): builds the image the `test` job runs in, from `container/test/Dockerfile`.

* `test` (`test` stage): runs `rake test:all`, in the image built by `build-test-image`.

* `build-image` (`build` stage): builds and pushes the application image. Runs only on the default branch and on semver tags.

## The `test` image

`test` does not run on a stock Ruby image. It runs on one built from `container/test/Dockerfile`, which bakes in the packages the suite needs to build native gems.

Installing those with apt inside the test job would work, but would pay a round-trip to the Debian package index on every pipeline. 

Baking them in to a test image instead pays that cost once per change to the Dockerfile. The trade off is that the image must be rebuilt when the package list changes, which is rare, while the pipeline runs often.

This image is not the application image. It contains no app code, and GitLab supplies the checkout and the bundle cache.

### Content tagging

`build-test-image` tags its image by a hash of the image's inputs, not by commit:

```sh
TEST_TAG="$( { cat container/test/Dockerfile; printf '\n%s\n' "$RUBY_VERSION"; } | sha256sum | cut -c1-12 )"
```

The inputs are the Dockerfile and `RUBY_VERSION`, which selects the base image tag. Both are hashed, so bumping `RUBY_VERSION` produces a new tag rather than silently reusing an image built on the old Ruby.

A commit tag would produce a new tag per commit, naming a byte-identical image. The content tag means a rebuild either reproduces the tag already in the registry, in which case the push is skipped, or the image genuinely changed.

### Layer caching

Baking the packages into the image is only half the saving. The other half is not rebuilding them, and that needs the apt layers to live somewhere a fresh CI container can reach.

`--layers` keeps intermediate layers in buildah's LOCAL storage, and `--cache-from` and `--cache-to` make the registry store each layer as well.

```sh
buildah build \
  --layers \
  --cache-from "$TEST_IMAGE" \
  --cache-to "$TEST_IMAGE" \
  ...
```

Confirming the cache works takes two checks, because the first can pass while the second fails:

* After a build, the registry should list cache entries alongside the image.

* A second build with no Dockerfile change should print `Using cache` for the apt steps rather than running them. If cache entries exist but apt still runs, the cache is being written but not read.

### Why `test` pulls `latest`

`test` cannot reference the content tag. GitLab expands a job's `image:` before any script in any job runs, and the tag is computed inside `build-test-image`'s own shell, so there is nothing for `test` to read.

So `build-test-image` also publishes the same image as `:latest`, and `test` pulls that. The consequence is that a rebuild concurrent with a running `test` job can swap the image under it. That is acceptable because the image holds a package set that changes rarely, rather than application code.

To pin exactly, `test` would have to consume the tag from a separate job rather than compute it, which is a larger change than the tagging itself.

### First run

`build-test-image` is guarded by `rules: changes`, so on most commits it does not run. Its tag therefore may not exist yet, in two cases: a fresh registry, or the first pipeline after this job was added. `test` then fails early with `manifest unknown`.

The fix is to run the build once by hand:

```sh
gitlab-ci-local build-test-image --manual
```

This applies to the pipeline in GitLab too. On the default branch the job is published as an optional manual job, so it appears in the `image` stage of the pipeline with a play button and the pipeline can pass without it:

1. Open the pipeline for a commit on the default branch (Pipelines -> the pipeline, or the job's own page).

2. Find `build-test-image` in the `image` stage and press play.

3. Later pipelines can then pull `test-base:latest`.

The button only exists on a pipeline whose rules matched. The manual clause requires the default branch, so a pipeline for a feature branch never shows one. If you need the image built from a branch that has no button, change a comment in `container/test/Dockerfile` and push to the default branch: that makes the `changes` rule match and the job runs automatically.

## Running CI/CD Locally

Install gitlab-ci-local: https://github.com/firecow/gitlab-ci-local

Install buildah:

```sh
apt install buildah
```

Create a file to define local environment variables FOR RUNNER JOBS:

```sh
cat > .gitlab-ci-local-variables.yml <<EOF
CI_REGISTRY_USER: robot$local-ci
CI_REGISTRY_PASSWORD: your-secret-token
CI_REGISTRY: registry.dcomms.org
HARBOR_PROJECT: dcomms-private
EOF
```

You must also configure authentication for `docker`:

```sh
docker login --username 'robot$local-ci' registry.dcomms.org
```

List the jobs:

```sh
cd dawa
gitlab-ci-local --list
```

Run a job:

```sh
gitlab-ci-local build-test-image
```

Jobs guarded by `rules: changes` show as `manual` when their inputs have not changed, and are skipped. Run them with `--manual`:

```sh
gitlab-ci-local build-test-image --manual
```

Add `--preview` to print the expanded job without running it.
