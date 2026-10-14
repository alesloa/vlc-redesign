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
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets

Widgets.PageExt {
    id: root

    title: qsTr("Albums")
    // A pinned album selects and expands the existing live album view.
    property var albumId
    property int pendingAlbumIndex: -1
    function revealAlbum() {
        if (!albumId || !albumId.isValid()) return
        const requested = albumId.toString()
        albumsView.model.getIndexFromId(albumId).then(function(index) {
            if (root.albumId && root.albumId.toString() === requested) {
                root.pendingAlbumIndex = index
                root.applyAlbumSelection()
            }
        }, function() {})
    }
    function applyAlbumSelection() {
        const view = albumsView.currentItem
        if (pendingAlbumIndex < 0 || !view || view.currentIndex === undefined) return
        const index = pendingAlbumIndex
        pendingAlbumIndex = -1
        albumsView.initialIndex = index
        albumsView.selectionModel.updateSelection(Qt.NoModifier, view.currentIndex, index)
        view.currentIndex = index
        view.positionViewAtIndex(index, ItemView.Contain)
        if (MainCtx.gridView && typeof view.switchExpandItem === "function")
            view.switchExpandItem(index)
    }
    onAlbumIdChanged: revealAlbum()

    MusicAlbums {
        id: albumsView
        anchors.fill: parent

        focus: true

        searchPattern: root.search.pattern
        sortCriteria: root.sort.criteria
        sortOrder: root.sort.order

        displayMarginBeginning: root.displayMarginBeginning
        displayMarginEnd: root.displayMarginEnd

        enableBeginningFade: root.enableBeginningFade
        enableEndFade: root.enableEndFade

        onCurrentIndexChanged: if (History.viewProp) History.viewProp.initialIndex = currentIndex
        onCurrentItemChanged: Qt.callLater(root.applyAlbumSelection)
    }

}
