# void

A wrapper around xbps and runit, mostly so I can stop looking up the runit way
of doing things every time I set up a Void box. One bash script, no build step,
no dependencies past what Void already installs.

```sh
void pkg install htop neovim git
void svc enable --now bluetoothd
void logs -f NetworkManager
void doctor
void cheat
```

The short version of what it changes: `void svc start foo` also enables `foo`,
because runit has no idea what a transient service is. `void pkg install` does
not sync indexes; that is `pkg update`'s job, and mixing the two is how you end
up with an install pulling from a month-old index. Everything else is mostly
remembering where runit keeps things.

## Install

```sh
./install.sh
```

Puts the command in `~/.local/bin/void` and the completion in
`~/.local/share/bash-completion/completions/void`. Make sure `~/.local/bin` is
on your `PATH`.

System-wide instead:

```sh
sudo PREFIX=/usr/local ./install.sh
```

To undo either one:

```sh
./install.sh --uninstall
sudo PREFIX=/usr/local ./install.sh --uninstall
```

## Packages

| Command | What it does |
| --- | --- |
| `void pkg install <pkg...>` | Install packages |
| `void pkg remove <pkg...>` | Remove packages (`rm` is an alias) |
| `void pkg update` | Refresh repository indexes only |
| `void pkg upgrade [pkg...]` | Upgrade everything or selected packages |
| `void pkg search <term>` | Search repositories (`--installed` to search locally) |
| `void pkg info <pkg>` | Show package details |
| `void pkg list` | List installed packages |
| `void pkg list --manual` | List packages you explicitly installed |
| `void pkg list --orphans` | List orphan packages |
| `void pkg files <pkg>` | Show files owned by a package |
| `void pkg owns <path>` | Find the package that owns a path |
| `void pkg deps <pkg>` | Show dependencies (`--reverse` for reverse deps) |
| `void pkg hold <pkg>` | Hold a package at its current version |
| `void pkg unhold <pkg>` | Release a held package |
| `void pkg reconfigure <pkg>` | Re-run a package's post-install steps |
| `void pkg autoremove` | Remove orphan packages |
| `void pkg clean [--all]` | Clean old packages from the cache |
| `void pkg repo ...` | Manage repositories and add third-party ones |

`void update` is shorthand for "refresh indexes, then upgrade everything".
`void install`, `void remove`, and `void search` work as top-level shortcuts
too, if you would rather not type the `pkg`.

Index refreshing only happens in `void pkg update`. `void pkg install` reads
whatever index is already on disk, so an install will not quietly pull in a new
index and upgrade half the system while you were only after htop.

### Parallel downloads

xbps fetches archives one at a time. `void pkg install` and `void pkg upgrade`
get around that by resolving the transaction first with `xbps-install -n`,
pulling the missing archives with `curl` several at a time, and dropping them in
`/var/cache/xbps`. The real `xbps-install` then finds them already on disk and
does not touch the network.

```sh
void pkg install neovim git -j 8   # eight at a time
void pkg install neovim            # default: one per CPU, capped at 32
void pkg install neovim --no-parallel
VOID_JOBS=4 void pkg upgrade
```

Order of operations:

1. `xbps-install -n` works out exactly what the real run will do. No network
   here, only the local package database and the repo indexes on disk.
2. Anything not already cached gets fetched with `curl`, `-j N` at a time, into
   a temp directory.
3. Each archive has to match the size the transaction advertised and then
   survive a `zstd -t` decompress test. Failures get thrown away. This check is
   not optional: a corrupt archive sitting in the cache makes `xbps-install`
   abort the whole transaction with an RSA signature error rather than
   re-downloading, so it is worth 57 ms to catch it first.
4. Survivors go into `/var/cache/xbps` in one privileged call, then the normal
   `xbps-install` runs.

`void pkg upgrade` syncs indexes first so the transaction it prefetches is the
one that actually runs, and then leaves `-S` off the final call since it would
be redundant.

Numbers from this machine, cold cache, 13 archives for neovim (~23 MB): 6.6 s
downloading serially, 4.1 s with `-j 8`. Whole-install time barely moves
because unpacking and configuring dominate on a fast mirror. The download phase
is where the savings are, and that part scales with archive size and how far
away the mirror is.

Every step here gives up quietly. No `curl`, no `xargs`, a dead mirror, a cache
directory you cannot write to, a package that disappeared from the index: in
all of those cases you get a plain `xbps-install` and no error message about
parallelism.

## Services

| Command | What it does |
| --- | --- |
| `void svc list` | Show enabled services and their live state |
| `void svc list --all` | Include services that are available but disabled |
| `void svc status [name...]` | Show details for one or more services |
| `void svc start <name...>` | Start a service (enables it first if needed) |
| `void svc stop <name...>` | Stop a service |
| `void svc restart <name...>` | Restart a service |
| `void svc reload <name...>` | Send `SIGHUP` to a service |
| `void svc enable [--now] <name>` | Enable at boot; `--now` also starts it |
| `void svc disable <name...>` | Stop and disable a service |
| `void svc logs [-f] <name>` | Show or follow a service log |
| `void svc edit <name>` | Edit `/etc/sv/<name>/run` with `sudoedit` |
| `void svc create <name> ...` | Create a new runit service |

### Making a service

Writing the `run` script is usually the part that stalls people, so this writes
one for you:

```sh
void svc create myservice --exec "/usr/bin/myservice --flag"
```

Which creates:

```
/etc/sv/myservice/run
/etc/sv/myservice/log/run
/var/log/myservice/
```

Options worth knowing:

```sh
# run as another user, via chpst
void svc create myservice --user nobody --exec "/usr/bin/myservice"

# no svlogd log service
void svc create myservice --no-log --exec "/usr/bin/myservice"

# enable and start it right after creating it
void svc create myservice --exec "/usr/bin/myservice" --enable
```

Editing later:

```sh
void svc edit myservice
void svc restart myservice
```

There is no `daemon-reload` step. runit reads the `run` script when the service
starts, so restarting is enough.

## Logs

```sh
void logs sddm              # last 50 lines
void logs -n 200 sddm       # last 200 lines
void logs -f NetworkManager # follow
void logs --list            # what log files exist
```

Services log in whatever way their author felt like, so `void logs` checks the
usual spots:

- `/var/log/<service>/current` (svlogd)
- `/var/log/<service>.log`
- whatever path it can pull out of `/etc/sv/<service>/log/run`

Some services hand off to `vlogger` or syslog and never write their own file.
In that case `void logs` points at the log script instead of pretending there
is a file to read.

## Coming from systemd

`void cheat` prints the whole table. `void cheat systemctl`, `void cheat
packages`, and `void cheat logs` narrow it down.

| systemd | void |
| --- | --- |
| `systemctl start foo` | `void svc start foo` |
| `systemctl stop foo` | `void svc stop foo` |
| `systemctl restart foo` | `void svc restart foo` |
| `systemctl status foo` | `void svc status foo` |
| `systemctl enable foo` | `void svc enable foo` |
| `systemctl enable --now foo` | `void svc enable --now foo` |
| `systemctl disable foo` | `void svc disable foo` |
| `systemctl list-units` | `void svc list` |
| `systemctl daemon-reload` | not a thing |
| `journalctl -u foo -f` | `void logs -f foo` |
| `apt install foo` | `void pkg install foo` |
| `apt remove foo` | `void pkg remove foo` |
| `apt update` | `void pkg update` |
| `apt upgrade` | `void update` |
| `apt search foo` | `void pkg search foo` |
| `dpkg -S /path` | `void pkg owns /path` |

## Repositories

`void pkg repo` handles third-party xbps repositories. `void repo` goes to the
same place.

```sh
void pkg repo                       # what is configured right now
void pkg repo available             # the built-in catalog
void pkg repo available hyprland    # filter it
void pkg repo info blackhole        # homepage, URL, arch support, state
void pkg repo add blackhole         # add a catalog repo by name
void pkg repo add vup-browsers
void pkg repo add https://repo.example.org/void --name example
void pkg repo disable blackhole     # keep the config, stop using it
void pkg repo enable blackhole
void pkg repo remove blackhole
void pkg repo refresh               # download fresh indexes
```

### The catalog

I checked each entry by fetching `<url>/<arch>-repodata` and confirming an xbps
index came back. `{{arch}}` expands to whatever `xbps-uhelper arch` says, so
musl and aarch64 machines get the right path without a separate entry.

| Name | What it is |
| --- | --- |
| `blackhole` | [BlackHole](https://www.black-hole.dev/), community packages, Hyprland, Wayland extras |
| `blackhole-ru` | BlackHole mirror in Russia |
| `hyprland` | Rolling Hyprland builds from `sofijacom/hyprland-void` (x86_64, glibc) |
| `librewolf` | LibreWolf builds |
| `noid` | Noid Linux packages |
| `sonicde` | SonicDE desktop |
| `kennel` | nwg-shell and Kennel-Linux |
| `xlibre` | XLibre X11 server |
| `linuxnauta` | LinuxNauta's personal repo |
| `voiders` | voiders.dev |
| `neko` | Neko Void |
| `lazy` | Lazy Linux |
| `grvn` | grvn's own builds |
| `vup-utilities` | VUP: utilities |
| `vup-productivity` | VUP: productivity |
| `vup-browsers` | VUP: browsers |
| `vup-communication` | VUP: communication |
| `vup-emulators` | VUP: emulators |
| `vup-education` | VUP: education |
| `vup-networking` | VUP: networking |
| `vup-languages` | VUP: languages |
| `vup-language-servers` | VUP: language servers |
| `vup-runtime-managers` | VUP: language runtime managers |

`void pkg repo available` reads the same table the code uses, so it cannot drift
out of date, and it marks anything already configured.

### Config files

Configs go in `/etc/xbps.d` as `<priority>-<name>.conf`. The priority matters:
xbps reads the files in name order and the first repo that has a package wins.

- `20-` for everything in the catalog, BlackHole included. Keeping third-party
  repos behind the `00-`/`10-` official ones means Void still wins on shared
  package names.
- `10-` for raw URLs added without a catalog name.

Adding a repo will not overwrite an existing config, and it will not add a URL
that is already configured. Trailing slashes do not count, so
`https://mirror.black-hole.dev/x86_64` and the same URL with a slash on the end
are one repo. `remove` takes a catalog name, a config filename, or a filename
stem, and matches by the URL inside the file rather than the filename, since
those do not always agree.

BlackHole used to publish through a GitHub repo configured as
`/etc/xbps.d/20-repository-extra.conf`. That setup is gone. Adding `blackhole`
now notices that file and offers to remove it first, because leaving both in
place gives you two sources for the same packages.

`disable` renames the file to `.conf.disabled`, which xbps ignores. `remove`
deletes it. Both ask first unless you pass `--yes`, and both respect
`--dry-run`.

### Conflicting repos

Some of these repos ship the same packages. xbps resolves a name from whichever
repo it reads first, so the second one is invisible: its builds never get
installed and its updates never show up. Nothing warns you about this, you just
quietly stop getting updates from a repo you thought was enabled.

The catalog has a `conflicts` field for this, and `void pkg repo add` refuses:

```
$ void pkg repo add hyprland
error: 'hyprland' conflicts with blackhole, which is already configured.
    They publish overlapping packages, so only the first one is used.
    Remove it first: void pkg repo remove blackhole
```

Two groups so far:

| Group | Why |
| --- | --- |
| `blackhole`, `blackhole-ru` | the Russian mirror is a full copy, all 121 packages |
| `blackhole`, `hyprland` | BlackHole ships 30 of the 33 packages in `sofijacom/hyprland-void`, including `hyprland`, `aquamarine`, `hyprlang` and `xdg-desktop-portal-hyprland` |

BlackHole is the wider source, 91 of its 121 packages are not in the Hyprland
repo at all. The `hyprland` entry exists for the newest compositor builds,
which run ahead of BlackHole by a version or two, at the cost of everything
else in that repo.

`void pkg repo list` grows a `Conflicting repositories:` block if two of these
end up enabled, and `void pkg repo info <name>` shows the group and which
member is currently live.

## Desktop caches

Hand-copied `.desktop` files, icon themes, and MIME types do not show up until
the caches are rebuilt:

```sh
void desktop refresh          # system-wide, uses sudo
void desktop refresh --user   # only things under ~/.local
void desktop refresh --no-icons --no-mime
```

Same thing by hand, if you would rather:

```sh
sudo update-desktop-database /usr/share/applications
sudo gtk-update-icon-cache -f -t /usr/share/icons/<theme>
sudo update-mime-database /usr/share/mime
```

Those come from `desktop-file-utils`, `gtk-update-icon-cache`, and
`shared-mime-info`.

## Health check

```sh
void doctor
```

Checks the things that bite people on a fresh Void install:

- is this actually Void
- are the xbps tools there
- is runit running and is `/var/service` intact
- any broken service symlinks
- is dbus enabled, since half the desktop needs it
- is a network service enabled
- orphan packages, pending updates
- is `/` filling up
- can this user actually run sudo

Warnings do not fail the command. Real problems exit non-zero.

## Output

```
==> Installing: htop
==> Fetching 3 package(s) with 4 parallel downloads
ok: Prefetched 3 package(s) into /var/cache/xbps
...
error: Package 'lolcat' was not found.
```

`==>` for progress, `ok:` for done, `warning:` and `error:` on stderr, and
notes indented underneath whichever line they belong to. No colour unless
stdout is a terminal, and `NO_COLOR` is respected.

## Safety

- Anything that changes the system goes through `sudo`, or `doas` if that is
  what you have. `void` never asks for or stores your password itself.
- `--dry-run` prints the exact command instead of running it:
  ```sh
  void --dry-run pkg install neovim
  void --dry-run svc create test --exec "sleep 1" --enable
  ```
- Only these write to `/etc`: `void svc create`, `void svc enable`,
  `void svc disable`, `void svc edit`, and `void pkg repo add/remove/
  disable/enable`. `void desktop refresh` only rebuilds caches under
  `/usr/share` or `~/.local/share`.
- `void svc disable` stops the service and removes its `/var/service` symlink.
  That is what disable means in runit; there is no separate stop-then-disable
  dance.

## Requirements

- Void Linux, or something with xbps and runit
- bash 4+
- `xbps-*`, `sv`, coreutils
- `sudo` or `doas` for the privileged commands
- optional: `bash-completion`, `curl`, `xargs` and `zstd` for parallel downloads

## Development

```sh
bash -n bin/void      # syntax
./tests/smoke.sh      # non-destructive checks
```

The smoke tests use a temp directory for service and repo paths via
`VOID_SV_DIR`, `VOID_SERVICE_DIR`, `VOID_LOG_DIR` and `VOID_XBPS_CONF_DIR`, so
running them does not touch the real system.

```
bin/void                  the command
completions/void.bash     bash completion
install.sh                installer and uninstaller
tests/smoke.sh            smoke tests
```

## License

MIT
