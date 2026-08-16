import QtQuick

Item {
  id: root
  property real iconSize: 11
  property color color: "white"
  width: iconSize
  height: iconSize

  Canvas {
    id: mark
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.strokeStyle = root.color
      ctx.lineWidth = Math.max(1.15, width * 0.105)
      ctx.lineCap = "square"
      ctx.lineJoin = "miter"

      ctx.beginPath()
      ctx.moveTo(width * 0.09, height * 0.19)
      ctx.lineTo(width * 0.28, height * 0.19)
      ctx.lineTo(width * 0.50, height * 0.50)
      ctx.lineTo(width * 0.28, height * 0.81)
      ctx.lineTo(width * 0.09, height * 0.81)
      ctx.lineTo(width * 0.31, height * 0.50)
      ctx.closePath()
      ctx.stroke()

      ctx.beginPath()
      ctx.moveTo(width * 0.91, height * 0.19)
      ctx.lineTo(width * 0.72, height * 0.19)
      ctx.lineTo(width * 0.50, height * 0.50)
      ctx.lineTo(width * 0.72, height * 0.81)
      ctx.lineTo(width * 0.91, height * 0.81)
      ctx.lineTo(width * 0.69, height * 0.50)
      ctx.closePath()
      ctx.stroke()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  onColorChanged: mark.requestPaint()
}
