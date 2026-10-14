/*****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
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
import QtQuick.Templates as T
import QtQml.Models
import QtQuick.Layouts


import VLC.Player
import VLC.PlayerControls
import VLC.MainInterface
import VLC.Style
import VLC.Widgets as Widgets
import VLC.Util

Flickable {
    id: root
    objectName: "toolbarComponentPalette"

    clip: true
    contentWidth: width
    contentHeight: components.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    // Geometry comes from Figma Customize Player 6587:18867. Labels and
    // draggable identifiers remain the existing control registry's values.
    readonly property real tileWidth: MainCtx.dp(86, VLCStyle.scale)
    readonly property real columnGap: MainCtx.dp(24, VLCStyle.scale)
    readonly property var orderedControls: {
        const order = [ControlListModel.WIDGET_SPACER, ControlListModel.WIDGET_DIVIDER,
                       ControlListModel.PLAYBACK_SPEED_BUTTON, ControlListModel.SKIP_FW_BUTTON,
                       ControlListModel.SKIP_BACK_BUTTON, ControlListModel.STOP_BUTTON,
                       ControlListModel.LOOP_BUTTON, ControlListModel.RANDOM_BUTTON,
                       ControlListModel.RECORD_BUTTON, ControlListModel.SNAPSHOT_BUTTON,
                       ControlListModel.PLAYLIST_BUTTON, ControlListModel.QUIT_BUTTON,
                       ControlListModel.INFO_BUTTON, ControlListModel.BOOKMARK_BUTTON]
        return PlayerControlbarControls.controlList.slice().sort((a, b) => {
            let ai = order.indexOf(a.id)
            let bi = order.indexOf(b.id)
            if (ai < 0) ai = order.length + PlayerControlbarControls.controlList.indexOf(a)
            if (bi < 0) bi = order.length + PlayerControlbarControls.controlList.indexOf(b)
            return ai - bi
        })
    }

    property alias removeInfoRectVisible: removeInfoRect.visible
    signal controlDragStarted(int id)
    signal controlDragStopped(int id)

    T.ScrollBar.vertical: Widgets.ScrollBarExt { }
    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    property Component implicitFlickableScrollHandler: DefaultFlickableScrollHandler { }
    property FlickableScrollHandler scrollHandler: interactive
        ? implicitFlickableScrollHandler.createObject(null, { target: root }) : null

    DropArea {
        anchors.fill: parent
        z: 3
        onDropped: (drop) => {
            if (!drop.source || drop.source.objectName === "buttonsList") return
            drop.source.dndView.model.remove(drop.source.DelegateModel.itemsIndex)
            drop.accept(Qt.MoveAction)
        }
    }

    Rectangle {
        id: removeInfoRect
        anchors.fill: parent
        z: 2
        visible: false
        opacity: 0.9
        color: theme.bg.primary
        border.color: theme.accent
        border.width: VLCStyle.border
        Text {
            anchors.centerIn: parent
            text: VLCIcons.del
            font.pixelSize: VLCStyle.icon_xlarge
            font.family: VLCIcons.fontFamily
            color: theme.accent
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.DragMoveCursor }
    }

    GridLayout {
        id: components
        width: root.width
        columns: Math.max(1, Math.floor((width + root.columnGap) / (root.tileWidth + root.columnGap)))
        columnSpacing: root.columnGap
        rowSpacing: MainCtx.dp(38, VLCStyle.scale)

        Repeater {
            model: root.orderedControls
            delegate: MouseArea {
                id: tile
                required property var modelData
                Layout.preferredWidth: root.tileWidth
                Layout.maximumWidth: root.tileWidth
                Layout.preferredHeight: label.implicitHeight + MainCtx.dp(48, VLCStyle.scale)
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                objectName: "buttonsList"
                hoverEnabled: true
                cursorShape: Qt.OpenHandCursor
                drag.target: buttonDragItem
                drag.smoothed: false
                readonly property int mIndex: modelData.id
                Accessible.name: modelData.text

                drag.onActiveChanged: {
                    if (drag.active) {
                        root.controlDragStarted(mIndex)
                        buttonDragItem.text = modelData.label
                        buttonDragItem.Drag.source = this
                        buttonDragItem.Drag.start()
                    } else {
                        buttonDragItem.Drag.drop()
                        root.controlDragStopped(mIndex)
                    }
                }
                onPressed: (mouse) => {
                    const pos = mapToItem(buttonDragItem.parent, mouse.x, mouse.y)
                    buttonDragItem.x = pos.x + VLCStyle.dragDelta
                    buttonDragItem.y = pos.y + VLCStyle.dragDelta
                }

                Canvas {
                    id: handle
                    width: MainCtx.dp(32, VLCStyle.scale)
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    property color stroke: tile.containsMouse ? theme.accent : theme.fg.secondary
                    onStrokeChanged: requestPaint()
                    onPaint: {
                        const painter = getContext("2d")
                        painter.clearRect(0, 0, width, height)
                        painter.strokeStyle = stroke
                        painter.lineWidth = VLCStyle.border
                        painter.setLineDash([3 * VLCStyle.scale, 3 * VLCStyle.scale])
                        painter.strokeRect(0.5, 0.5, width - 1, height - 1)
                    }
                    EditorDummyButton {
                        anchors.centerIn: parent
                        width: VLCStyle.icon_normal
                        height: width
                        color: theme.fg.secondary
                        font.pixelSize: VLCStyle.icon_normal
                        text: tile.modelData.label
                        visible: tile.mIndex !== ControlListModel.WIDGET_DIVIDER
                    }
                    Loader {
                        anchors.centerIn: parent
                        width: VLCStyle.icon_normal
                        height: width
                        source: tile.mIndex === ControlListModel.WIDGET_DIVIDER
                            ? PlayerControlbarControls.control(tile.mIndex).source : ""
                        onLoaded: {
                            item.paintOnly = true
                            item.enabled = false
                        }
                    }
                }
                Text {
                    id: label
                    anchors.top: handle.bottom
                    anchors.topMargin: MainCtx.dp(16, VLCStyle.scale)
                    width: parent.width
                    text: tile.modelData.text
                    color: theme.fg.secondary
                    font.pixelSize: MainCtx.dp(14, VLCStyle.scale)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
