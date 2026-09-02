import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

import "Dock.js" as Dock

BarWidget {
  id: root

  moduleName: "io.github.hogar1977.top-bar-dock"

  readonly property int maxTitleLength: Math.max(4, Number(root.setting("maxTitleLength", 18)))
  readonly property int previewDelay: Math.max(0, Number(root.setting("previewDelay", 350)))
  readonly property int previewTileCap: 6

  readonly property var dock: {
    var _ = serviceRetry.tries
    if (!bar || !bar.shell) return null
    if (typeof bar.shell.ensureService === "function") {
      var inst = bar.shell.ensureService(moduleName)
      if (inst) return inst
    }
    return typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
  }

  readonly property var dockEntries: dock ? dock.dockEntries : []
  readonly property int currentWorkspaceId: dock ? dock.currentWorkspaceId : -1
  readonly property var dragOrder: dock ? dock.dragOrder : null
  readonly property string dragId: dock ? dock.dragId : ""
  readonly property int dragGap: dock ? dock.dragGap : -1
  readonly property real dragDeadzone: dock ? dock.dragDeadzone : 10

  property var previewEntry: null
  property Item previewAnchor: null
  property var pendingPreviewEntry: null
  property Item pendingPreviewAnchor: null
  property var hoverChip: null
  property var menuEntry: null
  property Item menuAnchor: null
  property var menuItems: []

  implicitWidth: chipRow.implicitWidth
  implicitHeight: chipRow.implicitHeight
  visible: dock !== null

  function isMinimized(w) { return dock && dock.isMinimized(w) }
  function isRelevantWindow(w) { return dock && dock.isRelevantWindow(w) }
  function isActiveToplevel(w) { return dock && dock.isActiveToplevel(w) }
  function normalizedAddress(w) { return dock ? dock.normalizedAddress(w) : "" }
  function windowTitle(w) { return dock ? dock.windowTitle(w, root.maxTitleLength) : "" }
  function verticalLabel(w) { return dock ? dock.verticalLabel(w, root.maxTitleLength) : "W" }
  function prettyPinName(id) { return dock ? dock.prettyPinName(id) : id }
  function iconFromId(id, entry) { return dock ? dock.iconFromId(id, entry) : "" }
  function windowIcon(w) { return dock ? dock.windowIcon(w) : "" }
  function previewCardTitle(entry) { return dock ? dock.previewCardTitle(entry) : "" }
  function launchPinned(id) { if (dock) dock.launchPinned(id) }
  function toggleWindow(w) { if (dock) dock.toggleWindow(w) }
  function activateTile(w) { if (dock) dock.activateTile(w) }
  function closeWindow(w) { if (dock) dock.closeWindow(w) }

  function openMenu(anchorItem, entryObj) {
    root.menuAnchor = anchorItem
    root.menuEntry = entryObj
    root.menuItems = dock ? dock.menuItemsFor(entryObj) : []
  }

  function closeMenu() {
    root.menuEntry = null
    root.menuAnchor = null
  }

  function requestPreview(anchor, entryObj) {
    if (!entryObj) return
    pendingPreviewAnchor = anchor
    pendingPreviewEntry = entryObj
    previewTimer.restart()
  }

  function cancelAllPreviews() {
    previewTimer.stop()
    pendingPreviewAnchor = null
    pendingPreviewEntry = null
    previewEntry = null
    previewAnchor = null
  }

  function syncPreview() {
    if (!root.previewEntry) return
    if (!Dock.previewStillValid(root.previewEntry, root.dockEntries))
      root.cancelAllPreviews()
  }

  onCurrentWorkspaceIdChanged: root.cancelAllPreviews()
  onDockEntriesChanged: root.syncPreview()

  Timer {
    id: serviceRetry
    property int tries: 0
    interval: 200
    repeat: true
    running: root.dock === null
    onTriggered: serviceRetry.tries++
  }

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: {
      root.previewAnchor = root.pendingPreviewAnchor
      root.previewEntry = root.pendingPreviewEntry
      root.pendingPreviewAnchor = null
      root.pendingPreviewEntry = null
    }
  }

  GridLayout {
    id: chipRow
    columns: root.vertical ? 1 : Math.max(1, root.dockEntries.length)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(1) : 0

    Repeater {
      model: root.dockEntries

      WidgetButton {
        id: chip

        required property var modelData
        readonly property bool pinnedSlot: modelData.kind === "pinned"
        readonly property var toplevel: modelData.toplevel
        readonly property int iconExtent: Style.space(15)
        readonly property string iconSource: pinnedSlot
          ? root.iconFromId(modelData.entryId, modelData.entry) : root.windowIcon(toplevel)
        readonly property var windows: modelData.windows || (modelData.toplevel ? [modelData.toplevel] : [])
        readonly property bool multi: !pinnedSlot && windows.length > 1
        readonly property bool minimized: !pinnedSlot && windows.length > 0
          && windows.every(function(w) { return root.isMinimized(w) })
        readonly property bool focused: !pinnedSlot && windows.length > 0
          && windows.some(function(w) { return root.isActiveToplevel(w) }) && !minimized
        readonly property bool elsewhere: !pinnedSlot && !minimized && toplevel
          && toplevel.workspace !== null && toplevel.workspace.id !== root.currentWorkspaceId
        readonly property bool elsewhereSingle: !pinnedSlot && !multi && elsewhere
        readonly property string pinHost: pinnedSlot ? modelData.entryId : (modelData.pinId || "")
        readonly property bool draggedPin: root.dragOrder !== null && chip.pinHost === root.dragId

        bar: root.bar
        text: ""
        keepSpace: true
        hasVisualContent: true
        labelVisible: false
        fixedWidth: root.barSize
        fixedHeight: root.barSize
        clip: true
        dimmed: chip.draggedPin
        tooltipText: pinnedSlot
          ? (modelData.entry && modelData.entry.name
              ? modelData.entry.name : root.prettyPinName(modelData.entryId))
          : ""
        onTooltipHoveredChanged: {
          if (tooltipHovered) {
            root.hoverChip = chip
            if (!pinnedSlot) root.requestPreview(chip, modelData)
          } else if (root.hoverChip === chip) {
            root.hoverChip = null
          }
        }
        onPressed: function(button) {
          root.cancelAllPreviews()
          if (button === Qt.LeftButton) {
            if (pinnedSlot) {
              root.launchPinned(modelData.entryId)
            } else if (chip.multi) {
              root.previewTimer.stop()
              root.previewAnchor = chip
              root.previewEntry = modelData
              root.hoverChip = chip
            } else {
              root.toggleWindow(toplevel)
            }
          } else if (button === Qt.RightButton) {
            root.openMenu(chip, modelData)
          }
        }

        Rectangle {
          id: chipBackground
          anchors.fill: parent
          anchors.margins: Style.space(1)
          radius: Math.min(Style.cornerRadius, Style.space(4))
          color: {
            if (chipDrag.pressed) {
              return Util.alpha(Color.accent, 0.65)
            }
            if (chipHover.hovered || chip.tooltipHovered) {
              return Util.alpha(Color.accent, root.chipHoverAlpha || 0.50)
            }
            return "transparent"
          }

          Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
          }
        }

        HoverHandler { id: chipHover }

        MouseArea {
          id: chipDrag
          anchors.fill: parent
          acceptedButtons: Qt.MiddleButton
          preventStealing: true
          enabled: chip.pinHost !== "" && root.dock

          onPressed: {
            if (!root.dock || root.dock.dragOrder !== null) return
            root.closeMenu()
            root.cancelAllPreviews()
            chip.hideOwnTooltip()
            root.dock.beginDrag(chip.pinHost, mouse.x, mouse.y)
          }
          onPositionChanged: {
            if (!root.dock || root.dock.dragOrder === null) return
            var dx = mouse.x - root.dock.dragOriginX
            var dy = mouse.y - root.dock.dragOriginY
            if (dx * dx + dy * dy < root.dragDeadzone * root.dragDeadzone) return
            var p = chipDrag.mapToItem(chipRow, mouse.x, mouse.y)
            var target = root.dock.pinIndexAt(p.x, p.y, root.barSize, Style.space(1), root.vertical)
            root.dock.updateDrag(target)
          }
          onReleased: {
            if (!root.dock || root.dock.dragOrder === null) return
            root.dock.commitDrag(root.dock.dragTarget)
          }
          onCanceled: {
            if (root.dock) root.dock.resetDrag()
          }
        }

        Item {
          anchors.centerIn: parent
          width: chip.iconExtent
          height: chip.iconExtent

          Image {
            id: appIcon
            anchors.fill: parent
            source: chip.iconSource
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.centerIn: parent
            visible: appIcon.status === Image.Error || appIcon.source.toString() === ""
            text: chip.pinnedSlot
              ? (chip.modelData.entry && chip.modelData.entry.name
                  ? chip.modelData.entry.name.charAt(0).toUpperCase()
                  : root.prettyPinName(chip.modelData.entryId).charAt(0) || "?")
              : root.verticalLabel(chip.toplevel)
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            id: wsBadge
            visible: chip.elsewhereSingle
            text: chip.toplevel && chip.toplevel.workspace && Number(chip.toplevel.workspace.id) > 0 ? String(chip.toplevel.workspace.id) : ""
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Math.max(6, Style.font.caption - 3)
            style: Text.Outline
            styleColor: Util.alpha(root.bar ? root.bar.background : Color.background, 0.7)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -Style.space(3)
            anchors.rightMargin: -Style.space(3)
          }
        }

        Loader {
          id: segIndicator
          active: !chip.pinnedSlot && chip.windows && chip.windows.length > 0
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(1)
          sourceComponent: segmentedIndicatorComp

          readonly property var winList: chip.windows
          readonly property bool groupMinimized: chip.minimized
        }

        Component {
          id: segmentedIndicatorComp

          Item {
            id: indicatorRoot

            readonly property var winList: segIndicator.winList
            readonly property bool groupMinimized: segIndicator.groupMinimized
            readonly property int count: winList ? winList.length : 0
            readonly property int displaySegments: Math.max(1, Math.min(5, count))
            readonly property real totalSpan: Style.space(16)
            readonly property real barHeight: Style.space(2)
            readonly property real segmentGap: Style.spaceReal(1.5)
            readonly property real segmentWidth: (totalSpan - segmentGap * (displaySegments - 1)) / displaySegments

            function segmentColor(index) {
              if (groupMinimized) {
                return Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.40)
              }
              if (count > 5 && index === 4) {
                var anyTailFocused = false
                var allTailMinimized = true
                for (var bi = 4; bi < winList.length; bi++) {
                  var bw = winList[bi]
                  if (bw && root.isActiveToplevel(bw)) anyTailFocused = true
                  if (bw && !root.isMinimized(bw)) allTailMinimized = false
                }
                if (anyTailFocused) return Color.accent
                if (allTailMinimized) {
                  return Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.40)
                }
                return Util.alpha(Color.accent, 0.65)
              }
              var w = (winList && index < winList.length) ? winList[index] : null
              if (w && root.isActiveToplevel(w)) return Color.accent
              if (w && root.isMinimized(w)) {
                return Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.40)
              }
              return Util.alpha(Color.accent, 0.65)
            }

            implicitWidth: totalSpan
            implicitHeight: barHeight

            Row {
              anchors.centerIn: parent
              spacing: indicatorRoot.segmentGap
              Repeater {
                model: indicatorRoot.displaySegments
                Rectangle {
                  required property int index
                  width: indicatorRoot.segmentWidth
                  height: indicatorRoot.barHeight
                  radius: Math.max(1, Style.space(1))
                  color: indicatorRoot.segmentColor(index)
                  Behavior on color { ColorAnimation { duration: 100 } }
                }
              }
            }
          }
        }

        Component.onDestruction: {
          var md = chip.modelData
          if (root.hoverChip === chip) root.hoverChip = null
          if (root.dock && root.dock.dragOrder !== null && root.dock.dragId === chip.pinHost)
            root.dock.resetDrag()
          if (root.menuAnchor === chip) root.closeMenu()
          if (root.pendingPreviewAnchor === chip || (md && root.pendingPreviewEntry === md)) {
            root.previewTimer.stop()
            root.pendingPreviewAnchor = null
            root.pendingPreviewEntry = null
          }
          if (root.previewAnchor === chip || (md && root.previewEntry === md)) {
            root.previewAnchor = null
            root.previewEntry = null
          }
        }
      }
    }
  }

  Rectangle {
    id: dropBar
    visible: root.dragOrder !== null && root.dragGap >= 0 && root.dock
    width: root.vertical ? chipRow.width : Style.space(2)
    height: root.vertical ? Style.space(2) : chipRow.height
    radius: Style.space(2)
    color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.5)
    x: root.vertical ? chipRow.x : (chipRow.x + (root.dock ? root.dock.dropOffset(root.dragGap, root.barSize, Style.space(1), Style.space(2)) : 0))
    y: root.vertical ? (chipRow.y + (root.dock ? root.dock.dropOffset(root.dragGap, root.barSize, Style.space(1), Style.space(2)) : 0)) : (chipRow.y + (chipRow.height - height) / 2)
  }

  PopupCard {
    id: previewCard

    readonly property var previewWindows: {
      var ws = root.previewEntry && root.previewEntry.windows ? root.previewEntry.windows : []
      if (ws.length <= root.previewTileCap) return ws
      var out = []
      for (var i = 0; i < root.previewTileCap; i++) out.push(ws[i])
      return out
    }
    readonly property int tileCount: previewCard.previewWindows.length

    anchorItem: root.previewAnchor || root
    bar: root.bar
    triggerMode: "hover"
    open: root.previewEntry !== null && root.previewAnchor !== null
      && (root.hoverChip === root.previewAnchor || previewCard.containsMouse)
      && root.previewEntry.windows
      && root.previewEntry.windows.some(function(w) { return root.isRelevantWindow(w) })
    contentWidth: previewCard.tileCount > 1
      ? Math.round(previewCard.tileCount * Style.space(96) + (previewCard.tileCount - 1) * Style.space(6) + Style.space(24))
      : Style.space(320)
    contentHeight: previewCard.tileCount > 1
      ? Style.space(72) + Style.space(30) + Style.space(22) + Style.space(8)
      : Style.space(220)
    padding: Style.space(8)

    Item {
      anchors.fill: parent

      Item {
        id: previewFrame
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: previewTitle.top
        anchors.bottomMargin: Style.space(7)
        clip: true

        Row {
          id: groupTiles
          visible: previewCard.tileCount > 1
          anchors.centerIn: parent
          spacing: Style.space(6)

          Repeater {
            model: previewCard.previewWindows

            Column {
              required property var modelData
              width: Style.space(96)
              spacing: Style.space(2)

              Rectangle {
                width: Style.space(96)
                height: Style.space(72)
                radius: Style.space(4)
                clip: true
                color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.08)

                Image {
                  anchors.fill: parent
                  source: modelData ? root.windowIcon(modelData) : ""
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  fillMode: Image.PreserveAspectFit
                  opacity: tileView.hasContent ? 0 : 0.5
                }

                ScreencopyView {
                  id: tileView
                  anchors.fill: parent
                  captureSource: modelData
                    ? (modelData.wayland || (modelData.real && modelData.real.wayland)) : null
                  live: previewCard.open
                  paintCursor: false
                }

                Rectangle {
                  anchors.fill: parent
                  radius: parent.radius
                  color: "transparent"
                  border.width: tileHover.hovered ? Math.max(1, Style.space(1)) : 0
                  border.color: tileHover.hovered ? Color.accent : "transparent"
                  Behavior on border.color {
                    ColorAnimation { duration: 80 }
                  }
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.topMargin: Style.space(3)
                  anchors.leftMargin: Style.space(3)
                  visible: badgeText.text !== ""
                  radius: Style.space(4)
                  color: Util.alpha(root.bar ? root.bar.background : Color.background, 0.75)
                  width: badgeText.implicitWidth + Style.space(6)
                  height: badgeText.implicitHeight + Style.space(3)

                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: {
                      var ws = modelData && modelData.workspace ? modelData.workspace : null
                      var direct = ws ? Number(ws.id) : 0
                      if (direct > 0) return String(ws.id)
                      var addr = root.normalizedAddress(modelData)
                      var saved = addr && root.dock ? root.dock.lastWorkspaceByAddress[addr] : ""
                      if (saved !== undefined && saved !== null) {
                        var s = String(saved).trim()
                        if (s && s.indexOf("special:") !== 0) return s
                        var n = Number(s)
                        if (n > 0) return String(n)
                      }
                      return ""
                    }
                    color: root.bar ? root.bar.barForeground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Math.max(6, Style.font.caption - 3)
                  }
                }

                Rectangle {
                  id: closeButton
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: width / 2
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.topMargin: Style.space(3)
                  anchors.rightMargin: Style.space(3)
                  color: closeHover.hovered ? Color.urgent : Util.alpha(root.bar ? root.bar.background : Color.background, 0.75)
                  opacity: tileHover.hovered ? 1 : 0
                  Behavior on opacity {
                    NumberAnimation { duration: 100 }
                  }
                  Behavior on color {
                    ColorAnimation { duration: 100 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: "\u00d7"
                    color: closeHover.hovered ? (root.bar ? root.bar.background : Color.background) : (root.bar ? root.bar.barForeground : Color.foreground)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  HoverHandler { id: closeHover }
                  TapHandler {
                    onTapped: root.closeWindow(modelData)
                  }
                }

                HoverHandler { id: tileHover }
                TapHandler {
                  onTapped: if (!closeHover.hovered) root.activateTile(modelData)
                }
              }

              Text {
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.windowTitle(modelData)
                textFormat: Text.PlainText
                color: root.bar ? root.bar.barForeground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }

        Item {
          id: singleFrame
          visible: !groupTiles.visible
          anchors.fill: parent

          Image {
            width: Style.space(48)
            height: width
            anchors.centerIn: parent
            source: root.previewEntry && root.previewEntry.toplevel ? root.windowIcon(root.previewEntry.toplevel) : ""
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            fillMode: Image.PreserveAspectFit
            opacity: previewView.hasContent ? 0 : 0.5
          }

          ScreencopyView {
            id: previewView
            anchors.fill: parent
            captureSource: root.previewEntry && root.previewEntry.toplevel
              ? (root.previewEntry.toplevel.wayland
                  || (root.previewEntry.toplevel.real && root.previewEntry.toplevel.real.wayland)) : null
            live: previewCard.open
            paintCursor: false
          }
        }
      }

      Text {
        id: previewTitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.previewEntry ? root.previewCardTitle(root.previewEntry) : ""
        textFormat: Text.PlainText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  QtObject {
    id: menuOwner
    function close() { root.closeMenu() }
  }

  PopupCard {
    id: menuCard

    anchorItem: root.menuAnchor || root
    bar: root.bar
    owner: menuOwner
    triggerMode: "click"
    open: root.menuEntry !== null
    contentWidth: menuCard.fittedContentWidth(Style.space(170))
    contentHeight: menuCard.fittedContentHeight(menuColumn.implicitHeight)
    padding: Style.space(6)

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: root.menuItems

        Rectangle {
          id: menuRow
          required property var modelData
          width: menuColumn.width
          height: Style.space(26)
          radius: Style.space(4)
          color: itemHover.hovered
            ? Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.12) : "transparent"

          Behavior on color {
            ColorAnimation { duration: 100 }
          }

          HoverHandler { id: itemHover }

          TapHandler {
            onTapped: {
              var entry = root.menuEntry
              var action = menuRow.modelData.action
              root.closeMenu()
              if (entry && action) action(entry)
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.modelData.label
            textFormat: Text.PlainText
            color: menuRow.modelData.destructive ? Color.urgent
              : (root.bar ? root.bar.barForeground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
