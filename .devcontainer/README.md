# The dev container

Everything needed to work on canonscope, in one image, so a host machine needs
nothing but a container runtime.

```sh
# VS Code / any devcontainer-aware editor: "Reopen in Container"
# or by hand:
docker build -t canonscope-dev -f .devcontainer/Dockerfile .devcontainer
docker run --rm -it -v "$PWD:/workspaces/canonscope" -w /workspaces/canonscope \
    canonscope-dev bash
```

## What it cannot do: the camera

**There is no USB in here, and there will not be.** This is a property of the
approach, not a gap to be filled later:

- USB passthrough needs `--device=/dev/bus/usb/<bus>/<dev>`, and those paths
  change every time the camera is replugged or power-cycled.
- **udev rules execute on the host.** `tools/udev/99-canonscope-camera.rules`
  stops `gvfsd-gphoto2` claiming the camera, and both the problem and the fix
  live outside the container.
- Docker Desktop on macOS and Windows has no USB passthrough at all.

So `canonscope shoot`, `preview`, `zoom` and `focus` are host-side work. The
container is for everything else — and "everything else" is most of it,
because the test suites were built to need no camera.

## It is not how a controller is deployed

A controller (a Raspberry Pi or any Linux box) runs `tools/` directly — from
the `.deb`, or from a checkout — as bash and coreutils. A container must never
become a dependency of that. This image is a development convenience.

## Why Debian trixie

It is the base of Raspberry Pi OS (trixie), the reference controller OS, and
the release `.deb`s are built on it. If a package resolves here it resolves
there, and if chdkptp builds here it builds there.

## Scripts

| Script | Does |
| --- | --- |
| `post-create.sh` | Creates `build/mcpvenv-container` and installs the MCP SDK. Runs once, automatically. |
| `verify.sh` | Everything that needs no camera: syntax, shellcheck, version and manifest checks, the private-identifier guard, CLI, schema, MCP. This is what CI runs. |
| `../packaging/build-chdkptp.sh` | Builds chdkptp from the pinned upstream source. Needs the network; not run automatically. |
| `../packaging/build-deb.sh` | Builds the `.deb` for the container's architecture. |

## Deliberately absent

`gphoto2` — only ever a host-side sanity check that the camera enumerates.
