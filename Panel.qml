import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.brandc87.omamox"
  ipcTarget: "io.github.brandc87.omamox"

  property bool editingConnection: false
  property bool tokenVisible: false
  property int activeResourceTab: 0
  property var pendingActionResource: null
  property string pendingAction: ""

  readonly property bool configured: service.configured && !editingConnection
  readonly property bool loading: service.refreshing
  property alias allowInsecure: service.allowInsecure
  readonly property string statusText: service.statusText
  readonly property string errorText: service.lastError
  readonly property string baseUrl: service.baseUrl
  readonly property var resources: service.resources
  readonly property int onlineNodes: service.onlineNodes
  readonly property int totalNodes: service.totalNodes
  readonly property int runningGuests: service.runningGuests
  readonly property int stoppedGuests: service.stoppedGuests
  readonly property real cpuRatio: service.cpuRatio
  readonly property real memoryRatio: service.memoryRatio
  readonly property string actionBusyKey: service.actionBusyKey

  readonly property var containers: filteredResources("lxc")
  readonly property var virtualMachines: filteredResources("qemu")
  readonly property var disks: filteredResources("storage")
  readonly property var activeResourceList: activeResourceTab === 0
    ? containers : (activeResourceTab === 1 ? virtualMachines : disks)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color meterTrack: Style.selectedFillFor(foreground, accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Service { id: service; settings: root.settings }

  Connections {
    target: service
    function onConnectionSaved() {
      root.editingConnection = false
      root.tokenVisible = false
      apiKeyInput.text = ""
    }
  }

  function filteredResources(type) {
    return resources.filter(function(resource) {
      return resource && resource.type === type
    }).sort(function(left, right) {
      return resourceName(left).localeCompare(resourceName(right))
    })
  }

  function resourceName(resource) {
    if (!resource) return "Unknown"
    return String(resource.name || resource.storage || resource.id || resource.vmid || "Unknown")
  }

  function formatBytes(value) {
    var bytes = Number(value || 0)
    if (bytes <= 0) return "0 B"
    var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    var index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
    var scaled = bytes / Math.pow(1024, index)
    return (scaled >= 10 || index === 0 ? scaled.toFixed(0) : scaled.toFixed(1)) + " " + units[index]
  }

  function percent(value, maximum) {
    var max = Number(maximum || 0)
    return max > 0 ? Math.round(Number(value || 0) / max * 100) : 0
  }

  function resourceStatus(resource) {
    if (!resource) return "unknown"
    return String(resource.status || (Number(resource.active || 0) === 1 ? "active" : "unknown"))
  }

  function resourceDetails(resource) {
    if (!resource) return ""
    if (resource.type === "storage") {
      return formatBytes(resource.disk) + " / " + formatBytes(resource.maxdisk)
        + (resource.node ? "  •  " + resource.node : "")
    }
    return Math.round(Number(resource.cpu || 0) * 100) + "% CPU  •  "
      + percent(resource.mem, resource.maxmem) + "% memory  •  "
      + formatBytes(resource.mem) + " / " + formatBytes(resource.maxmem)
      + (resource.node ? "  •  " + resource.node : "")
  }

  function guestKey(resource) {
    return service.guestKey(resource)
  }

  function openWebUi(resource) {
    var url = baseUrl
    if (resource && resource.vmid) {
      url += "/#v1:0:=" + encodeURIComponent(String(resource.type) + "/" + String(resource.vmid)) + ":4:::::::"
    }
    Qt.openUrlExternally(url)
    close()
  }

  function requestGuestAction(resource, action) {
    if (!resource || actionBusyKey !== "") return
    if (action === "start") {
      runGuestAction(resource, action)
      return
    }
    pendingActionResource = resource
    pendingAction = action
    actionConfirm.selectedIndex = 0
    actionConfirm.opened = true
  }

  function cancelGuestAction() {
    actionConfirm.opened = false
    pendingActionResource = null
    pendingAction = ""
  }

  function confirmGuestAction() {
    var resource = pendingActionResource
    var action = pendingAction
    cancelGuestAction()
    runGuestAction(resource, action)
  }

  function runGuestAction(resource, action) {
    service.runGuestAction(resource, action)
  }

  function open() {
    root.controller.show()
    refresh()
  }

  function openFromHotkey() { open() }

  function close() {
    root.controller.hide()
    apiKeyInput.text = ""
    tokenVisible = false
  }

  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  function refresh() {
    service.refresh()
  }

  function saveConnection() {
    service.saveConnection(urlInput.text, apiKeyInput.text, allowInsecure)
  }

  function editConnection() {
    service.lastError = ""
    tokenVisible = false
    urlInput.text = service.baseUrl
    apiKeyInput.text = service.apiKey
    editingConnection = true
    Qt.callLater(function() { urlInput.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        OmamoxIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: Qt.darker(root.barForeground, 1.12)
        }
      }
    }
    tooltipText: root.statusText
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !root.configured
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.configured && contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(14)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              id: panelTitle
              text: "Omamox"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item {
              width: Math.max(0, parent.width - panelTitle.width - openProxmoxButton.width - parent.spacing * 2)
              height: 1
            }

            Button {
              id: openProxmoxButton
              anchors.verticalCenter: parent.verticalCenter
              text: root.loading ? "Refreshing…" : "Open Proxmox"
              bordered: true
              enabled: root.baseUrl !== "" && !root.loading
              foreground: root.foreground
              accent: root.accent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              fontSize: Style.font.caption
              onClicked: root.openWebUi(null)
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: !root.configured

            Text {
              width: parent.width
              text: "Connect to Proxmox VE"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            TextField {
              id: urlInput
              width: parent.width
              placeholderText: "https://proxmox.example:8006"
              foreground: root.foreground
              accent: root.accent
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: apiKeyInput
                width: parent.width - tokenVisibilityButton.width - parent.spacing
                placeholderText: "user@pve!token-name=token-secret"
                password: !root.tokenVisible
                foreground: root.foreground
                accent: root.accent
                onAccepted: root.saveConnection()
              }

              Button {
                id: tokenVisibilityButton
                anchors.verticalCenter: parent.verticalCenter
                text: root.tokenVisible ? "Hide" : "Show"
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.tokenVisible = !root.tokenVisible
              }
            }

            Toggle {
              width: parent.width
              label: "Allow insecure TLS"
              description: "Accept a self-signed or otherwise untrusted Proxmox certificate."
              checked: root.allowInsecure
              foreground: root.foreground
              accent: root.accent
              onClicked: root.allowInsecure = !root.allowInsecure
            }

            Button {
              text: "Save and connect"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              onClicked: root.saveConnection()
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.allowInsecure
                ? "Warning: certificate verification will be disabled. Use this only on a network you trust."
                : "Credentials are saved to ~/.config/omamox/.env with mode 0600. HTTPS certificate verification is enabled."
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Grid {
            width: parent.width
            columns: 2
            spacing: Style.space(10)
            visible: root.configured

            Repeater {
              model: [
                { label: "Nodes", value: root.onlineNodes + " / " + root.totalNodes },
                { label: "Guests", value: root.runningGuests + " running" },
                { label: "CPU", value: Math.round(root.cpuRatio * 100) + "%" },
                { label: "Memory", value: Math.round(root.memoryRatio * 100) + "%" }
              ]

              BorderSurface {
                id: summaryCard
                required property var modelData
                width: (contentColumn.width - Style.space(10)) / 2
                height: Style.space(70)
                color: Style.hoverFillFor(root.foreground, root.accent)
                radius: Style.cornerRadius

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(3)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: summaryCard.modelData.value
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: summaryCard.modelData.label
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.configured
            text: root.stoppedGuests + " stopped guests  •  " + root.baseUrl
            elide: Text.ElideMiddle
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.configured

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  "Containers (" + root.containers.length + ")",
                  "VMs (" + root.virtualMachines.length + ")",
                  "Disks (" + root.disks.length + ")"
                ]

                Button {
                  id: resourceTabButton
                  required property int index
                  required property var modelData
                  property int tabIndex: index
                  text: String(modelData)
                  selected: root.activeResourceTab === tabIndex
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  onClicked: root.activeResourceTab = tabIndex
                }
              }
            }

            Flickable {
              id: resourceList
              width: parent.width
              height: Style.space(180)
              contentWidth: width
              contentHeight: resourceListColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height

              Column {
                id: resourceListColumn
                width: resourceList.width
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  visible: root.activeResourceList.length === 0
                  text: root.loading ? "Loading resources…" : "No resources in this group"
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: root.activeResourceList

                  BorderSurface {
                    id: resourceRow
                    required property var modelData
                    readonly property int diskPercent: root.percent(modelData.disk, modelData.maxdisk)
                    width: resourceListColumn.width
                    height: Style.space(88)
                    color: Style.hoverFillFor(root.foreground, root.accent)
                    radius: Style.cornerRadius

                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(12)
                      anchors.rightMargin: Style.space(12)
                      spacing: Style.space(3)

                      Row {
                        width: parent.width

                        Text {
                          width: parent.width - resourceStatusLabel.width
                          text: root.resourceName(resourceRow.modelData)
                            + (resourceRow.modelData.vmid ? "  #" + resourceRow.modelData.vmid : "")
                          elide: Text.ElideRight
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }

                        Text {
                          id: resourceStatusLabel
                          text: resourceRow.modelData.type === "storage"
                            ? resourceRow.diskPercent + "%"
                            : root.resourceStatus(resourceRow.modelData)
                          color: root.resourceStatus(resourceRow.modelData) === "running"
                            || root.resourceStatus(resourceRow.modelData) === "active"
                            || root.resourceStatus(resourceRow.modelData) === "available"
                            ? root.accent : root.foreground
                          opacity: resourceRow.modelData.type === "storage"
                            ? 1 : (color === root.foreground ? 0.55 : 1)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      Item {
                        visible: resourceRow.modelData.type === "storage"
                        width: 1
                        height: visible ? 2 : 0
                      }

                      Item {
                        visible: resourceRow.modelData.type === "storage"
                        width: parent.width
                        height: visible
                          ? Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
                          : 0

                        Rectangle {
                          id: diskMeterTrack
                          anchors.fill: parent
                          radius: height / 2
                          color: root.meterTrack
                        }

                        Rectangle {
                          anchors.left: diskMeterTrack.left
                          anchors.verticalCenter: diskMeterTrack.verticalCenter
                          height: diskMeterTrack.height
                          radius: diskMeterTrack.radius
                          width: diskMeterTrack.width * Math.max(0, Math.min(1, resourceRow.diskPercent / 100))
                          color: resourceRow.diskPercent >= 90 ? Color.urgent : root.foreground

                          Behavior on width {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                          }
                        }
                      }

                      Text {
                        width: parent.width
                        text: root.resourceDetails(resourceRow.modelData)
                        elide: Text.ElideRight
                        color: root.foreground
                        opacity: 0.62
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Item {
                        visible: resourceRow.modelData.type !== "storage"
                        width: 1
                        height: visible ? 2 : 0
                      }

                      Row {
                        visible: resourceRow.modelData.type === "lxc" || resourceRow.modelData.type === "qemu"
                        spacing: Style.space(4)

                        Button {
                          text: "Start"
                          enabled: root.resourceStatus(resourceRow.modelData) !== "running"
                            && root.actionBusyKey === ""
                          bordered: true
                          foreground: root.foreground
                          accent: root.accent
                          horizontalPadding: Style.space(5)
                          verticalPadding: Style.space(2)
                          fontSize: Style.font.caption
                          onClicked: root.requestGuestAction(resourceRow.modelData, "start")
                        }

                        Button {
                          text: "Shutdown"
                          enabled: root.resourceStatus(resourceRow.modelData) === "running"
                            && root.actionBusyKey === ""
                          bordered: true
                          foreground: root.foreground
                          accent: root.accent
                          horizontalPadding: Style.space(5)
                          verticalPadding: Style.space(2)
                          fontSize: Style.font.caption
                          onClicked: root.requestGuestAction(resourceRow.modelData, "shutdown")
                        }

                        Button {
                          text: "Reboot"
                          enabled: root.resourceStatus(resourceRow.modelData) === "running"
                            && root.actionBusyKey === ""
                          bordered: true
                          foreground: root.foreground
                          accent: root.accent
                          horizontalPadding: Style.space(5)
                          verticalPadding: Style.space(2)
                          fontSize: Style.font.caption
                          onClicked: root.requestGuestAction(resourceRow.modelData, "reboot")
                        }

                        Button {
                          text: "Edit"
                          bordered: true
                          foreground: root.foreground
                          accent: root.accent
                          horizontalPadding: Style.space(5)
                          verticalPadding: Style.space(2)
                          fontSize: Style.font.caption
                          onClicked: root.openWebUi(resourceRow.modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.errorText !== ""
            wrapMode: Text.WordWrap
            text: root.errorText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(8)
            visible: root.configured

            Button {
              text: "Refresh"
              bordered: true
              enabled: !root.loading
              foreground: root.foreground
              accent: root.accent
              onClicked: root.refresh()
            }

            Button {
              text: "Edit connection"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              onClicked: root.editConnection()
            }
          }
        }
      }

      ConfirmDialog {
        id: actionConfirm
        anchors.fill: parent
        z: 20
        message: root.pendingActionResource
          ? "Do you want to " + root.pendingAction + " "
            + root.resourceName(root.pendingActionResource) + " (#"
            + root.pendingActionResource.vmid + ")?"
          : "Confirm guest action?"
        confirmText: root.pendingAction === "reboot" ? "Reboot" : "Shutdown"
        background: Color.background
        foreground: root.foreground
        selectedText: root.accent
        fontFamily: root.fontFamily
        onCanceled: root.cancelGuestAction()
        onConfirmed: root.confirmGuestAction()
      }
    }
  }
}
