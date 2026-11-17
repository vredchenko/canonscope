# Shell and provisioning lessons

Patterns and traps that apply to anything that writes to hardware or
provisions a headless box. Some were learned on this project, and some come
from earlier provisioning work and are generalised here. The scripts in
`tools/` follow them.

## Principles

**Validate before you escalate.** Every safety check in a destructive script
should run *unprivileged*, so a wrong target is rejected while the script
still cannot destroy anything. `tools/make-card.sh` reads the device size
from `/sys/block/<dev>/size` rather than `blockdev --getsize64` for exactly
this reason: the latter needs root, which would force escalation before the
decision it is meant to inform. Everything above its
`ESCALATE ONLY BELOW THIS LINE` marker runs as you.

**Replace a guard, never remove it.** A USB hard disk fails both of an SD-card
writer's guards (removable, under a size cap). So the fixed-disk mode does not
skip them. It *substitutes* an exact serial match (`--expect-serial`). The guard
count never goes down, and no flag skips the identifying check.

**Show what is about to die.** Before erasing, print model, serial, size and
current contents (with a file count for anything mounted), and make a human
type the device name back. "It's blank" is a claim worth checking.

**Report, don't fix, when the fix is physical.** A health check that sees an
SoC at 80 °C should say "throttling — fit a heatsink", not try to do something
about it.

**Assert, then verify.** Don't trust that writing a config file changed
behaviour. Read the *effective* setting back. For example,
`sshd -T | awk '/^passwordauthentication/{print $2}'` should print `no`.
`make-card.sh` re-reads the `BOOTDISK` marker and runs fsck after writing.

**Exercise every branch, not just the default.** `make-card.sh --mode chdk`
carried a live bug through five test runs because every run used
`--mode verreq`. A flag that selects a different code path needs its own run.

**Before a first commit, list what the VCS actually considers untracked.**
Some tools silently skip dotfiles in their "add everything" shortcut.
Check what a fresh checkout's status command reports before trusting it.

## Shell traps

Each of these cost real time. Several are instances of the `set -e` class of
bug: commands that "cannot fail", failing.

**`grep -c` prints `0` but exits non-zero when the count is zero.** So the
idiomatic-looking `grep -c pattern file || echo 0` emits **two lines** — `0`
from grep's own output and `0` from the fallback — and any arithmetic test below
it dies with a syntax error. Use `|| true`, never `|| echo 0`:

```sh
N="$(lsblk -nro TYPE "$DEV" | grep -c -e lvm -e raid || true)"   # right
N="$(lsblk -nro TYPE "$DEV" | grep -c -e lvm -e raid || echo 0)" # WRONG: "0\n0"
```

**A failing input redirect is reported by the shell, not the command**, so
`2>/dev/null` on the command does not suppress it and `|| fallback` does not
catch it cleanly:

```sh
tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo '?'   # still prints an error
[[ -r /proc/device-tree/model ]] && tr -d '\0' < ... || echo '?'  # right
```

**A health check must not use `set -e`.** It has to report every section even
when a probe fails; `set -e` silently truncates the report, which is the same
failure shape as the bad-package-name trap below — you get a partial result
that looks complete. This is also the argument for test-running a health
check on hardware where *everything* is absent: graceful degradation is not
something you can eyeball.

**Throttle flags are two sets of bits.** In `vcgencmd get_throttled`, the low
bits report what is happening *now* and bits 16–19 report what has happened
*at any point since boot*. Easy to misread one as the other and conclude a board
is currently throttling when it merely did once.

### `| grep -q` under `pipefail` — this one shipped

Found 2026-10-30 the hard way: `make-card.sh --mode chdk` refused a perfectly
good CHDK zip with "contains no DISKBOOT.BIN".

```sh
unzip -l "$BUILD" | grep -qi 'DISKBOOT.BIN' || die "..."
```

`grep -q` exits the instant it matches. `DISKBOOT.BIN` is the **first** entry in
the archive, so grep is gone almost immediately, `unzip` dies writing to a closed
pipe with **SIGPIPE (exit 141)**, and `set -o pipefail` reports the pipeline as
failed. The `|| die` therefore fires *because the match succeeded*.

The fix is to not pipe into something that exits early:

```sh
BUILD_LIST="$(unzip -l "$BUILD")"
grep -qi 'DISKBOOT.BIN' <<< "$BUILD_LIST" || die "..."
```

**`head` has the same problem.** `find | sort | head -25` SIGPIPEs `sort`, which
under `pipefail` and `set -e` aborts the script outright — in our case at the
very end, during post-write verification. `sed -n '1,25p'` consumes all its
input and is a safe substitute; so is `sed -n '1p'` for `head -1`.

Five instances existed in `make-card.sh`; two were masked by an incidental
`|| true` and three were live. Grep for `| grep -q` and `| head` in any
`pipefail` script.

**Why it was not caught:** every test run had used `--mode verreq`, which skips
the build validation entirely. The `chdk` branch had never once been executed
until a human ran it. Guards and validation only count as tested on the paths
actually taken — and a flag that selects a whole different code path deserves a
run of its own, even when it looks like a small variation on the one you tested.

## Provisioning a headless board

**First boot: no default account, and key-only authentication from the very
first boot**, rather than hardened afterwards. With cloud-init, defining
`users:` replaces the image's default account; combine it with
`lock_passwd: true`, `ssh_pwauth: false` and `disable_root: true`. On
Raspberry Pi OS, verify whether the image ships cloud-init before designing
around it. `userconf.txt`, `firstrun.sh` and Imager's options are less
expressive.

**Anti-lockout.** Refuse to disable password authentication if
`~/.ssh/authorized_keys` is missing or empty. On a board with no screen, this
guard is the difference between a hardened box and a brick.

**One bad package name plus `set -e` means nothing after that line runs.** On a
headless box, "nothing happened" is invisible. Install per package with
checks, or `|| die` with a message naming the package.

**sshd takes the FIRST match per keyword, and drop-ins load lexically.** A
hardening drop-in must sort *before* the distribution's own, so use
`00-hardening.conf`, not `99-hardening.conf`.

**The same first-match rule governs `~/.ssh/config`.** Only one `HostName`
per `Host` block is ever used. A second is silently ignored and does **not**
act as a fallback. Use a separate alias (`board-lan`) instead.

**A fresh install presents a new DHCP client-ID even with an unchanged MAC**,
so the board's address moves on reflash. Reserve by MAC, or reach it by name
through something you control.

**Match on the mountpoint, not on the current options.** To add `noatime` to
`/`, edit the line whose mountpoint is `/`. Never key off the string
`defaults`, because `/boot/firmware` usually has it too.

**Redact secrets from a boot partition after consuming them.** A key written
to a FAT boot partition is effectively world-readable: FAT has no permission
bits.

**Don't let an isolated node depend on the network's resolver.** If the box
you diagnose *from* takes its DNS from the network that broke, it breaks with
it. Reach peers by address or `/etc/hosts`.

**Keep a marker of what provisioned the box.** For example,
`/etc/<project>-provisioned` records host, image, media and timestamp.

**Firewall.** An autonomous controller has a decided purpose and may bind a
service to `0.0.0.0`. Give it a default-deny firewall.

## Credentials and storage

- **Never put a credential in a URL.** Use `curl -u` or the equivalent. A
  password containing `/` silently breaks URL userinfo parsing, and the
  failure looks like an auth problem.
- **Configure rclone through environment variables** (`RCLONE_CONFIG_<REMOTE>_*`)
  rather than a config file, so no file holding the key is written to disk.
- **Prefer copy semantics over sync** for anything irreplaceable.
  `rclone copy` never deletes, so a partial export keeps the previous good one.
- **An installer should refuse to install a backup timer when its password
  file or credentials are missing**, rather than install one that fails quietly
  every night.
- **Collect every failure, then exit non-zero.** For a multi-job backup, treat
  each job as independently fallible, reprint all failures at the end, and
  exit non-zero so systemd marks the run failed.

## Disks and monitoring

- **`smartmontools` pulls in postfix** unless installed with
  `--no-install-recommends`, and the install then blocks on an interactive
  mail-server prompt. smartd needs no mailer.
- **A USB disk is only monitored if it was attached when smartd started.**
  Restart the service after plugging one in, and use `-d sat` for USB-attached
  SATA. Use `-n standby,q` so checks never wake a sleeping disk.
- **Alerting on an autonomous box has to be local**: an LED, or a status file
  that the next connected sync ships out.

## Offline packages

Nothing off the shelf was found for this, so the suggested approach is opinion
rather than inherited practice:

```sh
apt-get --download-only install <pkgs>     # into a directory
dpkg-scanpackages . > Packages             # a local repo on the artefact drive
# then: deb [trusted=yes] file:///path/to/repo <suite> main
```

Pin architecture and suite exactly, and **keep the download manifest tracked
in git**, so the set is reproducible rather than whatever was current the day
the drive was built.
