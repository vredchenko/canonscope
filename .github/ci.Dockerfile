# CI-only layer: the dev container image with the checkout baked in.
#
# Why copy rather than bind-mount: the image runs as uid 1000 and
# post-create.sh has to create build/ inside the tree, while the runner's
# checkout belongs to a different uid. Copying with --chown sidesteps
# ownership entirely, and works identically on hosted and self-hosted runners
# (including ones where `docker run -v` is resolved by a daemon that cannot
# see the job's filesystem).
ARG BASE=canonscope-dev
FROM ${BASE}
COPY --chown=dev:dev . /workspaces/canonscope
WORKDIR /workspaces/canonscope
