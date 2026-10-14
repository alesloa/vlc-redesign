/*****************************************************************************
 * Copyright (C) 2020 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
import QtQuick
import QtQuick.Layouts

import VLC.MainInterface
import VLC.Style

// NOTE: Attached pointing tool tip must be used if the popup type is `Popup.Window`.
ToolTipExt {
    id: pointingTooltip

    margins: 0
    padding: hasPreview ? VLCStyle.dp(10, VLCStyle.scale) : VLCStyle.margin_xxsmall
    radius: VLCStyle.dp(hasPreview ? 14 : 6, VLCStyle.scale)

    height: implicitHeight + background.arrowHeight
    bottomInset: height - implicitHeight

    implicitHeight: (implicitContentHeight + topPadding + bottomPadding)

    x: _x
    y: _pos.y - (implicitHeight + arrowArea.implicitHeight + VLCStyle.dp(7.5, VLCStyle.scale))

    readonly property real _x: _pos.x - (width / 2)
    property point pos
    property point _pos
    property url imageSource
    readonly property bool hasPreview: imageSource.toString().length > 0 && previewImage.status === Image.Ready
    // Source: Figma seek tooltip 2151:9673 and its 252×142 image. The image
    // source is an actual current-media thumbnail produced by VLC.
    readonly property real previewWidth: Math.min(VLCStyle.dp(252, VLCStyle.scale),
        Math.max(VLCStyle.dp(120, VLCStyle.scale), (MainCtx.intfMainWindow?.width ?? 272) - 2 * VLCStyle.dp(10, VLCStyle.scale)))

    contentItem: ColumnLayout {
        spacing: VLCStyle.dp(10, VLCStyle.scale)
        ImageExt {
            id: previewImage
            visible: pointingTooltip.hasPreview
            Layout.preferredWidth: pointingTooltip.previewWidth
            Layout.preferredHeight: pointingTooltip.previewWidth * 142 / 252
            implicitWidth: pointingTooltip.previewWidth
            implicitHeight: pointingTooltip.previewWidth * 142 / 252
            source: pointingTooltip.imageSource
            radius: VLCStyle.dp(4, VLCStyle.scale)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            id: contentText
            Layout.fillWidth: true
            text: pointingTooltip.text
            font: pointingTooltip.hasPreview ? Qt.font({
                family: pointingTooltip.font.family,
                weight: pointingTooltip.font.weight,
                italic: pointingTooltip.font.italic,
                pixelSize: VLCStyle.dp(15, VLCStyle.scale)
            }) : pointingTooltip.font
            color: pointingTooltip.colorContext.fg.primary
            wrapMode: Text.WordWrap

            // Preserve ToolTipExt's existing independent-window behavior on
            // Windows when this component supplies richer tooltip content.
            property QtWindow _lastWindowForNoRedirectionSurface
            Component.onCompleted: {
                if (MainCtx.createWindowWithoutRedirectionSurface) {
                    Window.windowChanged.connect(this, () => {
                        if (Window.window && Window.window !== MainCtx.intfMainWindow &&
                                Window.window !== contentText._lastWindowForNoRedirectionSurface) {
                            MainCtx.createWindowWithoutRedirectionSurface(Window.window)
                            contentText._lastWindowForNoRedirectionSurface = Window.window
                        }
                    })
                }
            }
        }
    }

    // We do not want to respect `pos` until it becomes relevant:
    onAboutToShow: {
        _pos = Qt.binding(() => { return pointingTooltip.pos })
    }

    onAboutToHide: {
        _pos = pos
    }

    background: Rectangle {
        border.color: pointingTooltip.colorContext.border
        color: pointingTooltip.colorContext.bg.primary
        radius: pointingTooltip.radius
        border.pixelAligned: (radius < Number.EPSILON)

        readonly property real arrowHeight: arrow.implicitHeight + border.width

        Item {
            id: arrowArea

            z: 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.bottom
            anchors.topMargin: -(parent.border.width)

            implicitHeight: arrow.implicitHeight * Math.sqrt(2) / 2

            clip: true

            Rectangle {
                id: arrow

                anchors.horizontalCenter: parent.horizontalCenter
                // NOTE: The offset is also set with independent window popup, because the position
                //       may still be clamped due to screen geometry:
                anchors.horizontalCenterOffset: (pointingTooltip._x - pointingTooltip.x)
                anchors.verticalCenter: parent.top

                implicitWidth: VLCStyle.dp(10, VLCStyle.scale)
                implicitHeight: VLCStyle.dp(10, VLCStyle.scale)

                rotation: 45

                color: pointingTooltip.colorContext.bg.primary
                border.color: pointingTooltip.colorContext.border
                border.pixelAligned: (radius < Number.EPSILON)
            }
        }
    }
}
