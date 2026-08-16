.pragma library

function parseConfig(raw) {
  var result = { apiKey: "", baseUrl: "", allowInsecure: false }
  String(raw || "").split(/\r?\n/).forEach(function(line) {
    var separator = line.indexOf("=")
    if (separator < 1) return
    var key = line.substring(0, separator).trim()
    var value = line.substring(separator + 1).trim()
    if (key === "API_KEY") result.apiKey = value
    else if (key === "URL_BASE") result.baseUrl = value.replace(/\/+$/, "")
    else if (key === "ALLOW_INSECURE") result.allowInsecure = value === "true"
  })
  return result
}

function serializeConfig(apiKey, baseUrl, allowInsecure) {
  return "API_KEY=" + apiKey + "\n"
    + "URL_BASE=" + String(baseUrl || "").replace(/\/+$/, "") + "\n"
    + "ALLOW_INSECURE=" + (allowInsecure ? "true" : "false") + "\n"
}

function summarize(raw) {
  var payload = JSON.parse(String(raw || "{}"))
  var resources = payload && Array.isArray(payload.data) ? payload.data : []
  var nodes = resources.filter(function(resource) { return resource && resource.type === "node" })
  var guests = resources.filter(function(resource) {
    return resource && (resource.type === "qemu" || resource.type === "lxc")
  })
  var cpuUsed = 0
  var cpuTotal = 0
  var memoryUsed = 0
  var memoryTotal = 0
  nodes.forEach(function(node) {
    var maxCpu = Number(node.maxcpu || 0)
    cpuUsed += Number(node.cpu || 0) * maxCpu
    cpuTotal += maxCpu
    memoryUsed += Number(node.mem || 0)
    memoryTotal += Number(node.maxmem || 0)
  })
  return {
    resources: resources,
    onlineNodes: nodes.filter(function(node) { return node.status === "online" }).length,
    totalNodes: nodes.length,
    runningGuests: guests.filter(function(guest) { return guest.status === "running" }).length,
    stoppedGuests: guests.filter(function(guest) { return guest.status !== "running" }).length,
    cpuRatio: cpuTotal > 0 ? cpuUsed / cpuTotal : 0,
    memoryRatio: memoryTotal > 0 ? memoryUsed / memoryTotal : 0
  }
}

function errorMessage(raw, fallback) {
  var message = String(raw || "").trim()
  if (message === "") return fallback
  try {
    var parsed = JSON.parse(message)
    if (parsed && parsed.errors) return JSON.stringify(parsed.errors)
    if (parsed && parsed.message) return String(parsed.message)
  } catch (error) {}
  return message.replace(/\s+/g, " ").substring(0, 240)
}
