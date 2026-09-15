import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "Model.js" as Model

// Binds the bar to vibez's own MPRIS player.
//
// vibez registers org.mpris.MediaPlayer2.vibez on the session bus and serves the
// full player interface from it (internal/player/mpris/server.go). That name is
// fixed and belongs to one process, so finding the player is a string
// comparison — no pid matching, no helper, no polling. A browser-based player
// needs all of that because a Chromium-family browser publishes one player per
// *process* covering every tab, under an instance<pid> name; a player that
// publishes itself needs none of it.
Item {
  id: root

  property var settings: ({})

  readonly property string busName: "org.mpris.MediaPlayer2.vibez"

  property string lastError: ""
  property string actionStatus: ""
  property int positionTick: 0

  property string artUrl: ""
  property string artSource: ""

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: findPlayer()

  // vibez creates its MPRIS server only once the audio engine is ready, so the
  // player appearing means more than the process existing: it means the thing
  // is actually able to play something.
  readonly property bool running: player !== null
  readonly property bool hasMedia: player !== null && (trackTitle !== "" || trackArtist !== "")
  readonly property bool isPlaying: player !== null && player.isPlaying === true

  readonly property string trackTitle: player ? Model.sanitize(player.trackTitle) : ""
  readonly property string trackArtist: player ? Model.sanitize(player.trackArtist) : ""
  readonly property string trackAlbum: player ? Model.sanitize(player.trackAlbum) : ""

  readonly property bool canGoNext: player !== null && player.canGoNext === true
  readonly property bool canGoPrevious: player !== null && player.canGoPrevious === true
  readonly property bool canToggle: player !== null && player.canTogglePlaying === true
  readonly property bool canSeek: player !== null && player.canSeek === true && lengthKnown

  // vibez reports a real duration from the track it queued, so unlike a web
  // player the panel can draw a bar that means something and a total that is
  // not INT64_MAX. The upper bound is kept as a sanity check, not a workaround.
  readonly property real trackLength: {
    var l = player ? Number(player.length) : 0
    if (!isFinite(l) || l <= 0 || l > 86400) return 0
    return l
  }
  readonly property bool lengthKnown: trackLength > 0
  readonly property bool positionKnown: player !== null && player.positionSupported === true
  readonly property real trackPosition: {
    positionTick
    if (!player || !positionKnown) return 0
    var p = Number(player.position)
    return isFinite(p) && p >= 0 ? p : 0
  }

  // Both are writable on vibez's player and wired to its own repeat and shuffle
  // (server.go maps LoopStatus and Shuffle onto SetRepeat and SetShuffle), so
  // these are controls rather than readouts.
  readonly property bool shuffleSupported: player !== null && player.shuffleSupported === true
  readonly property bool shuffleOn: player !== null && player.shuffle === true
  readonly property bool loopSupported: player !== null && player.loopSupported === true
  readonly property string loopState: {
    if (!player) return "None"
    if (player.loopState === MprisLoopState.Track) return "Track"
    if (player.loopState === MprisLoopState.Playlist) return "Playlist"
    return "None"
  }
  readonly property string loopLabel: Model.loopLabel(loopState)

  readonly property string headline: Model.headline({
    running: running, hasMedia: hasMedia, isPlaying: isPlaying
  })

  readonly property string barLabel: showTrackInBar && hasMedia
    ? Model.barLabel(trackTitle, trackArtist, maxBarChars)
    : ""

  readonly property bool showTrackInBar: setting("showTrackInBar", true) === true
  readonly property bool showArtwork: setting("showArtwork", true) === true
  readonly property int maxBarChars: intSetting("maxBarChars", 28, 8, 80)

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string launchHelper: pluginDir + "/bin/omarchy-vibez"
  readonly property string artHelper: pluginDir + "/bin/omarchy-vibez-art"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function findPlayer() {
    var list = players || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].dbusName || "") === busName) return list[i]
    }
    return null
  }

  function note(text) {
    actionStatus = Model.sanitize(text)
    actionStatusTimer.restart()
  }

  // ------------------------------------------------------------- artwork

  // vibez publishes cover art as a remote https URL on Apple's CDN. Fetching it
  // here would put the bar on the network against an address that arrived as
  // metadata, so the helper does it out of process, against an allow-list, and
  // hands back a path. Until it does, artUrl stays empty and the panel shows its
  // placeholder — which is also what happens when a track simply has no art.
  function refreshArt() {
    var wanted = player && showArtwork ? String(player.trackArtUrl || "") : ""
    if (wanted === artSource) return
    artSource = wanted
    artUrl = ""
    if (wanted === "") return
    if (artProcess.running) artProcess.running = false
    artProcess.command = ["/usr/bin/bash", artHelper, wanted]
    artProcess.running = true
  }

  // ------------------------------------------------------------- actions

  // One entry point for both cases: the helper focuses an existing window and
  // starts one when there is none, and reports which it did.
  function open() {
    if (launchProcess.running) return
    launchProcess.command = ["/usr/bin/bash", launchHelper]
    launchProcess.running = true
  }

  function playPause() {
    if (!player) { open(); return }
    if (canToggle) player.togglePlaying()
    else note("vibez is not accepting playback commands")
  }

  function next() {
    if (!player || !canGoNext) return
    player.next()
  }

  function previous() {
    if (!player || !canGoPrevious) return
    player.previous()
  }

  function toggleShuffle() {
    if (!player || !shuffleSupported) return
    player.shuffle = !shuffleOn
    note(shuffleOn ? "Shuffle off" : "Shuffle on")
  }

  // Off, then every track, then the one track — the order vibez itself cycles.
  function cycleRepeat() {
    if (!player || !loopSupported) return
    if (loopState === "None") player.loopState = MprisLoopState.Playlist
    else if (loopState === "Playlist") player.loopState = MprisLoopState.Track
    else player.loopState = MprisLoopState.None
  }

  function seekFraction(fraction) {
    if (!player || !canSeek) return
    var target = Model.seekTarget(fraction, trackLength)
    if (target < 0) return
    player.position = target
    positionTick++
  }

  onPlayerChanged: {
    artSource = ""
    refreshArt()
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onTrackArtUrlChanged() { root.refreshArt() }
  }

  onShowArtworkChanged: refreshArt()

  // MPRIS position is read on demand rather than pushed, so the progress line
  // needs its own tick. Only while something is actually playing.
  Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying && root.positionKnown
    onTriggered: root.positionTick++
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  // Both helpers answer in one short line. The cap is small and applied to each
  // chunk as it arrives rather than to a collected result, because a collector
  // has already allocated whatever it was handed by the time a length check
  // runs — and this is the shell process, shared with every other widget.
  readonly property int maxHelperBytes: 4096

  property string launchBuf: ""
  property string artBuf: ""

  function overflowed(proc, buf) {
    if (buf.length <= maxHelperBytes) return false
    proc.signal(15)
    return true
  }

  Process {
    id: launchProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.launchBuf += chunk
        if (root.overflowed(launchProcess, root.launchBuf)) {
          root.launchBuf = ""
          launchKill.restart()
        }
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.launchBuf.length <= root.maxHelperBytes) root.launchBuf += chunk
      }
    }
    onRunningChanged: if (running) launchDeadline.restart(); else launchDeadline.stop()
    onExited: function(exitCode) {
      launchKill.stop()
      var out = Model.sanitize(root.launchBuf)
      root.launchBuf = ""
      if (exitCode === 0 && out !== "") {
        root.lastError = ""
        root.note(out)
        return
      }
      root.lastError = out !== "" ? out : ("Could not run " + root.launchHelper)
    }
  }

  // A helper that never exits would otherwise hold the widget in "opening"
  // forever. TERM first, KILL after a grace period, both on the process group.
  Timer {
    id: launchDeadline
    interval: 20000
    repeat: false
    onTriggered: if (launchProcess.running) { launchProcess.signal(15); launchKill.restart() }
  }

  Timer {
    id: launchKill
    interval: 2000
    repeat: false
    onTriggered: if (launchProcess.running) launchProcess.signal(9)
  }

  // A failed fetch is not worth a message in the panel: the placeholder already
  // says there is no art, and the reason is almost always that the track has
  // none. Only the launch path reports errors.
  Process {
    id: artProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.artBuf += chunk
        if (root.overflowed(artProcess, root.artBuf)) {
          root.artBuf = ""
          artKill.restart()
        }
      }
    }
    onRunningChanged: if (running) artDeadline.restart(); else artDeadline.stop()
    onExited: function(exitCode) {
      artKill.stop()
      var out = String(root.artBuf || "").trim()
      root.artBuf = ""
      if (exitCode !== 0) { root.artUrl = ""; return }
      // Only a path this plugin's own cache produced is rendered. The helper
      // prints nothing else, but the check is here rather than assumed.
      root.artUrl = /^file:\/\/\/[^\0\n]+$/.test(out) ? out : ""
    }
  }

  Timer {
    id: artDeadline
    interval: 20000
    repeat: false
    onTriggered: if (artProcess.running) { artProcess.signal(15); artKill.restart() }
  }

  Timer {
    id: artKill
    interval: 2000
    repeat: false
    onTriggered: if (artProcess.running) artProcess.signal(9)
  }

  // Nothing this plugin started outlives it.
  Component.onDestruction: {
    if (launchProcess.running) launchProcess.signal(15)
    if (artProcess.running) artProcess.signal(15)
  }
}
