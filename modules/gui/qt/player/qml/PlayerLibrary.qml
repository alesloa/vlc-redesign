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
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQml.Models
import VLC.MainInterface
import VLC.MediaLibrary
import VLC.Player
import VLC.Playlist
import VLC.Dialogs
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets

// Compact Figma library: every row and image is supplied by VLC's live media-library models.
T.Pane {
    id: root

    readonly property var activeModel: insideCollection ? collectionKind === "audio" ? collectionAudioModel : collectionKind === "albums" ? collectionAlbumsModel : collectionKind === "playlist" ? collectionPlaylistModel : collectionModel : category === 1 ? foldersModel : category === 2 ? musicSection === 1 ? albumsModel : musicSection === 2 ? artistsModel : musicSection === 3 ? genresModel : audioModel : category === 3 ? streamsModel : category === 4 ? playlistsModel : recentModel
    readonly property bool audioRows: category === 2 && (!insideCollection || collectionKind === "audio")
    property var backHistory: []
    readonly property var categories: [qsTr("Home"), qsTr("Videos"), qsTr("Music"), qsTr("Network"), qsTr("Playlists"), qsTr("Recent")]
    property int category: 1
    property var collectionId
    property string collectionKind: "video"
    readonly property bool collectionRows: insideCollection ? collectionKind === "albums" : category === 1 || category === 4 || (category === 2 && musicSection > 0)
    property string collectionTitle: ""
    readonly property ColorContext colorContext: ColorContext {
        id: theme

        colorSet: ColorContext.View
    }
    property var forwardHistory: []
    property bool gridMode: false
    property bool searchVisible: false
    property bool insideCollection: false
    property int musicSection: 0
    readonly property var musicSections: [qsTr("Songs"), qsTr("Albums"), qsTr("Artists"), qsTr("Genres")]
    readonly property var pinnedIds: LibraryPins.serializedIds
    readonly property var sortActions: makeSortActions()
    // The caption counts actual entries represented by the current pane.
    readonly property int visibleItemCount: category === 0 && !insideCollection
        ? continueModel.count + listenAgainModel.count + homeStreamsModel.count
          + Math.min(3, LibraryPins.frequentFolders.count)
          + Math.min(3, LibraryPins.frequentPlaylists.count)
          + LibraryPins.frequentArtists.count
        : activeModel.count

    function setCurrentItemFocus(reason) {
        if (category === 0 && !insideCollection) homeSections.forceActiveFocus(reason)
        else if (gridMode) mediaGrid.forceActiveFocus(reason)
        else mediaList.setCurrentItemFocus(reason)
    }
    onActiveFocusChanged: if (activeFocus && Window.window?.activeFocusItem === root) setCurrentItemFocus(Qt.TabFocusReason)
    Keys.onPressed: event => Navigation.defaultKeyAction(event)

    signal requestClose
    signal requestFullView(var path, var properties)

    function activateIndex(index) {
        const source = activeModel;
        const collection = collectionRows;
        if (index < 0 || index >= source.count)
            return;
        source.getDataFlat([index], function (data) {
            if (root.activeModel === source && data.length > 0)
                root.activateMedia(data[0], collection);
        });
    }
    function activateMedia(data, collection) {
        if (collection) {
            LibraryPins.visit(data.id);
            remember();
            collectionKind = category === 4 ? "playlist" : category === 2 ? (!insideCollection && musicSection === 2 ? "albums" : "audio") : "video";
            collectionId = data.id;
            setCollectionId(data.id);
            collectionTitle = data.title || data.name || data.fileName || "";
            insideCollection = true;
        } else {
            MediaLib.addAndPlay(data.id);
        }
    }
    function activatePin(serialized, data) {
        LibraryPins.visit(data.mediaId);
        remember();
        if (serialized.startsWith("VLC_ML_PARENT_FOLDER") || serialized.startsWith("VLC_ML_PARENT_GROUP")) {
            category = 1;
            collectionKind = "video";
        } else if (serialized.startsWith("VLC_ML_PARENT_PLAYLIST")) {
            category = 4;
            collectionKind = "playlist";
        } else if (serialized.startsWith("VLC_ML_PARENT_ARTIST")) {
            category = 2;
            musicSection = 2;
            collectionKind = "albums";
        } else if (serialized.startsWith("VLC_ML_PARENT_ALBUM")) {
            category = 2;
            musicSection = 1;
            collectionKind = "audio";
        } else if (serialized.startsWith("VLC_ML_PARENT_GENRE")) {
            category = 2;
            musicSection = 3;
            collectionKind = "audio";
        } else {
            MediaLib.addAndPlay(data.mediaId);
            return;
        }
        collectionId = data.mediaId;
        collectionTitle = data.title;
        setCollectionId(collectionId);
        insideCollection = true;
    }
    function goBack() {
        if (backHistory.length === 0)
            return;
        forwardHistory = forwardHistory.concat([snapshot()]);
        const state = backHistory[backHistory.length - 1];
        backHistory = backHistory.slice(0, -1);
        restore(state);
    }
    function goForward() {
        if (forwardHistory.length === 0)
            return;
        backHistory = backHistory.concat([snapshot()]);
        const state = forwardHistory[forwardHistory.length - 1];
        forwardHistory = forwardHistory.slice(0, -1);
        restore(state);
    }
    function makeSortActions() {
        const entries = [];
        function add(text, criterion, order) {
            entries.push({
                text: text,
                action: function () {
                    root.activeModel.sortByColumn(criterion, order);
                }
            });
        }
        if ((insideCollection && (collectionKind === "video" || collectionKind === "playlist")) || category === 5) {
            add(qsTr("Unwatched First"), "playcount", Qt.AscendingOrder);
            add(qsTr("Watched First"), "playcount", Qt.DescendingOrder);
        }
        if ((category === 2 && musicSection === 0) || (insideCollection && (collectionKind === "video" || collectionKind === "audio")) || category === 5) {
            add(qsTr("Newest First"), "insertion", Qt.DescendingOrder);
            add(qsTr("Oldest First"), "insertion", Qt.AscendingOrder);
        }
        const titleCriterion = category === 2 && !insideCollection && musicSection >= 2 ? "name" : "title";
        add(qsTr("Title A-Z"), titleCriterion, Qt.AscendingOrder);
        add(qsTr("Title Z-A"), titleCriterion, Qt.DescendingOrder);
        if (audioRows && !collectionRows) {
            add(qsTr("Artist A-Z"), "main_artist", Qt.AscendingOrder);
            add(qsTr("Artist Z-A"), "main_artist", Qt.DescendingOrder);
            add(qsTr("Album A-Z"), "album_title", Qt.AscendingOrder);
            add(qsTr("Album Z-A"), "album_title", Qt.DescendingOrder);
            add(qsTr("Track Number Ascending"), "track_number", Qt.AscendingOrder);
            add(qsTr("Track Number Descending"), "track_number", Qt.DescendingOrder);
        }
        return entries;
    }
    function openCategory(index) {
        remember();
        category = index;
        insideCollection = false;
    }
    function popupContextMenu(indexes, position) {
        if (insideCollection && collectionKind === "playlist")
            playlistMenu.popup(indexes, position);
        else
            libraryMenu.popup(indexes, position);
    }
    function remember() {
        backHistory = backHistory.concat([snapshot()]);
        forwardHistory = [];
    }
    function restore(state) {
        if (state.insideCollection) LibraryPins.visit(state.collectionId);
        category = state.category;
        musicSection = state.musicSection;
        collectionKind = state.collectionKind;
        collectionTitle = state.collectionTitle;
        collectionId = state.collectionId;
        if (state.insideCollection)
            setCollectionId(state.collectionId);
        insideCollection = state.insideCollection;
    }
    function setCollectionId(id) {
        if (collectionKind === "playlist")
            collectionPlaylistModel.parentId = id;
        else if (collectionKind === "audio")
            collectionAudioModel.parentId = id;
        else if (collectionKind === "albums")
            collectionAlbumsModel.parentId = id;
        else
            collectionModel.parentId = id;
    }
    function showFullView() {
        let path = category === 0 ? ["home"] : category === 1 ? ["video", "all"] : category === 2 ? ["music", ["tracks", "albums", "artists", "genres"][musicSection]] : category === 3 ? ["discover", "url"] : category === 4 ? ["video", "playlists"] : ["home", "continueWatching"];
        let properties = {};
        if (insideCollection && collectionId) {
            // Resolve the current, actual collection through the same routes
            // used by the library rail; expansion must retain its source ID.
            const route = LibraryPins.route({
                kind: LibraryPins.kind(collectionId.toString()),
                mediaId: collectionId,
                title: collectionTitle
            });
            if (route) {
                path = route.path;
                properties = route.properties;
            }
        }
        requestFullView(path, properties);
    }
    function snapshot() {
        return {
            category: category,
            musicSection: musicSection,
            insideCollection: insideCollection,
            collectionKind: collectionKind,
            collectionTitle: collectionTitle,
            collectionId: collectionId
        };
    }

    padding: 0

    background: Rectangle {
        color: theme.bg.primary
        radius: 0
    }
    contentItem: RowLayout {
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: VLCStyle.dp(50, VLCStyle.scale)
            color: theme.bg.secondary

            Flickable {
                anchors.fill: parent
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                contentHeight: railIcons.height + VLCStyle.dp(16, VLCStyle.scale)
                contentWidth: width

                Column {
                    id: railIcons

                    spacing: VLCStyle.dp(14, VLCStyle.scale)
                    x: VLCStyle.dp(10, VLCStyle.scale)
                    y: VLCStyle.dp(8, VLCStyle.scale)

                    Repeater {
                        model: root.categories

                        Widgets.IconToolButton {
                            readonly property var files: ["home", "videos", "music", "network", "playlists", "recent"]
                            required property int index
                            required property string modelData
                            mirrorIcon: index === 0 || index === 2 || index === 3 || index === 5

                            Navigation.parentItem: root
                            checked: root.category === index
                            description: modelData
                            height: VLCStyle.dp(30, VLCStyle.scale)
                            iconSource: "qrc:///redesign/icons/" + files[index] + ".svg"
                            text: VLCIcons.home
                            width: VLCStyle.dp(30, VLCStyle.scale)

                            onClicked: root.openCategory(index)
                        }
                    }
                    Widgets.IconToolButton {
                        description: qsTr("Add Folder")
                        height: VLCStyle.dp(30, VLCStyle.scale)
                        iconSource: "qrc:///redesign/icons/add.svg"
                        text: VLCIcons.add
                        width: VLCStyle.dp(30, VLCStyle.scale)

                        onClicked: DialogsProvider.chooseDirectory(root, selected => monitoredFolders.add(selected))
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.margins: VLCStyle.dp(20, VLCStyle.scale)
            spacing: VLCStyle.dp(17, VLCStyle.scale)

            RowLayout {
                Layout.fillWidth: true

                Widgets.IconToolButton {
                    Layout.preferredHeight: VLCStyle.dp(24, VLCStyle.scale)
                    Layout.preferredWidth: VLCStyle.dp(24, VLCStyle.scale)
                    description: qsTr("Back")
                    enabled: root.backHistory.length > 0
                    iconSource: "qrc:///redesign/icons/library-back.svg"
                    mirrorIcon: true
                    text: VLCIcons.back

                    onClicked: root.goBack()
                }
                Widgets.IconToolButton {
                    Layout.preferredHeight: VLCStyle.dp(24, VLCStyle.scale)
                    Layout.preferredWidth: VLCStyle.dp(24, VLCStyle.scale)
                    description: qsTr("Forward")
                    enabled: root.forwardHistory.length > 0
                    iconSource: "qrc:///redesign/icons/library-forward.svg"
                    mirrorIcon: true
                    text: VLCIcons.next

                    onClicked: root.goForward()
                }
                Widgets.ButtonExt {
                    id: breadcrumb

                    Accessible.name: text
                    Layout.fillWidth: true
                    T.ToolTip.text: text
                    T.ToolTip.visible: hovered
                    display: T.AbstractButton.TextOnly
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Normal
                    implicitWidth: 0
                    text: root.insideCollection ? root.collectionTitle : root.categories[root.category]

                    background: Widgets.AnimatedBackground {
                        color: breadcrumb.hovered && root.insideCollection ? theme.bg.highlight : "transparent"
                        border.color: breadcrumb.visualFocus ? theme.visualFocus : "transparent"
                    }
                    contentItem: Widgets.LabelExt {
                        text: breadcrumb.text
                        font: breadcrumb.font
                        color: theme.fg.secondary
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: if (root.insideCollection)
                        root.openCategory(root.category)
                }
                Widgets.IconToolButton {
                    Layout.preferredHeight: VLCStyle.dp(24, VLCStyle.scale)
                    Layout.preferredWidth: VLCStyle.dp(24, VLCStyle.scale)
                    description: qsTr("Menu")
                    iconSource: "qrc:///redesign/icons/library-more.svg"
                    mirrorIcon: true
                    text: ""
                    onClicked: libraryActions.popup([], mapToGlobal(0, height))
                }
                Widgets.IconToolButton {
                    Layout.preferredHeight: VLCStyle.dp(24, VLCStyle.scale)
                    Layout.preferredWidth: VLCStyle.dp(24, VLCStyle.scale)
                    description: qsTr("Expand")
                    iconSource: "qrc:///redesign/icons/library-expand.svg"
                    mirrorIcon: true
                    text: VLCIcons.fullscreen

                    onClicked: root.showFullView()
                }
            }
            RowLayout {
                Layout.fillWidth: true

                Widgets.CaptionLabel {
                    Layout.fillWidth: true
                    color: theme.fg.secondary
                    text: qsTr("%1 items").arg(root.visibleItemCount)
                }
                Widgets.IconToolButton {
                    description: qsTr("Sort")
                    iconSource: "qrc:///redesign/icons/library-sort.svg"
                    text: VLCIcons.topbar_sort
                    visible: root.category !== 0 && root.category !== 3

                    onClicked: sortMenu.popup([], mapToGlobal(0, height))
                }
                Widgets.IconToolButton {
                    description: qsTr("View")
                    iconSource: "qrc:///redesign/icons/library-view.svg"
                    text: root.gridMode ? VLCIcons.grid : VLCIcons.list
                    visible: root.category !== 0

                    onClicked: viewMenu.popup([], mapToGlobal(0, height))
                }
                Widgets.IconToolButton {
                    description: qsTr("Search")
                    iconSource: "qrc:///redesign/icons/library-search.svg"
                    text: VLCIcons.search
                    checked: root.searchVisible || search.text.length > 0
                    onClicked: {
                        root.searchVisible = !checked
                        if (root.searchVisible) search.expandAndFocus()
                        else {
                            search.clear()
                            root.setCurrentItemFocus(Qt.MouseFocusReason)
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: VLCStyle.dp(1, VLCStyle.scale)
                color: theme.border
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: VLCStyle.dp(4, VLCStyle.scale)
                visible: root.category === 2 && !root.insideCollection

                Repeater {
                    model: root.musicSections

                    Widgets.ButtonExt {
                        required property int index
                        required property string modelData

                        Layout.fillWidth: true
                        checked: root.musicSection === index
                        implicitWidth: 0
                        text: modelData

                        onClicked: {
                            root.remember();
                            root.musicSection = index;
                        }
                    }
                }
            }
            Widgets.InlineSearchField {
                id: search

                Layout.fillWidth: true
                Navigation.downItem: root.category === 0 && !root.insideCollection ? homeSections : root.gridMode ? mediaGrid : mediaList
                Navigation.parentItem: root
                visible: root.searchVisible || text.length > 0
            }
            Widgets.ButtonExt {
                Layout.fillWidth: true
                text: qsTr("Open Network Stream")
                visible: root.category === 3

                onClicked: DialogsProvider.openNetDialog()
            }
            Flickable {
                id: homeView

                Layout.fillHeight: true
                Layout.fillWidth: true
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                contentHeight: homeSections.height
                contentWidth: width
                visible: root.category === 0 && !root.insideCollection

                T.ScrollBar.vertical: Widgets.ScrollBarExt {
                }

                Widgets.NavigableCol {
                    id: homeSections
                    Navigation.parentItem: root
                    Navigation.upItem: search

                    spacing: VLCStyle.dp(30, VLCStyle.scale)
                    width: homeView.width

                    HomeSection {
                        sectionModel: continueModel
                        title: qsTr("Continue Watching")
                        fullPath: ["home", "continueWatching"]
                        width: parent.width
                    }
                    HomeSection {
                        sectionModel: listenAgainModel
                        // Source: the Figma Home section, backed by VLC audio history.
                        title: qsTr("Listen Again")
                        fullPath: ["home", "listenAgain"]
                        width: parent.width
                    }
                    HomeSection {
                        visitedCollection: true
                        sectionModel: LibraryPins.frequentFolders
                        maximumRows: 3
                        iconSource: "qrc:///redesign/icons/folder.svg"
                        mirrorIcon: true
                        fullPath: ["video", "all"]
                        title: qsTr("Frequently Visited Folders")
                        width: parent.width
                    }
                    HomeSection {
                        visitedCollection: true
                        sectionModel: LibraryPins.frequentPlaylists
                        maximumRows: 3
                        iconSource: "qrc:///redesign/icons/playlists.svg"
                        fullPath: ["video", "playlists"]
                        title: qsTr("Frequently Visited Playlists")
                        width: parent.width
                    }
                    HomeSection {
                        visitedCollection: true
                        sectionModel: LibraryPins.frequentArtists
                        iconSource: "qrc:///redesign/icons/library-artist.svg"
                        fullPath: ["music", "artists"]
                        title: qsTr("Frequently Listened Artists")
                        width: parent.width
                    }
                    HomeSection {
                        sectionModel: homeStreamsModel
                        title: qsTr("Network")
                        iconSource: "qrc:///redesign/icons/network.svg"
                        mirrorIcon: true
                        fullPath: ["discover", "url"]
                        width: parent.width
                    }
                }
            }
            Widgets.ListViewExt {
                id: mediaList

                Accessible.name: root.categories[root.category]
                Layout.fillHeight: true
                Layout.fillWidth: true
                Navigation.parentItem: root
                Navigation.upItem: search
                clip: true
                focus: visible
                model: root.activeModel
                spacing: VLCStyle.dp(10, VLCStyle.scale)
                visible: root.category !== 0 && !root.gridMode

                delegate: T.ItemDelegate {
                    id: mediaDelegate

                    readonly property bool collection: root.collectionRows
                    readonly property url cover: model.small_cover || model.thumbnail || model.cover || ""
                    readonly property var mediaId: model.id
                    readonly property string title: model.title || model.name || model.fileName || model.url || ""

                    height: VLCStyle.dp(32, VLCStyle.scale)
                    highlighted: {
                        const selection = mediaList.selectionModel.selectionFlat;
                        return mediaList.selectionModel.isSelected(index);
                    }
                    width: mediaList.width

                    background: Widgets.AnimatedBackground {
                        color: mediaDelegate.highlighted || mediaDelegate.hovered ? theme.bg.highlight : "transparent"
                        border.color: mediaDelegate.visualFocus ? theme.visualFocus : "transparent"
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                    }
                    contentItem: RowLayout {
                        Image {
                            Layout.preferredHeight: VLCStyle.dp(32, VLCStyle.scale)
                            Layout.preferredWidth: VLCStyle.dp(32, VLCStyle.scale)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: mediaDelegate.cover
                            visible: source.toString() !== ""
                        }
                        Widgets.IconLabel {
                            Layout.preferredHeight: VLCStyle.dp(32, VLCStyle.scale)
                            Layout.preferredWidth: VLCStyle.dp(32, VLCStyle.scale)
                            color: theme.fg.secondary
                            font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
                            text: root.category === 3 ? VLCIcons.stream : VLCIcons.album_cover
                            visible: mediaDelegate.cover.toString() === ""
                        }
                        Widgets.ListLabel {
                            Layout.fillWidth: true
                            color: theme.fg.secondary
                            font.weight: Font.Normal
                            text: mediaDelegate.title
                        }
                        Widgets.CaptionLabel {
                            color: theme.fg.secondary
                            text: model.duration?.valid() && model.duration.toSeconds() >= 0 && (!model.duration.isSubSecond() || model.duration.scale(1000).toSeconds() >= 0) ? model.duration.formatShort() : ""
                            visible: !mediaDelegate.collection && root.audioRows && model.duration !== undefined
                        }
                        Widgets.ButtonExt {
                            implicitHeight: VLCStyle.dp(28, VLCStyle.scale)
                            text: LibraryPins.contains(mediaDelegate.mediaId) ? qsTr("Unpin") : qsTr("Pin")
                            visible: mediaDelegate.hovered || mediaDelegate.activeFocus

                            onClicked: LibraryPins.toggle(mediaDelegate.mediaId)
                        }
                    }

                    onClicked: {
                        mediaList.selectionModel.updateSelection(Qt.NoModifier, mediaList.currentIndex, index);
                        mediaList.currentIndex = index;
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton

                        onDoubleTapped: {
                            root.activateMedia(model, mediaDelegate.collection);
                        }
                    }
                    MouseArea {
                        acceptedButtons: Qt.RightButton
                        anchors.fill: parent

                        onClicked: mouse => {
                            mediaList.selectionModel.updateSelection(Qt.NoModifier, mediaList.currentIndex, index);
                            mediaList.currentIndex = index;
                            const selected = mediaList.model.index(index, 0);
                            root.popupContextMenu([selected], mapToGlobal(mouse.x, mouse.y));
                        }
                    }
                    DragHandler {
                        target: null

                        onActiveChanged: {
                            if (active) {
                                dragItem.indexes = [index];
                                dragItem.Drag.active = true;
                            } else if (dragItem.Drag.active) {
                                dragItem.Drag.drop();
                            }
                        }
                    }
                }
                selectionModel: ListSelectionModel {
                    model: mediaList.model
                }

                onActionAtIndex: index => {
                    const requestedModel = model;
                    const collection = root.collectionRows;
                    requestedModel.getDataFlat([index], function (data) {
                        if (root.activeModel === requestedModel && data.length > 0)
                            root.activateMedia(data[0], collection);
                    });
                }
                onShowContextMenu: globalPos => root.popupContextMenu(selectionModel.selectedIndexes, globalPos)
            }
            GridView {
                id: mediaGrid

                Accessible.name: root.categories[root.category]
                Layout.fillHeight: true
                Layout.fillWidth: true
                Navigation.parentItem: root
                Navigation.upItem: search
                activeFocusOnTab: true
                cellHeight: VLCStyle.dp(root.audioRows ? 180 : 135, VLCStyle.scale)
                cellWidth: width / Math.max(1, Math.floor(width / VLCStyle.dp(145, VLCStyle.scale)))
                clip: true
                keyNavigationEnabled: true
                model: root.activeModel
                visible: root.category !== 0 && root.gridMode

                T.ScrollBar.vertical: Widgets.ScrollBarExt {
                }
                delegate: T.ItemDelegate {
                    id: gridDelegate

                    readonly property url cover: model.small_cover || model.thumbnail || model.cover || ""
                    required property int index
                    required property var model
                    readonly property string title: model.title || model.name || model.fileName || model.url || ""

                    Accessible.name: title
                    height: mediaGrid.cellHeight
                    highlighted: mediaGrid.currentIndex === index
                    padding: VLCStyle.dp(6, VLCStyle.scale)
                    width: mediaGrid.cellWidth

                    background: Widgets.AnimatedBackground {
                        color: gridDelegate.highlighted || gridDelegate.hovered ? theme.bg.highlight : "transparent"
                        border.color: gridDelegate.visualFocus ? theme.visualFocus : "transparent"
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                    }
                    contentItem: ColumnLayout {
                        spacing: VLCStyle.dp(8, VLCStyle.scale)

                        Image {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: gridDelegate.cover.toString() || (root.audioRows ? VLCStyle.noArtAlbumCover : VLCStyle.noArtVideoCover)
                        }
                        Widgets.ListLabel {
                            Layout.fillWidth: true
                            color: theme.fg.primary
                            horizontalAlignment: Text.AlignHCenter
                            text: gridDelegate.title
                        }
                    }

                    onClicked: {
                        mediaGrid.currentIndex = index;
                        mediaGrid.forceActiveFocus(Qt.MouseFocusReason);
                    }

                    TapHandler {
                        onDoubleTapped: root.activateMedia(gridDelegate.model, root.collectionRows)
                    }
                    MouseArea {
                        acceptedButtons: Qt.RightButton
                        anchors.fill: parent

                        onClicked: mouse => root.popupContextMenu([root.activeModel.index(gridDelegate.index, 0)], mapToGlobal(mouse.x, mouse.y))
                    }
                    DragHandler {
                        target: null

                        onActiveChanged: {
                            if (active) {
                                gridDragItem.indexes = [gridDelegate.index];
                                gridDragItem.Drag.active = true;
                            } else if (gridDragItem.Drag.active)
                                gridDragItem.Drag.drop();
                        }
                    }
                }

                Keys.onEnterPressed: root.activateIndex(currentIndex)
                Keys.onReturnPressed: root.activateIndex(currentIndex)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: VLCStyle.dp(8, VLCStyle.scale)
                visible: LibraryPins.model.count > 0

                Rectangle {
                    Layout.fillWidth: true
                    color: theme.border
                    implicitHeight: VLCStyle.dp(1, VLCStyle.scale)
                }
                Widgets.ListViewExt {
                    Accessible.name: qsTr("Pins")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(LibraryPins.model.count * VLCStyle.dp(32, VLCStyle.scale), Math.max(0, root.availableHeight * 0.25))
                    clip: true
                    model: LibraryPins.model

                    delegate: Widgets.ButtonExt {
                        required property var model

                        implicitHeight: VLCStyle.dp(32, VLCStyle.scale)
                        text: model.title
                        width: ListView.view.width

                        onClicked: root.activatePin(model.serialized, model)
                    }
                }
            }
        }
    }

    onVisibleChanged: if (visible)
        LibraryPins.reload()

    MLVideoFoldersModel {
        id: foldersModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLAudioModel {
        id: audioModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLAlbumModel {
        id: albumsModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLArtistModel {
        id: artistsModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLGenreModel {
        id: genresModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLUrlModel {
        id: streamsModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLPlaylistListModel {
        id: playlistsModel

        ml: MediaLib
        coverDefault: VLCStyle.noArtVideoCover
        searchPattern: search.text
    }
    MLPlaylistListModel {
        id: homePlaylistsModel

        limit: 3
        ml: MediaLib
        coverDefault: VLCStyle.noArtVideoCover
        searchPattern: search.text
    }
    MLRecentMediaModel {
        id: recentModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLVideoModel {
        id: collectionModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLPlaylistModel {
        id: collectionPlaylistModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLAudioModel {
        id: collectionAudioModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLAlbumModel {
        id: collectionAlbumsModel

        ml: MediaLib
        searchPattern: search.text
    }
    MLRecentVideoModel {
        id: continueModel

        limit: 3
        ml: MediaLib
        searchPattern: search.text
    }
    MLMediaModel {
        id: favoriteModel

        favoriteOnly: true
        limit: 3
        ml: MediaLib
        searchPattern: search.text
    }
    MLRecentAudioModel {
        id: listenAgainModel

        limit: 3
        ml: MediaLib
        searchPattern: search.text
    }
    MLUrlModel { id: homeStreamsModel; ml: MediaLib; limit: 3; searchPattern: search.text }
    MLFolderModel {
        id: monitoredFolders

        ctx: MainCtx
    }
    MLContextMenu {
        id: libraryMenu

        model: mediaList.model
    }
    PlaylistMediaContextMenu {
        id: playlistMenu

        ctx: MainCtx
        model: collectionPlaylistModel
    }
    NativeMenu {
        id: sortMenu

        actions: root.sortActions
    }
    NativeMenu {
        id: libraryActions
        actions: [
            {text: qsTr("Open File"), action: function () { DialogsProvider.simpleOpenDialog() }},
            {text: qsTr("Add Folder"), action: function () { DialogsProvider.chooseDirectory(root, selected => monitoredFolders.add(selected)) }},
            {text: qsTr("New Playlist"), action: function () { DialogsProvider.newPlaylistDialog() }}
        ]
    }
    NativeMenu {
        id: viewMenu

        actions: [
            {
                text: qsTr("List"),
                action: function () {
                    root.gridMode = false;
                }
            },
            {
                text: qsTr("Grid"),
                action: function () {
                    root.gridMode = true;
                }
            }
        ]
    }
    MLDragItem {
        id: dragItem

        coverRole: "small_cover"
        indexesFlat: true
        view: mediaList
    }
    MLDragItem {
        id: gridDragItem

        coverRole: "small_cover"
        indexesFlat: true
        view: mediaGrid
    }

    component HomeSection: Column {
        id: section

        Navigation.parentItem: homeSections
        Navigation.navigable: visible
        function setCurrentItemFocus(reason) { const item = homeItems.itemAt(0); if (item) item.forceActiveFocus(reason) }

        property bool collection: false
        property bool visitedCollection: false
        property url iconSource: ""
        property bool mirrorIcon: false
        property var fullPath: []
        property int maximumRows: 0
        required property var sectionModel
        property int sourceCategory: 0
        required property string title

        spacing: VLCStyle.dp(15, VLCStyle.scale)
        visible: sectionModel.count > 0

        RowLayout {
            width: parent.width
            Widgets.SubtitleLabel {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                font.weight: Font.Normal
                color: theme.fg.secondary
                text: section.title
                elide: Text.ElideRight
            }
            Widgets.IconToolButton {
                visible: section.fullPath.length > 0
                iconSource: "qrc:///redesign/icons/home-chevron.svg"
                mirrorIcon: true
                text: VLCIcons.chevron_right
                description: section.title
                onClicked: root.requestFullView(section.fullPath, {})
            }
        }
        Column {
            width: section.width
            spacing: VLCStyle.dp(10, VLCStyle.scale)
            Repeater {
                id: homeItems
                model: section.sectionModel

                T.ItemDelegate {
                    id: homeDelegate

                    readonly property url cover: model.small_cover || model.thumbnail || model.cover || ""
                    required property int index
                    required property var model
                    readonly property string title: model.title || model.name || model.fileName || model.url || ""

                    Accessible.name: title
                    activeFocusOnTab: true
                    hoverEnabled: true
                    Navigation.parentItem: section
                    Navigation.upItem: homeItems.itemAt(index - 1)
                    Navigation.downItem: (section.maximumRows === 0 || index + 1 < section.maximumRows) ? homeItems.itemAt(index + 1) : null
                    Keys.onPressed: event => Navigation.defaultKeyAction(event)
                    height: visible ? VLCStyle.dp(32, VLCStyle.scale) : 0
                    visible: section.maximumRows === 0 || index < section.maximumRows
                    width: section.width

                    background: Widgets.AnimatedBackground {
                        color: homeDelegate.hovered || homeDelegate.visualFocus ? theme.bg.highlight : "transparent"
                        border.color: homeDelegate.visualFocus ? theme.visualFocus : "transparent"
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                    }
                    contentItem: RowLayout {
                        Image {
                            Layout.preferredHeight: VLCStyle.dp(32, VLCStyle.scale)
                            Layout.preferredWidth: VLCStyle.dp(32, VLCStyle.scale)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            mirror: section.iconSource.toString().length > 0 && section.mirrorIcon
                            source: section.iconSource.toString().length > 0
                                ? SVGColorImage.colorize(section.iconSource).any({"#8F8F8F": theme.fg.secondary}).uri()
                                : homeDelegate.cover
                            visible: source.toString().length > 0
                        }
                        Widgets.IconLabel {
                            Layout.preferredHeight: VLCStyle.dp(32, VLCStyle.scale)
                            Layout.preferredWidth: VLCStyle.dp(32, VLCStyle.scale)
                            color: theme.fg.secondary
                            font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
                            text: VLCIcons.album_cover
                            visible: section.iconSource.toString().length === 0 && homeDelegate.cover.toString().length === 0
                        }
                        Widgets.ListLabel {
                            Layout.fillWidth: true
                            color: theme.fg.secondary
                            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                            font.weight: Font.Normal
                            text: homeDelegate.title
                        }
                    }

                    onClicked: {
                        if (section.visitedCollection) {
                            root.activatePin(model.serialized, {mediaId: model.id, title: model.title});
                            return;
                        }
                        if (section.collection) {
                            root.remember();
                            root.category = section.sourceCategory;
                            root.insideCollection = false;
                        }
                        root.activateMedia(model, section.collection);
                    }
                }
            }
        }
    }
}
