/*****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
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


import VLC.Widgets as Widgets
import VLC.Style
import VLC.Player
import VLC.Util

Widgets.IconToolButton {
    id: root

    // Proprerties

    property bool audioTracks: false
    property int initialTab: audioTracks ? 1 : 0

    readonly property var _parentItem: {
        if ((typeof rootPlayer !== 'undefined') && (rootPlayer !== null))
            return rootPlayer
        else
            return g_mainDisplay
    }

    // Signals

    signal requestLockUnlockAutoHide(bool lock)
    signal menuOpened(var menu)

    // Settings

    text: audioTracks ? VLCIcons.volume_high : VLCIcons.audiosub
    iconSource: audioTracks ? "qrc:///redesign/icons/audio.svg" : "qrc:///redesign/icons/subtitles.svg"

    enabled: menuLoader.status === Loader.Ready

    description: audioTracks ? qsTr("Audio") : qsTr("Languages and tracks")

    AccessibleCompat.id: audioTracks ? "audioTracksButton" : "langButton"

    // Events

    onClicked: {
        menuLoader.item.initialTab = initialTab
        menuLoader.item.open()
    }

    // Children

    Loader {
        id: menuLoader

        sourceComponent: TracksMenu {
            id: menu

            parent: root._parentItem

            x: sideAligned ? Math.max(0, parent.width - width - VLCStyle.margin_small)
                           : VLCStyle.margin_small
            y: sideAligned ? panelTop : Math.max(panelTop, panelBottom - height - VLCStyle.margin_small)
            z: 1

            focus: true

            colorContext.palette: root.colorContext.palette

            onOpened: {
                root.requestLockUnlockAutoHide(true)
                root.menuOpened(menu)
                menu.contentItem.forceActiveFocus(Qt.PopupFocusReason)
            }

            onClosed: {
                root.requestLockUnlockAutoHide(false)
                root.forceActiveFocus()
                root.menuOpened(null)
            }
        }
    }

    function forceUnlock() {
        if((menuLoader)&&(menuLoader.item))
            menuLoader.item.close()
    }
}
