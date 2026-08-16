import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string configDir: configHome + "/omamox"
  readonly property string configPath: configDir + "/.env"

  property string apiKey: ""
  property string baseUrl: ""
  property bool allowInsecure: false
  property bool configured: false
  property bool refreshing: false
  property string statusText: "Omamox"
  property string lastError: ""
  property var resources: []
  property int onlineNodes: 0
  property int totalNodes: 0
  property int runningGuests: 0
  property int stoppedGuests: 0
  property real cpuRatio: 0
  property real memoryRatio: 0
  property string actionBusyKey: ""

  property string _fetchOutput: ""
  property string _fetchError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _pendingConfig: ""

  signal connectionSaved()

  readonly property bool busy: fetchProcess.running || actionProcess.running || mkdirProcess.running || saveProcess.running
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)

  function intSetting(name, fallback, min, max) {
    var value = settings && settings[name] !== undefined ? settings[name] : fallback
    var number = parseInt(String(value), 10)
    if (!isFinite(number)) number = fallback
    return Math.max(min, Math.min(max, number))
  }

  function loadConfig(raw) {
    var config = Model.parseConfig(raw)
    apiKey = config.apiKey
    baseUrl = config.baseUrl
    allowInsecure = config.allowInsecure
    configured = apiKey !== "" && baseUrl !== ""
    if (configured) refresh()
    else statusText = "Omamox needs setup"
  }

  function curlQuote(value) {
    return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
  }

  function curlConfig(url, method) {
    var lines = [
      "silent", "show-error", "fail-with-body", "max-time = 15",
      "header = \"Authorization: PVEAPIToken=" + curlQuote(apiKey) + "\"",
      "url = \"" + curlQuote(url) + "\""
    ]
    if (allowInsecure) lines.splice(4, 0, "insecure")
    if (method) lines.splice(4, 0, "request = \"" + method + "\"")
    return lines.join("\n") + "\n"
  }

  function startWithInput(process, input) {
    process.pendingInput = input
    process.stdinEnabled = true
    process.running = true
  }

  function refresh() {
    if (!configured || fetchProcess.running) return
    refreshing = true
    lastError = ""
    _fetchOutput = ""
    _fetchError = ""
    startWithInput(fetchProcess, curlConfig(baseUrl + "/api2/json/cluster/resources", ""))
  }

  function applyStatus(raw) {
    try {
      var summary = Model.summarize(raw)
      resources = summary.resources
      onlineNodes = summary.onlineNodes
      totalNodes = summary.totalNodes
      runningGuests = summary.runningGuests
      stoppedGuests = summary.stoppedGuests
      cpuRatio = summary.cpuRatio
      memoryRatio = summary.memoryRatio
      statusText = totalNodes > 0 ? onlineNodes + "/" + totalNodes + " nodes online" : "Connected"
    } catch (error) {
      lastError = "Proxmox returned an unreadable response"
      statusText = "Omamox error"
    }
  }

  function saveConnection(url, key, insecure) {
    url = String(url || "").trim().replace(/\/+$/, "")
    key = String(key || "").trim()
    if (!/^https?:\/\/[^\s]+$/.test(url)) {
      lastError = "Enter a complete http:// or https:// URL"
      return
    }
    if (key.indexOf("!") < 1 || key.indexOf("=") < 3 || /[\r\n]/.test(key)) {
      lastError = "Use user@realm!token-name=token-secret"
      return
    }
    lastError = ""
    _pendingConfig = Model.serializeConfig(key, url, insecure)
    mkdirProcess.running = true
  }

  function guestKey(resource) {
    return resource ? String(resource.type) + ":" + String(resource.vmid) : ""
  }

  function runGuestAction(resource, action) {
    if (!resource || actionProcess.running || !configured) return
    var type = String(resource.type || "")
    var node = String(resource.node || "")
    var vmid = String(resource.vmid || "")
    if ((type !== "qemu" && type !== "lxc") || !/^[A-Za-z0-9._-]+$/.test(node)
        || !/^\d+$/.test(vmid) || ["start", "stop", "reboot"].indexOf(action) < 0) {
      lastError = "Invalid guest action"
      return
    }
    lastError = ""
    _actionOutput = ""
    _actionError = ""
    actionBusyKey = guestKey(resource)
    var url = baseUrl + "/api2/json/nodes/" + encodeURIComponent(node) + "/"
      + type + "/" + vmid + "/status/" + action
    startWithInput(actionProcess, curlConfig(url, "POST"))
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.configured = false
      root.statusText = "Omamox needs setup"
    }
  }

  Process {
    id: fetchProcess
    property string pendingInput: ""
    command: ["curl", "--config", "-"]
    onStarted: {
      write(pendingInput)
      pendingInput = ""
      stdinEnabled = false
    }
    stdout: StdioCollector { id: fetchStdout; waitForEnd: true; onStreamFinished: root._fetchOutput = text }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true; onStreamFinished: root._fetchError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(fetchStdout.text || root._fetchOutput || "")
      var stderr = String(fetchStderr.text || root._fetchError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else {
        root.statusText = "Proxmox unavailable"
        root.lastError = Model.errorMessage(stderr || stdout, "Could not contact Proxmox")
      }
    }
  }

  Process {
    id: actionProcess
    property string pendingInput: ""
    command: ["curl", "--config", "-"]
    onStarted: {
      write(pendingInput)
      pendingInput = ""
      stdinEnabled = false
    }
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      root.actionBusyKey = ""
      if (exitCode === 0) actionRefreshTimer.restart()
      else root.lastError = Model.errorMessage(stderr || stdout, "Proxmox rejected the guest action")
    }
  }

  Process {
    id: mkdirProcess
    command: ["install", "-d", "-m", "700", root.configDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "Could not create the Omamox configuration directory"
        return
      }
      try {
        root.startWithInput(saveProcess, root._pendingConfig)
      } catch (error) {
        root.lastError = "Could not save the connection"
      }
    }
  }

  Process {
    id: saveProcess
    property string pendingInput: ""
    command: ["install", "-m", "600", "/dev/stdin", root.configPath]
    onStarted: {
      write(pendingInput)
      pendingInput = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "Could not save the connection securely"
        return
      }
      root.loadConfig(root._pendingConfig)
      root._pendingConfig = ""
      root.connectionSaved()
    }
  }

  Timer { id: actionRefreshTimer; interval: 1500; onTriggered: root.refresh() }
  Timer { interval: root.refreshIntervalSec * 1000; repeat: true; running: root.configured; onTriggered: root.refresh() }

  Component.onCompleted: configFile.reload()
}
