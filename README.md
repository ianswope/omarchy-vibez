# vibez

[vibez](https://github.com/simonepelosi/vibez) in the Omarchy bar: what it is
playing, and the transport for it, without switching to the terminal it runs in.

## The case it exists for

vibez is a TUI, and a good one — but a TUI lives in a window you have to go
back to. Most of the time the only thing wanted from a music player is the
title of what is playing and a way to skip it, and neither is worth leaving
what you were doing for.

vibez already publishes everything needed for that. It registers
`org.mpris.MediaPlayer2.vibez` on the session bus and serves the full MPRIS
player interface from it, including a real track duration and writable shuffle
and repeat. This plugin is a reader for that, plus one script to open the
window when there isn't one.

## What it shows

* Track, artist and album, with cover art.
* Elapsed time, total, and a progress bar you can click to scrub.
* Whether vibez is closed, running and idle, playing, or paused. Those are four
  different states and the panel names which one it is.
* In the bar: the note icon, dimmed while nothing is running, plus the current
  track when there is one.

## Actions

| Key | Action |
|---|---|
| `p` | play or pause |
| `n` | next track |
| `b` | previous track |
| `s` | shuffle |
| `r` | repeat: off, all, one |
| `o` or `enter` | open vibez, or focus the window if it is already open |
| `esc` | close the panel |

On the bar icon: left click opens the panel, right click plays or pauses
without opening anything. Clicking the progress bar seeks.

The same actions are on the shell IPC, which makes them bindable from Hyprland:

```bash
omarchy-shell ianswope.vibez playpause
omarchy-shell ianswope.vibez next
omarchy-shell ianswope.vibez shuffle
omarchy-shell ianswope.vibez repeat
omarchy-shell ianswope.vibez status     # Playing, Paused, Ready, Not running
omarchy-shell ianswope.vibez track      # Title · Artist
```

## How it finds vibez

By name. `org.mpris.MediaPlayer2.vibez` is fixed, belongs to one process, and is
registered by vibez itself, so finding the player is a string comparison against
`Mpris.players` and there is nothing to poll — the name appearing *is* the
event.

That is worth spelling out, because the same widget for a web player cannot be
written this way. A Chromium-family browser publishes one MPRIS player per
browser **process**, covering every tab, under an `instance<pid>` name it does
not promise to keep, and exposes no `xesam:url`. A widget bound to that is
really showing whatever tab is loudest. Getting a single app out of it needs a
dedicated profile, a scan of `/proc` for the process that owns it, and a match
against the bus name's owning pid. A player that publishes itself needs none of
that, and this plugin has none of it.

## Two things that are less obvious

**Cover art is fetched out of process.** vibez publishes `mpris:artUrl` as a
remote URL on Apple's artwork CDN, which is the honest thing for it to do — but
handing a URL that arrived as metadata to a QML `Image` would make the bar
itself fetch an address it did not choose. So `bin/omarchy-vibez-art` does the
fetch instead: `https` only, no redirects followed, hosts restricted to
`*.mzstatic.com`, size capped, and the result checked for an actual image magic
number before it is kept. The shell only ever reads a local file. The cache
lives in `$XDG_CACHE_HOME/omarchy-vibez/art` and is bounded at 60 images.

**The window is matched by class, not by title.** vibez is started through
`xdg-terminal-exec --app-id=org.omarchy.vibez`, and that app-id is the only
thing matched when focusing it. Matching the title as well — which
`omarchy-launch-or-focus-tui` does — would focus a terminal that merely has the
word "vibez" in its title, such as one editing the vibez source or sitting in
its source directory.

The consequence: a vibez started by hand in an ordinary terminal is not a window
this plugin can recognise. Rather than start a second one, it says so. A second
vibez would run, lose the race for the MPRIS bus name, and then publish nothing
at all — so the bar would go quiet while the music kept playing.

## What it touches

**Network.** One endpoint, and only for cover art:
`https://*.mzstatic.com` — Apple's artwork CDN, whose URL vibez publishes as
`mpris:artUrl`. The request carries no credentials, follows no redirects, and is
made by `bin/omarchy-vibez-art`, never by the shell. Nothing else on the network
is contacted, and no data leaves the machine.

**Files written.** One directory: `$XDG_CACHE_HOME/omarchy-vibez/art`
(`~/.cache/omarchy-vibez/art` by default), mode 0700, holding at most 60 cover
images at mode 0600, named by the SHA-256 of their source URL. Nothing else is
written — no state, no credentials, no configuration of yours is edited.

**Reads.** The session bus, for `org.mpris.MediaPlayer2.vibez` only, and
`hyprctl clients` to find the vibez window.

## Removing

```bash
omarchy plugin remove ianswope.vibez
```

That removes the plugin. Two things survive it, because they are not the
plugin's to delete:

* The cover-art cache at `~/.cache/omarchy-vibez/art`. Album covers only —
  no listening history, no credentials. Delete it with
  `rm -rf ~/.cache/omarchy-vibez` if you want it gone.
* vibez itself, and any vibez window that is open. The plugin starts vibez but
  does not own it; close the terminal as you normally would.

Nothing is left running, no permissions are granted, and no shared
configuration is modified, so there is nothing else to revoke.

## Requirements

`vibez`, plus `jq`, `curl`, `busctl` and `hyprctl`, which Omarchy already has.

vibez is looked for at `~/.local/bin/vibez`, `/usr/local/bin/vibez` and
`/usr/bin/vibez`, in that order — a fixed list rather than `PATH`, since this is
the binary that gets launched. `OMARCHY_VIBEZ_BIN` overrides it with an absolute
path. Every other program the two helpers run is called by absolute path for the
same reason.

## Credit

vibez is Simone Pelosi's: <https://github.com/simonepelosi/vibez>. This plugin
is not affiliated with it, and does not speak for it — it is a bar widget built
by someone who likes the player.

## License

MIT.
