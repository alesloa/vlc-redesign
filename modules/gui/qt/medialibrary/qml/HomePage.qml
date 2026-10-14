/******************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
 *
 * Author: Ash <ashutoshv191@gmail.com>
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
 ******************************************************************************/
import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtQuick.Layouts

import VLC.MediaLibrary

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Style

Widgets.PageExt {
    id: root

    property var pagePrefix: [] // behave like a Page

    property var sortModel: [
        { text: qsTr("Alphabetic"), criteria: "title" },
        { text: qsTr("Duration"), criteria: "duration" }
    ]

    title: qsTr("Home")

    hasGridListMode: true

    isSearchable: true
    // Actual entries represented in this pane, including external-media history.
    displayedItemCount: continueWatchingRow.model.count + listenAgainRow.model.count
        + frequentFolderRow.collectionModel.count + frequentPlaylistRow.collectionModel.count
        + frequentArtistRow.collectionModel.count + favoritesRow.model.count
        + newVideoRow.model.count + newMusicRow.model.count + streamHistory.count

    property real listCoverHeight: VLCStyle.listAlbumCover_height
    property real listCoverWidth: VLCStyle.listAlbumCover_width
    property real listCoverRadius: VLCStyle.listAlbumCover_radius

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    signal seeAllButtonClicked(string name, int reason)

    function positionContentAtBeginning() {
        contentYBehavior.enabled = true
        flickable.contentY = -flickable.originY
        contentYBehavior.enabled = false
    }

    function setCurrentItemFocus(reason) {
        const rows = [continueWatchingRow, listenAgainRow, frequentFolderRow, frequentPlaylistRow,
                      frequentArtistRow, favoritesRow, newVideoRow, newMusicRow, streamsRow]
        const row = rows.find(item => item.visible && item.focus) ?? rows.find(item => item.visible)
        if (row) row.setCurrentItemFocus(reason)
        else coneNButtons.forceActiveFocus(reason)
    }

    contentItem: Flickable {
        id: flickable

        implicitWidth: Math.max(coneNButtons.implicitWidth, mediaRows.implicitWidth)
        implicitHeight: _hasMedias ? mediaRows.implicitHeight : coneNButtons.implicitHeight

        contentWidth: width
        contentHeight: _hasMedias ? mediaRows.implicitHeight
                                  : height - topMargin - bottomMargin

        flickableDirection: Flickable.AutoFlickIfNeeded

        boundsBehavior: Flickable.StopAtBounds

        // FIXME: make the media rows positioners consider the flickable margins when adjusting flickable `contentY`.
        bottomMargin: VLCStyle.margin_large

        pixelAligned: (MainCtx.qtVersion() >= MainCtx.qtVersionCheck(6, 2, 5)) // QTBUG-103996
                      && (Screen.pixelDensity >= VLCStyle.highPixelDensityThreshold) // no need for sub-pixel alignment with high pixel density

        property bool _hasMedias: true

        Binding on _hasMedias {
            when: !continueWatchingRow.model.loading && !favoritesRow.model.loading
                  && !newVideoRow.model.loading && !newMusicRow.model.loading && !listenAgainRow.model.loading
            value: continueWatchingRow.visible || favoritesRow.visible
                   || newVideoRow.visible || newMusicRow.visible || listenAgainRow.visible
                   || frequentFolderRow.visible || frequentPlaylistRow.visible || frequentArtistRow.visible || streamsRow.visible
            restoreMode: Binding.RestoreNone
        }

        T.ScrollBar.vertical: Widgets.ScrollBarExt {}

        // This behavior allows to have similar "smooth" animation
        // that Qt views have with `highlightFollowsCurrentItem`.
        Behavior on contentY {
            id: contentYBehavior

            enabled: false

            // NOTE: Usage of `SmoothedAnimation` is intentional here.
            SmoothedAnimation {
                duration: VLCStyle.duration_veryLong
                easing.type: Easing.InOutSine
            }
        }

        property Component implicitFlickableScrollHandler: DefaultFlickableScrollHandler { }

        // NOTE: This property can be set to null to prevent using a scroll handler:
        property FlickableScrollHandler scrollHandler: {
            if (interactive) {
                // JS ownership:
                return implicitFlickableScrollHandler.createObject(null, { target: flickable })
            } else {
                return null
            }
        }

        Component.onCompleted: {
            if (!usingTouch) {
                // Flickable filters child mouse events for flicking (even when
                // the delegate is grabbed). However, this is not a useful
                // feature for non-touch cases, so disable it here and enable
                // it if touch is detected through the hover handler:
                MainCtx.setFiltersChildMouseEvents(flickable, false)
            }
        }

        readonly property bool usingTouch: MainCtx.usingTouch

        onUsingTouchChanged: {
            if (usingTouch)
                MainCtx.setFiltersChildMouseEvents(flickable, true)
            // We do not disable filtering child mouse events
            // because Qt currently has a bug that the flickable
            // jumps when it is enabled again later on.
        }

        NoMedialibHome.ConeNButtons {
            id: coneNButtons

            focus: true
            visible: !flickable._hasMedias

            orientation: flickable._hasMedias ? Qt.Horizontal : Qt.Vertical

            anchors.centerIn: flickable._hasMedias ? undefined : parent
            anchors.top: flickable._hasMedias ? parent.top : undefined
            anchors.left: flickable._hasMedias ? parent.left : undefined
            anchors.leftMargin: flickable._hasMedias ? newVideoRow.contentLeftMargin : 0

            Navigation.parentItem: root
            Navigation.upItem: root.header
            Navigation.downItem: mediaRows

            onActiveFocusChanged: {
                contentYBehavior.enabled = true
                Helpers.positionFlickableToContainItem(flickable, this)
                contentYBehavior.enabled = false
            }
        }

        Widgets.NavigableCol {
            id: mediaRows

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right

            spacing: 0 // NOTE: We depend on the top padding of view header currently.

            Navigation.parentItem: root
            Navigation.upItem: root.header

            HomeSectionHeader {
                visible: continueWatchingRow.visible
                text: qsTr("Continue Watching")
                view: continueWatchingRow
                seeAllButton.visible: true

                onSeeAllButtonClicked: function (reason) {
                    root.seeAllButtonClicked("continueWatching", reason)
                }
            }

            VideoAll {
                id: continueWatchingRow

                AccessibleCompat.id: "continueWatching"

                anchors.left: parent.left
                anchors.right: parent.right

                height: currentItem?.contentHeight ?? implicitHeight

                visible: model.count !== 0

                headerPositioning: ListView.InlineHeader
                enableBeginningFade: false
                enableEndFade: false
                sectionProperty: ""

                interactive: false

                emptyLabel: null

                // FIXME: `ExpandGridView` causes extreme performance degradation when `reuseItems`
                //        is true and items provided by the model change (#29084).
                reuseItems: !MainCtx.gridView

                listCoverWidth: root.listCoverWidth
                listCoverHeight: root.listCoverHeight
                listCoverRadius: root.listCoverRadius

                Navigation.parentItem: mediaRows

                model: MLRecentVideoModel {
                    ml: MediaLib

                    sortCriteria: root.sort.criteria
                    sortOrder: root.sort.order
                    searchPattern: root.search.pattern

                    // FIXME: Make limit 0 load no items, instead of loading all items.
                    limit: MainCtx.gridView ? Math.max(continueWatchingRow.currentItem?.nbItemPerRow ?? null, 1) : 5
                }

                contextMenu: MLContextMenu {
                    model: continueWatchingRow.model

                    showPlayAsAudioAction: true
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        contentYBehavior.enabled = true
                        Helpers.positionFlickableToContainItem(flickable, item ?? this)
                        contentYBehavior.enabled = false
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        if (item) {
                            contentYBehavior.enabled = true
                            Helpers.positionFlickableToContainItem(flickable, item)
                            contentYBehavior.enabled = false
                        }
                    }
                }
            }

            // Source: Figma Home / Listen Again; entries use VLC audio history.
            HomeSectionHeader {
                text: qsTr("Listen Again")
                visible: listenAgainRow.visible
                view: listenAgainRow
                seeAllButton.visible: true

                onSeeAllButtonClicked: function (reason) {
                    root.seeAllButtonClicked("listenAgain", reason)
                }
            }

            MediaView {
                id: listenAgainRow

                AccessibleCompat.id: "listenAgain"

                anchors.left: parent.left
                anchors.right: parent.right

                height: currentItem?.contentHeight ?? implicitHeight

                visible: model.count !== 0

                listHeaderPositioning: ListView.InlineHeader
                enableBeginningFade: false
                enableEndFade: false
                listSectionProperty: ""

                interactive: false

                emptyLabel: null

                // FIXME: `ExpandGridView` causes extreme performance degradation when `reuseItems`
                //        is true and items provided by the model change (#29084).
                reuseItems: !MainCtx.gridView

                listCoverWidth: root.listCoverWidth
                listCoverHeight: root.listCoverHeight
                listCoverRadius: root.listCoverRadius

                Navigation.parentItem: mediaRows

                model: MLRecentAudioModel {
                    ml: MediaLib

                    sortCriteria: root.sort.criteria
                    sortOrder: root.sort.order
                    searchPattern: root.search.pattern

                    // FIXME: Make limit 0 load no items, instead of loading all items.
                    limit: MainCtx.gridView ? Math.max(listenAgainRow.currentItem?.nbItemPerRow ?? null, 1) : 5
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        contentYBehavior.enabled = true
                        Helpers.positionFlickableToContainItem(flickable, item ?? this)
                        contentYBehavior.enabled = false
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        if (item) {
                            contentYBehavior.enabled = true
                            Helpers.positionFlickableToContainItem(flickable, item)
                            contentYBehavior.enabled = false
                        }
                    }
                }
            }

            CollectionHomeRow {
                id: frequentFolderRow
                width: parent.width
                collectionModel: LibraryPins.frequentFolders
                heading: qsTr("Frequently Visited Folders")
                iconSource: "qrc:///redesign/icons/folder.svg"
                mirrorIcon: true
                fullPath: ["video", "all"]
            }
            CollectionHomeRow {
                id: frequentPlaylistRow
                width: parent.width
                collectionModel: LibraryPins.frequentPlaylists
                heading: qsTr("Frequently Visited Playlists")
                iconSource: "qrc:///redesign/icons/playlists.svg"
                fullPath: ["video", "playlists"]
            }
            CollectionHomeRow {
                id: frequentArtistRow
                width: parent.width
                collectionModel: LibraryPins.frequentArtists
                heading: qsTr("Frequently Listened Artists")
                iconSource: "qrc:///redesign/icons/library-artist.svg"
                fullPath: ["music", "artists"]
            }
            HomeSectionHeader {
                visible: favoritesRow.visible
                text: qsTr("Favorites")
                view: favoritesRow
                seeAllButton.visible: true

                onSeeAllButtonClicked: function (reason) {
                    root.seeAllButtonClicked("favorites", reason)
                }
            }

            MediaView {
                id: favoritesRow

                AccessibleCompat.id: "favourites"

                anchors.left: parent.left
                anchors.right: parent.right

                height: currentItem?.contentHeight ?? implicitHeight

                visible: model.count !== 0

                listHeaderPositioning: ListView.InlineHeader
                enableBeginningFade: false
                enableEndFade: false
                listSectionProperty: ""

                interactive: false

                emptyLabel: null

                // FIXME: `ExpandGridView` causes extreme performance degradation when `reuseItems`
                //        is true and items provided by the model change (#29084).
                reuseItems: !MainCtx.gridView

                listCoverWidth: root.listCoverWidth
                listCoverHeight: root.listCoverHeight
                listCoverRadius: root.listCoverRadius

                Navigation.parentItem: mediaRows

                model: MLMediaModel {
                    favoriteOnly: true

                    ml: MediaLib

                    sortCriteria: root.sort.criteria || "insertion"
                    sortOrder: root.sort.order
                    searchPattern: root.search.pattern

                    // FIXME: Make limit 0 load no items, instead of loading all items.
                    limit: MainCtx.gridView ? Math.max(favoritesRow.currentItem?.nbItemPerRow ?? null, 1) : 5
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        contentYBehavior.enabled = true
                        Helpers.positionFlickableToContainItem(flickable, item ?? this)
                        contentYBehavior.enabled = false
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        if (item) {
                            contentYBehavior.enabled = true
                            Helpers.positionFlickableToContainItem(flickable, item)
                            contentYBehavior.enabled = true
                        }
                    }
                }
            }

            HomeSectionHeader {
                text: qsTr("New Videos")
                visible: newVideoRow.visible
                view: newVideoRow
                seeAllButton.visible: true

                onSeeAllButtonClicked: function (reason) {
                    root.seeAllButtonClicked("newVideo", reason)
                }
            }

            VideoAll {
                id: newVideoRow

                AccessibleCompat.id: "newVideo"

                anchors.left: parent.left
                anchors.right: parent.right

                height: currentItem?.contentHeight ?? implicitHeight

                visible: model.count !== 0

                headerPositioning: ListView.InlineHeader
                enableBeginningFade: false
                enableEndFade: false
                sectionProperty: ""

                interactive: false

                emptyLabel: null

                // FIXME: `ExpandGridView` causes extreme performance degradation when `reuseItems`
                //        is true and items provided by the model change (#29084).
                reuseItems: !MainCtx.gridView

                listCoverWidth: root.listCoverWidth
                listCoverHeight: root.listCoverHeight
                listCoverRadius: root.listCoverRadius

                Navigation.parentItem: mediaRows

                model: MLVideoModel {
                    ml: MediaLib

                    sortCriteria: root.sort.criteria || "insertion"
                    sortOrder: root.sort.order
                    searchPattern: root.search.pattern

                    // FIXME: Make limit 0 load no items, instead of loading all items.
                    limit: MainCtx.gridView ? Math.max(newVideoRow.currentItem?.nbItemPerRow ?? null, 1) : 5
                }

                contextMenu: MLContextMenu {
                    model: newVideoRow.model

                    showPlayAsAudioAction: true
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        contentYBehavior.enabled = true
                        Helpers.positionFlickableToContainItem(flickable, item ?? this)
                        contentYBehavior.enabled = false
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        if (item) {
                            contentYBehavior.enabled = true
                            Helpers.positionFlickableToContainItem(flickable, item)
                            contentYBehavior.enabled = false
                        }
                    }
                }
            }

            HomeSectionHeader {
                text: qsTr("New Music")
                visible: newMusicRow.visible
                view: newMusicRow
                seeAllButton.visible: true

                onSeeAllButtonClicked: function (reason) {
                    root.seeAllButtonClicked("newMusic", reason)
                }
            }

            MediaView {
                id: newMusicRow

                AccessibleCompat.id: "newMusic"

                anchors.left: parent.left
                anchors.right: parent.right

                height: currentItem?.contentHeight ?? implicitHeight

                visible: model.count !== 0

                listHeaderPositioning: ListView.InlineHeader
                enableBeginningFade: false
                enableEndFade: false
                listSectionProperty: ""

                interactive: false

                emptyLabel: null

                // FIXME: `ExpandGridView` causes extreme performance degradation when `reuseItems`
                //        is true and items provided by the model change (#29084).
                reuseItems: !MainCtx.gridView

                listCoverWidth: root.listCoverWidth
                listCoverHeight: root.listCoverHeight
                listCoverRadius: root.listCoverRadius

                Navigation.parentItem: mediaRows

                model: MLAudioModel {
                    ml: MediaLib

                    sortCriteria: root.sort.criteria || "insertion"
                    sortOrder: root.sort.order
                    searchPattern: root.search.pattern

                    // FIXME: Make limit 0 load no items, instead of loading all items.
                    limit: MainCtx.gridView ? Math.max(newMusicRow.currentItem?.nbItemPerRow ?? null, 1) : 5
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        contentYBehavior.enabled = true
                        Helpers.positionFlickableToContainItem(flickable, item ?? this)
                        contentYBehavior.enabled = false
                    }
                }

                onCurrentIndexChanged: {
                    if (activeFocus) {
                        const item = currentItem?.currentItem ?? currentItem?._getItem(currentIndex) // FIXME: `ExpandGridView` does not have `currentItem`.
                        if (item) {
                            contentYBehavior.enabled = true
                            Helpers.positionFlickableToContainItem(flickable, item)
                            contentYBehavior.enabled = false
                        }
                    }
                }
            }

            Column {
                id: streamsRow
                width: parent.width
                spacing: VLCStyle.margin_small
                visible: streamHistory.count > 0
                Navigation.parentItem: mediaRows
                function setCurrentItemFocus(reason) { const item = streamItems.itemAt(0); if (item) item.forceActiveFocus(reason) }
                MLUrlModel { id: streamHistory; ml: MediaLib; limit: 3; searchPattern: root.search.pattern }
                RowLayout {
                    width: parent.width
                    Widgets.SubtitleLabel {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: qsTr("Network")
                        font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
                        font.weight: Font.Normal
                        color: theme.fg.secondary
                    }
                    Widgets.IconToolButton {
                        text: VLCIcons.chevron_right
                        iconSource: "qrc:///redesign/icons/home-chevron.svg"
                        mirrorIcon: true
                        description: qsTr("Network")
                        onClicked: History.push(["discover", "url"])
                    }
                }
                Repeater {
                    id: streamItems
                    model: streamHistory
                    T.ItemDelegate {
                        id: streamDelegate
                        required property int index
                        required property var model
                        activeFocusOnTab: true
                        Navigation.parentItem: streamsRow
                        Navigation.upItem: streamItems.itemAt(index - 1)
                        Navigation.downItem: streamItems.itemAt(index + 1)
                        Keys.onPressed: event => Navigation.defaultKeyAction(event)
                        width: streamsRow.width
                        height: VLCStyle.dp(32, VLCStyle.scale)
                        hoverEnabled: true
                        Accessible.name: model.url
                        contentItem: Widgets.ListLabel { text: streamDelegate.model.url; color: theme.fg.primary }
                        background: Widgets.AnimatedBackground { color: streamDelegate.hovered || streamDelegate.visualFocus ? theme.bg.highlight : "transparent"; border.color: streamDelegate.visualFocus ? theme.visualFocus : "transparent"; radius: VLCStyle.dp(4, VLCStyle.scale) }
                        onClicked: MediaLib.addAndPlay(model.id)
                    }
                }
            }
        }
    }

    // Figma6261:15648/6272:13895:20px regular heading,5px chevron gap.
    component HomeSectionHeader: T.Pane {
        id: sectionHeader
        required property Item view
        property alias text: heading.text
        property alias seeAllButton: more
        signal seeAllButtonClicked(int reason)
        width: view.width
        implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                                implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                                 implicitContentHeight + topPadding + bottomPadding)
        leftPadding: view.contentLeftMargin ?? 0
        rightPadding: view.contentRightMargin ?? 0
        topPadding: VLCStyle.dp(40, VLCStyle.scale)
        bottomPadding: VLCStyle.dp(20, VLCStyle.scale)
        Navigation.parentItem: view
        Navigation.navigable: more.visible
        contentItem: RowLayout {
            spacing: VLCStyle.dp(5, VLCStyle.scale)
            Widgets.LabelExt {
                id: heading
                font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
                font.weight: Font.Normal
                color: theme.fg.secondary
            }
            Widgets.IconToolButton {
                id: more
                Layout.preferredHeight: VLCStyle.dp(24, VLCStyle.scale)
                Layout.preferredWidth: VLCStyle.dp(24, VLCStyle.scale)
                iconSource: "qrc:///redesign/icons/home-chevron.svg"
                mirrorIcon: true
                text: VLCIcons.chevron_right
                description: heading.text
                focus: true
                Navigation.parentItem: sectionHeader
                Binding on focusReason { value: sectionHeader.focusReason }
                onClicked: sectionHeader.seeAllButtonClicked(focusReason)
            }
            Item { Layout.fillWidth: true }
        }
    }

    component CollectionHomeRow: FocusScope {
        id: collectionRow
        required property var collectionModel
        required property string heading
        required property url iconSource
        property bool mirrorIcon: false
        required property var fullPath
        readonly property var model: collectionModel
        implicitHeight: visible ? collectionContents.implicitHeight + VLCStyle.dp(60, VLCStyle.scale) : 0
        height: implicitHeight
        visible: collectionModel.count > 0
        Navigation.parentItem: mediaRows
        function itemAtIndex(index) { return cards.itemAt(index) }
        function setCurrentItemFocus(reason) { const item = cards.itemAt(0); if (item) item.forceActiveFocus(reason) }
        onActiveFocusChanged: if (activeFocus) Helpers.positionFlickableToContainItem(flickable, this)
        Widgets.DragItem {
            id: collectionDrag
            view: collectionRow
            indexesFlat: true
            onRequestData: (indexes, resolve, reject) => {
                resolve(indexes.filter(index => index >= 0 && index < collectionRow.collectionModel.count)
                    .map(index => collectionRow.collectionModel.get(index)))
            }
            onRequestInputItems: (indexes, data, resolve, reject) => MediaLib.mlInputItem(data.map(row => row.mediaId), resolve)
        }
        Column {
            id: collectionContents
            x: continueWatchingRow.contentLeftMargin
            y: VLCStyle.dp(40, VLCStyle.scale)
            width: parent.width - continueWatchingRow.contentLeftMargin - continueWatchingRow.contentRightMargin
            spacing: VLCStyle.dp(20, VLCStyle.scale)
            RowLayout {
                width: parent.width
                Layout.minimumWidth: 0
                Widgets.SubtitleLabel {
                    Layout.minimumWidth: 0
                    text: collectionRow.heading
                    font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
                    font.weight: Font.Normal
                    color: theme.fg.secondary
                    elide: Text.ElideRight
                }
                Widgets.IconToolButton {
                    text: VLCIcons.chevron_right
                    iconSource: "qrc:///redesign/icons/home-chevron.svg"
                    mirrorIcon: true
                    description: collectionRow.heading
                    onClicked: History.push(collectionRow.fullPath)
                }
                Item { Layout.fillWidth: true }
            }
            Flow {
                width: parent.width
                spacing: VLCStyle.margin_normal
                Repeater {
                    id: cards
                    model: collectionRow.collectionModel
                    T.ItemDelegate {
                        id: card
                        required property int index
                        required property var model
                        hoverEnabled: true
                        width: MainCtx.gridView ? Math.min(VLCStyle.gridCover_music_width, collectionRow.width) : collectionRow.width
                        height: MainCtx.gridView ? Math.min(VLCStyle.gridCover_music_height, width) + VLCStyle.margin_small + titleText.implicitHeight : VLCStyle.dp(32, VLCStyle.scale)
                        padding: 0
                        Accessible.name: model.title
                        Navigation.parentItem: collectionRow
                        Keys.onPressed: event => {
                            const next = event.key === Qt.Key_Right ? index + 1 : event.key === Qt.Key_Left ? index - 1 : -1
                            if (next >= 0 && next < cards.count) { cards.itemAt(next).forceActiveFocus(Qt.TabFocusReason); event.accepted = true }
                            else Navigation.defaultKeyAction(event)
                        }
                        onClicked: {
                            const route = LibraryPins.route(model)
                            if (route) History.push(route.path, route.properties)
                        }
                        background: Widgets.AnimatedBackground {
                            color: card.visualFocus || card.hovered ? theme.bg.highlight : "transparent"
                            border.color: card.visualFocus ? theme.visualFocus : "transparent"
                            radius: VLCStyle.dp(4, VLCStyle.scale)
                        }
                        contentItem: Item {
                            Rectangle {
                                id: picture
                                width: MainCtx.gridView ? parent.width : VLCStyle.dp(32, VLCStyle.scale)
                                height: MainCtx.gridView ? Math.min(VLCStyle.gridCover_music_height, width) : width
                                color: theme.bg.secondary
                                radius: VLCStyle.dp(4, VLCStyle.scale)
                                Image {
                                    anchors.fill: parent
                                    visible: !!card.model.cover && card.model.kind !== "folder"
                                    source: visible ? card.model.cover : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: VLCStyle.dp(24, VLCStyle.scale)
                                    height: width
                                    visible: !card.model.cover || card.model.kind === "folder"
                                    mirror: collectionRow.mirrorIcon
                                    source: SVGColorImage.colorize(collectionRow.iconSource).any({"#8F8F8F": theme.fg.secondary}).uri()
                                }
                            }
                            Widgets.ListLabel {
                                id: titleText
                                x: MainCtx.gridView ? 0 : picture.width + VLCStyle.margin_small
                                y: MainCtx.gridView ? picture.height + VLCStyle.margin_small : (parent.height - height) / 2
                                width: parent.width - x
                                text: card.model.title
                                font.weight: Font.Normal
                                color: theme.fg.secondary
                            }
                            Widgets.ButtonExt {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                visible: card.hovered || activeFocus
                                text: LibraryPins.contains(card.model.mediaId) ? qsTr("Unpin") : qsTr("Pin")
                                onClicked: LibraryPins.toggle(card.model.mediaId)
                            }
                        }
                        DragHandler {
                            target: null
                            acceptedDevices: PointerDevice.AllDevices & ~PointerDevice.TouchScreen
                            onActiveChanged: {
                                if (active) { collectionDrag.indexes = [card.index]; collectionDrag.Drag.active = true }
                                else if (collectionDrag.Drag.active) collectionDrag.Drag.drop()
                            }
                        }
                    }
                }
            }
        }
    }
}
