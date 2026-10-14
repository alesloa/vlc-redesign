
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
import QtQuick.Templates as T
import VLC.MainInterface
import VLC.MediaLibrary
import VLC.Player
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets

ColumnLayout {
    id: root
    spacing: VLCStyle.margin_normal

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }
    // Source: VLC's existing bookmark model, including its time formatting and persisted names.
    MLBookmarkModel { id: bookmarks; ml: MediaLib; player: Player }

    RowLayout {
        Layout.fillWidth: true
        Widgets.CaptionLabel {
            Layout.fillWidth: true
            text: qsTr("%1 Bookmarks").arg(bookmarkView.count)
            color: theme.fg.secondary
        }
        Widgets.IconToolButton {
            text: VLCIcons.remove
            description: qsTr("Remove")
            enabled: bookmarkView.currentIndex >= 0 && bookmarkView.count > 0
            onClicked: bookmarks.remove([bookmarks.index(bookmarkView.currentIndex, 0)])
        }
        Widgets.IconToolButton {
            text: VLCIcons.add
            iconSource: "qrc:///redesign/icons/add.svg"
            description: qsTr("Add")
            enabled: Player.isStarted && Player.time.valid()
            onClicked: bookmarks.add()
        }
    }

    Widgets.ListViewExt {
        id: bookmarkView
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: bookmarks
        focus: true
        clip: true
        fadingEdge.backgroundColor: theme.bg.primary
        Accessible.name: qsTr("Bookmarks")
        onActionAtIndex: (index) => bookmarks.select(bookmarks.index(index, 0))
        Keys.onDeletePressed: {
            if (currentIndex >= 0 && count > 0)
                bookmarks.remove([bookmarks.index(currentIndex, 0)])
        }

        delegate: T.ItemDelegate {
            id: bookmarkDelegate
            width: bookmarkView.width
            height: VLCStyle.dp(42, VLCStyle.scale)
            property bool editing: false
            highlighted: bookmarkView.currentIndex === index
            onClicked: {
                bookmarkView.currentIndex = index
                bookmarks.select(bookmarks.index(index, 0))
            }
            contentItem: RowLayout {
                Widgets.ListLabel {
                    Layout.fillWidth: true
                    text: model.name
                    visible: !bookmarkDelegate.editing
                    color: theme.fg.primary
                }
                Widgets.TextFieldExt {
                    id: nameEditor
                    Layout.fillWidth: true
                    visible: bookmarkDelegate.editing
                    Accessible.name: model.name
                    selectByMouse: true
                    onVisibleChanged: if (visible) { text = model.name; forceActiveFocus(Qt.OtherFocusReason); selectAll() }
                    onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
                    Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
                    onEditingFinished: { if (bookmarkDelegate.editing) model.name = text; bookmarkDelegate.editing = false }
                    Keys.onEscapePressed: { bookmarkDelegate.editing = false; bookmarkView.forceActiveFocus(Qt.OtherFocusReason) }
                }
                Widgets.CaptionLabel {
                    text: model.time
                    color: theme.fg.secondary
                }
            }
            background: Widgets.AnimatedBackground {
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: bookmarkDelegate.highlighted || bookmarkDelegate.hovered ? theme.bg.highlight : "transparent"
            }
            Navigation.parentItem: bookmarkView
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_F2) { editing = true; event.accepted = true }
            }
            TapHandler { onDoubleTapped: bookmarkDelegate.editing = true }
        }
    }
    Navigation.parentItem: parent
    onActiveFocusChanged: if (activeFocus) bookmarkView.setCurrentItemFocus(Qt.TabFocusReason)
}
