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
import QtQuick.Window
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQml.Models


import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Playlist
import VLC.Style
import VLC.Dialogs
import VLC.Player

T.Pane {
    id: root

    property var model: PlaylistListModel {
        playlist: MainPlaylistController.playlist
    }
    readonly property ListSelectionModel selectionModel: listView?.selectionModel ?? null

    property bool useAcrylic: true
    property int selectedTab: 0

    readonly property real minimumWidth: contentItem.Layout.minimumWidth +
                                         leftPadding +
                                         rightPadding +
                                         2 * (VLCStyle.margin_xsmall)

    readonly property ListView listView: contentItem.listView

    property alias contextMenu: contextMenu

    property alias dragItem: dragItem

    property alias isDropAcceptableFunc: listView.isDropAcceptableFunc
    property alias acceptDropFunc: listView.acceptDropFunc

    property alias view: listView

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    verticalPadding: 0

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Play Queue")
    AccessibleCompat.id: "playqueuePane"

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View

        focused: root.activeFocus
        hovered: root.hovered
        enabled: root.enabled
    }

    Widgets.DragItem {
        id: dragItem

        view: root.listView

        onRequestData: (indexes, resolve, reject) => {
            resolve(indexes.map((index) => {
                const item = root.model.itemAt(index)
                return {
                    "title": item.title,
                    "cover": (!!item.artwork && item.artwork.toString() !== "") ? item.artwork : VLCStyle.noArtAlbumCover,
                    "url": item.url
                }
            }))
        }

        onRequestInputItems: (indexes, data, resolve, reject) => {
            resolve(root.model.getItemsForIndexes((indexes?.length > 0) ? indexes : root.selectionModel.selectedIndexesFlat))
        }
    }

    PlaylistContextMenu {
        id: contextMenu
        model: root.model
        proxyModel: (root.contentItem?.listView?.model instanceof AbstractProxyModel) ? root.contentItem.listView.model
                                                                                        : null
        selectionModel: root.selectionModel
        controler: MainPlaylistController
        ctx: MainCtx

        onJumpToCurrentPlaying: listView.positionViewAtIndex( MainPlaylistController.currentIndex, ItemView.Center)
    }

    background: Widgets.AcrylicBackground {
        enabled: root.useAcrylic
        tintColor: theme.bg.primary

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: VLCStyle.dp(1, VLCStyle.scale)
            color: theme.border
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        Layout.minimumWidth: Math.min(Math.max(noContentInfoColumn.implicitWidth,
                                               titleRowLayout.implicitWidth ),
                                      /* Minimum width should not be too large, we rely on elision otherwise: */
                                      Window.width / 3) + (headerColumn.Layout.leftMargin + headerColumn.Layout.rightMargin)

        readonly property ListView listView: listView

        Widgets.NavigableRow {
            id: paneTabs
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: VLCStyle.dp(6, VLCStyle.scale)
            Layout.rightMargin: VLCStyle.dp(6, VLCStyle.scale)
            spacing: VLCStyle.dp(1, VLCStyle.scale)
            Navigation.parentItem: root
            Navigation.downItem: root.selectedTab === 0 ? listView : root.selectedTab === 1 ? bookmarkPane : chapterView

            PaneTab {
                Layout.fillWidth: true
                sourceName: "queue"
                text: qsTr("Queue")
                checked: root.selectedTab === 0
                onClicked: root.selectedTab = 0
            }
            PaneTab {
                Layout.fillWidth: true
                sourceName: "bookmarks"
                text: qsTr("Bookmarks")
                visible: MainCtx.mediaLibraryAvailable
                checked: root.selectedTab === 1
                onClicked: root.selectedTab = 1
            }
            PaneTab {
                Layout.fillWidth: true
                sourceName: "chapters"
                text: qsTr("Chapters")
                visible: Player.hasChapters
                checked: root.selectedTab === 2
                onClicked: root.selectedTab = 2
            }
        }

        ColumnLayout {
            id: headerColumn
            visible: root.selectedTab === 0
            Layout.fillHeight: false
            Layout.fillWidth: true
            Layout.leftMargin: VLCStyle.dp(20, VLCStyle.scale)
            Layout.rightMargin: VLCStyle.dp(20, VLCStyle.scale)
            Layout.topMargin: VLCStyle.dp(20, VLCStyle.scale)
            Layout.bottomMargin: VLCStyle.dp(12, VLCStyle.scale)
            spacing: VLCStyle.margin_xsmall

            RowLayout {
                id: titleRowLayout
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: VLCStyle.dp(12, VLCStyle.scale)

                Widgets.CaptionLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    color: theme.fg.secondary
                    elide: Text.ElideRight
                    // Source: the Figma item-count row; both values are from
                    // the original queue model, including its duration sum.
                    text: {
                        const count = listView.count
                        const caption = count === 1 ? qsTr("%1 item").arg(count) : qsTr("%1 items").arg(count)
                        if (count === 0) return caption
                        let duration
                        const model = listView.model
                        if (model instanceof PlaylistListModel) duration = model.duration
                        else {
                            const durations = []
                            for (let i = 0; i < count; ++i) durations.push(model.data(model.index(i, 0), PlaylistListModel.DurationRole))
                            duration = durations[0].sum(durations)
                        }
                        return duration.valid() && duration.toSeconds() >= 0 && (!duration.isSubSecond() || duration.scale(1000).toSeconds() >= 0)
                            ? caption + " - " + duration.formatLong() : caption
                    }
                }
                Widgets.SortControl {
                    id: sort
                    implicitWidth: VLCStyle.dp(24, VLCStyle.scale)
                    implicitHeight: VLCStyle.dp(24, VLCStyle.scale)
                    iconSource: "qrc:///redesign/icons/library-sort.svg"
                    description: qsTr("Sort")
                    AccessibleCompat.id: "playqueueSort"
                    enabled: MainPlaylistController.count > 1
                    checked: MainPlaylistController.sortKey !== PlaylistController.SORT_KEY_NONE
                    popupAbove: false
                    model: MainPlaylistController.sortKeyTitleList
                    sortKey: MainPlaylistController.sortKey
                    sortOrder: MainPlaylistController.sortOrder === PlaylistController.SORT_ORDER_ASC ? Qt.AscendingOrder : Qt.DescendingOrder
                    onSortSelected: key => MainPlaylistController.sortKey = key
                    onSortOrderSelected: order => {
                        MainPlaylistController.sortOrder = order === Qt.AscendingOrder ? PlaylistController.SORT_ORDER_ASC : PlaylistController.SORT_ORDER_DESC
                        MainPlaylistController.sort()
                    }
                    Navigation.parentItem: root
                    Navigation.rightItem: repeatQueue
                    Navigation.downItem: searchBox
                }
                QueueAction {
                    id: repeatQueue
                    text: MainPlaylistController.repeatMode === PlaylistController.PLAYBACK_REPEAT_CURRENT ? VLCIcons.repeat_one : VLCIcons.repeat_all
                    iconSource: MainPlaylistController.repeatMode === PlaylistController.PLAYBACK_REPEAT_CURRENT ? "" : "qrc:///redesign/icons/queue-repeat.svg"
                    mirrorIcon: true
                    description: qsTr("Repeat")
                    checked: MainPlaylistController.repeatMode !== PlaylistController.PLAYBACK_REPEAT_NONE
                    onClicked: MainPlaylistController.toggleRepeatMode()
                    Navigation.leftItem: sort
                    Navigation.rightItem: randomQueue
                }
                QueueAction {
                    id: randomQueue
                    text: VLCIcons.shuffle
                    iconSource: "qrc:///redesign/icons/queue-shuffle.svg"
                    mirrorIcon: true
                    description: qsTr("Random")
                    checked: MainPlaylistController.random
                    onClicked: MainPlaylistController.toggleRandom()
                    Navigation.leftItem: repeatQueue
                    Navigation.rightItem: removeQueue
                }
                QueueAction {
                    id: removeQueue
                    text: VLCIcons.remove
                    iconSource: "qrc:///redesign/icons/queue-remove.svg"
                    description: qsTr("Remove Selected")
                    enabled: root.selectionModel?.selectedIndexesFlat.length > 0
                    onClicked: root.model.removeItems(listView.mappedSelectedIndexes())
                    Navigation.leftItem: randomQueue
                    Navigation.rightItem: addFiles
                }
                QueueAction {
                    id: addFiles
                    text: VLCIcons.add
                    iconSource: "qrc:///redesign/icons/add.svg"
                    description: qsTr("Add")
                    AccessibleCompat.id: "playqueueAddFiles"
                    onClicked: DialogsProvider.simpleOpenDialog(false)
                    Navigation.leftItem: removeQueue
                    Navigation.downItem: queueMenu
                }
            }
            // Keep the original search/regex/case options and full queue menu
            // available without crowding the Figma five-action playback row.
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: VLCStyle.margin_xsmall
                Widgets.SearchBox {
                    id: searchBox
                    enabled: MainPlaylistController.count > 1
                    toggleButton.font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
                    toggleButton.iconSource: "qrc:///redesign/icons/library-search.svg"
                    popBelow: true
                    displayRegexToggleButton: true
                    displayCaseSensitiveToggleButton: true
                    popup.width: Math.max(popup.implicitWidth, root.contentItem?.width * 0.6)
                    popup.topPadding: VLCStyle.margin_xxsmall
                    Navigation.parentItem: root
                    Navigation.upItem: sort
                    Navigation.rightItem: queueMenu
                    Navigation.downItem: listView
                    Connections {
                        target: contextMenu
                        function onDiscardedFilteredOutItems() { searchBox.retract() }
                    }
                }
                QueueAction {
                    id: queueMenu
                    text: VLCIcons.more
                    iconSource: "qrc:///redesign/icons/library-more.svg"
                    mirrorIcon: true
                    description: qsTr("Menu")
                    AccessibleCompat.id: "playqueueMenu"
                    onClicked: contextMenu.popup(-1, mapToGlobal(0, height))
                    Navigation.leftItem: searchBox
                    Navigation.upItem: addFiles
                }
            }
        }

        Widgets.ListViewExt {
            id: listView
            visible: root.selectedTab === 0
            enabled: visible

            Layout.fillWidth: true
            Layout.fillHeight: true

            leftMargin: VLCStyle.dp(20, VLCStyle.scale)
            rightMargin: VLCStyle.dp(20, VLCStyle.scale)
            spacing: VLCStyle.dp(12, VLCStyle.scale)

            selectionModel: ListSelectionModel {
                model: listView.model
            }

            focus: true

            clip: !fadingEdge.implicitClipping && (height < contentHeight)

            model: proxyModel ?? root.model

            onWidthChanged: {
                if (searchBox.expanded) {
                    if (width < searchBox.textField.width)
                        searchBox.retract()
                }
            }

            property QtSortFilterProxyModel proxyModel

            function adjustFiltering() {
                // Once text changes, we switch to the proxy model.
                // We do not switch back to the source model after that.
                if (!proxyModel) {
                    proxyModel = proxyModelComponent.createObject(listView)
                }

                if (searchBox.regexButtonToggled)
                    proxyModel.setFilterRegularExpression(searchBox.searchPattern)
                else
                    proxyModel.setFilterFixedString(searchBox.searchPattern)
            }

            Component {
                id: proxyModelComponent

                QtSortFilterProxyModel {
                    filterRole: PlaylistListModel.FilterRole

                    sourceModel: root.model

                    filterCaseSensitivity: searchBox.caseSensitiveButtonToggled ? Qt.CaseSensitive
                                                                                : Qt.CaseInsensitive
                }
            }

            fadingEdge.backgroundColor: (root.background && (root.background.color.a >= 1.0)) ? root.background.color
                                                                                              : Qt.alpha(root.background.color, 0.0)

            function mappedSelectedIndexes() : var {
                let mappedSelectedIndexes

                if (!listView.selectionModel)
                    return [] // unlikely

                const selectedIndexes = listView.selectionModel.selectedIndexesFlat
                if (listView.proxyModel && listView.model === listView.proxyModel) {
                    mappedSelectedIndexes = []
                    for (let i = 0; i < selectedIndexes.length; ++i) {
                        const mappedIndex = listView.model.mapToSource(listView.model.index(selectedIndexes[i], 0))
                        mappedSelectedIndexes.push(mappedIndex.row)
                    }
                } else {
                    mappedSelectedIndexes = selectedIndexes
                }

                return mappedSelectedIndexes
            }

            function mappedIndex(index) : int {
                if (index < 0 || index >= listView.count)
                    return -1
                if (listView.proxyModel && listView.model === listView.proxyModel)
                    return listView.proxyModel.mapToSource(listView.proxyModel.index(index, 0)).row
                return index
            }

            function mappedInsertionIndex(index) : int {
                if (index < 0 || index > listView.count)
                    return -1
                if (index < listView.count)
                    return mappedIndex(index)
                // The boundary below the last visible row belongs directly
                // after that real queue item, even with search filtering.
                return listView.count > 0 ? mappedIndex(listView.count - 1) + 1 : root.model.count
            }

            isDropAcceptableFunc: function(drop, index) {
                const targetIndex = listView.mappedInsertionIndex(index)
                if (targetIndex < 0)
                    return false
                if (drop.source === dragItem)
                    return Helpers.itemsMovable(listView.mappedSelectedIndexes(), targetIndex)
                else if (Helpers.isValidInstanceOf(drop.source, Widgets.DragItem))
                    return true
                else if (drop.hasUrls)
                    return true
                else
                    return false
            }

            acceptDropFunc: function(index, drop) {
                const item = drop.source;
                const targetIndex = listView.mappedInsertionIndex(index);
                if (targetIndex < 0)
                    return Promise.resolve()

                // NOTE: Move implementation.
                if (dragItem === item) {
                    root.model.moveItemsPre(listView.mappedSelectedIndexes(), targetIndex);
                    listView.forceActiveFocus();
                // NOTE: Dropping medialibrary content into the queue.
                } else if (Helpers.isValidInstanceOf(item, Widgets.DragItem)) {
                    return item.getSelectedInputItem().then((inputItems) => {
                            if (!Helpers.isArray(inputItems) || inputItems.length === 0) {
                                console.warn("can't convert items to input items");
                                return
                            }
                            MainPlaylistController.insert(targetIndex, inputItems, false)
                        }).then(() => { listView.forceActiveFocus(); })
                // NOTE: Dropping an external item (i.e. filesystem) into the queue.
                } else if (drop.hasUrls) {
                    const urlList = [];

                    for (let url in drop.urls)
                        urlList.push(drop.urls[url]);

                    MainPlaylistController.insert(targetIndex, urlList, false);

                    // NOTE This is required otherwise backend may handle the drop as well yielding double addition.
                    drop.accept(Qt.IgnoreAction);
                    listView.forceActiveFocus();
                }

                return Promise.resolve()
            }

            property int shiftIndex: -1

            onShowContextMenu: (globalPos) => {
                contextMenu.popup(-1, globalPos)
            }

            Behavior on contentY {
                id: contentYBehavior

                enabled: false

                // NOTE: Usage of `SmoothedAnimation` is intentional here.
                SmoothedAnimation {
                    duration: VLCStyle.duration_veryLong
                    easing.type: Easing.InOutSine
                }
            }

            Component.onCompleted: {
                // WARNING: Tracking the current item and not the current index is intentional here.
                MainPlaylistController.currentItemChanged.connect(listView, () => {
                    // FIXME: Qt does not provide the `contentY` with `positionViewAtIndex()` for us
                    //        to animate. For that reason, we capture the new `contentY`, adjust
                    //        `contentY` to it is old value then enable the animation and set `contentY`
                    //        to its new value.
                    const oldContentY = listView.contentY
                    const currentIndex = listView.proxyModel && listView.model === listView.proxyModel
                        ? listView.proxyModel.mapFromSource(root.model.index(MainPlaylistController.currentIndex, 0)).row
                        : MainPlaylistController.currentIndex
                    if (currentIndex < 0)
                        return
                    listView.positionViewAtIndex(currentIndex, ListView.Contain)
                    const newContentY = listView.contentY
                    if (Math.abs(oldContentY - newContentY) >= Number.EPSILON) {
                        contentYBehavior.enabled = false
                        listView.contentY = oldContentY
                        contentYBehavior.enabled = true
                        listView.contentY = newContentY
                        contentYBehavior.enabled = false
                    }
                })

                searchBox.searchPatternChanged.connect(listView, listView.adjustFiltering)
                searchBox.regexButtonToggledChanged.connect(listView, listView.adjustFiltering)
            }

            Connections {
                target: listView.model

                function onRowsInserted() {
                    if (listView.currentIndex === -1)
                        listView.currentIndex = 0
                }

                function onModelReset() {
                    if (listView.currentIndex === -1 && listView.count > 0)
                        listView.currentIndex = 0
                }
            }

            delegate: PlaylistDelegate {
                id: delegate

                compact: true
                width: listView.contentWidth
                rightPadding: Math.max(listView.T.ScrollBar.vertical.width, VLCStyle.dp(4, VLCStyle.scale))

                contextMenu: root.contextMenu

                dragItem: root.dragItem

                isDropAcceptable: listView.isDropAcceptableFunc
                acceptDrop: listView.acceptDropFunc

                onContainsDragChanged: listView.updateItemContainsDrag(this, containsDrag)

                onIsCurrentChanged: {
                    if (isCurrent)
                        listView.fadingEdge.excludeItem = delegate
                    else if (listView.fadingEdge.excludeItem === delegate)
                        listView.fadingEdge.excludeItem = null
                }
            }

            Keys.onDeletePressed: {
                let items

                const selectedIndexes = selectionModel.selectedIndexesFlat
                if (listView.proxyModel && listView.model === listView.proxyModel) {
                    items = []
                    for (let i = 0; i < selectedIndexes.length; ++i) {
                        const mappedIndex = listView.proxyModel.mapToSource(listView.proxyModel.index(selectedIndexes[i], 0))
                        items.push(mappedIndex.row)
                    }
                } else {
                    items = selectedIndexes
                }

                if (items.length > 0)
                    root.model.removeItems(items)
            }

            Navigation.parentItem: root
            Navigation.upItem: sort

            onActionAtIndex: (index) => {
                const sourceIndex = listView.mappedIndex(index)
                if (sourceIndex < 0)
                    return

                MainPlaylistController.goTo(sourceIndex, true)
            }

            Column {
                id: noContentInfoColumn

                anchors.centerIn: parent

                visible: false
                enabled: visible

                opacity: (listView.activeFocus) ? 1.0 : 0.4

                Binding on visible {
                    delayed: true
                    value: (listView.count === 0 && !listView.footerItem.firstItemIndicatorVisible)
                }

                Widgets.IconLabel {
                    id: label

                    anchors.horizontalCenter: parent.horizontalCenter

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    text: VLCIcons.playlist

                    color: theme.fg.primary

                    font.pixelSize: VLCStyle.dp(48, VLCStyle.scale)
                }

                T.Label {
                    anchors.topMargin: VLCStyle.margin_xlarge

                    anchors.horizontalCenter: parent.horizontalCenter

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    text: (listView.proxyModel &&
                           listView.model === listView.proxyModel &&
                           listView.count !== root.model.count) ? qsTr("No results")
                                                                : qsTr("No content yet")

                    color: label.color

                    font.pixelSize: VLCStyle.fontSize_xxlarge
                }

                T.Label {
                    anchors.topMargin: VLCStyle.margin_normal

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    text: qsTr("Drag & Drop some content here!")
                    visible: (listView.proxyModel && listView.model === listView.proxyModel) ? (listView.count === root.model.count)
                                                                                             : true

                    color: label.color

                    font.pixelSize: VLCStyle.fontSize_large
                }
            }
        }

        Loader {
            id: bookmarkPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: VLCStyle.margin_normal
            active: root.selectedTab === 1 && MainCtx.mediaLibraryAvailable
            visible: active
            source: "qrc:///qt/qml/VLC/Player/PlayerBookmarks.qml"
            onLoaded: item.focus = true
            onActiveFocusChanged: if (activeFocus && item) item.forceActiveFocus(Qt.TabFocusReason)
            Navigation.parentItem: root
            Navigation.upItem: paneTabs
        }

        Widgets.ListViewExt {
            id: chapterView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: VLCStyle.margin_normal
            visible: root.selectedTab === 2
            enabled: visible
            model: Player.chapters
            focus: visible
            clip: true
            Accessible.name: qsTr("Chapters")
            Navigation.parentItem: root
            Navigation.upItem: paneTabs
            onActionAtIndex: (index) => Player.chapters.selectChapter(index)

            delegate: Widgets.CheckedDelegate {
                width: chapterView.width
                height: VLCStyle.dp(42, VLCStyle.scale)
                checked: model.checked
                checkable: false
                text: model.display
                onClicked: Player.chapters.selectChapter(index)
                contentItem: RowLayout {
                    Widgets.CaptionLabel {
                        text: index + 1
                        color: theme.accent
                    }
                    Widgets.ListLabel {
                        Layout.fillWidth: true
                        text: model.display
                        color: theme.fg.primary
                    }
                    Widgets.CaptionLabel {
                        text: model.time.valid() ? model.time.formatHMS() : ""
                        color: theme.fg.secondary
                    }
                }
                Navigation.parentItem: chapterView
            }
        }
    }

    component QueueAction: Widgets.IconToolButton {
        implicitWidth: VLCStyle.dp(24, VLCStyle.scale)
        implicitHeight: VLCStyle.dp(24, VLCStyle.scale)
        Navigation.parentItem: root
        Navigation.downItem: listView
    }

    component PaneTab: Widgets.ButtonExt {
        id: paneTab
        required property string sourceName
        implicitWidth: 0
        implicitHeight: VLCStyle.dp(50, VLCStyle.scale)
        topPadding: VLCStyle.dp(14, VLCStyle.scale)
        bottomPadding: VLCStyle.dp(16, VLCStyle.scale)
        leftPadding: 0
        rightPadding: 0
        color: checked ? theme.fg.primary : theme.fg.secondary
        Accessible.name: text
        readonly property ColorContext tabTheme: ColorContext { colorSet: ColorContext.TextField }
        background: Rectangle {
            color: paneTab.tabTheme.bg.primary
            border.width: paneTab.visualFocus ? VLCStyle.dp(2, VLCStyle.scale) : 0
            border.color: theme.visualFocus
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                height: VLCStyle.dp(2, VLCStyle.scale)
                width: Math.max(0, parent.width - VLCStyle.dp(16, VLCStyle.scale))
                color: paneTab.checked ? theme.accent : "transparent"
            }
        }
        contentItem: Item {
            implicitHeight: VLCStyle.dp(20, VLCStyle.scale)
            Row {
            anchors.centerIn: parent
            spacing: VLCStyle.dp(8, VLCStyle.scale)
            Image {
                width: VLCStyle.dp(20, VLCStyle.scale)
                height: width
                source: SVGColorImage.colorize("qrc:///redesign/icons/player-tab-" + paneTab.sourceName + ".svg")
                         .any({ "#6B6B6B": paneTab.color, "#8F8F8F": paneTab.color, "#D37918": paneTab.checked ? theme.accent : paneTab.color }).uri()
            }
            Text {
                visible: paneTab.width >= VLCStyle.dp(100, VLCStyle.scale)
                text: paneTab.text
                color: paneTab.color
                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                height: VLCStyle.dp(20, VLCStyle.scale)
            }
            }
        }
    }

    Connections {
        target: Player
        function onHasChaptersChanged() {
            if (!Player.hasChapters && root.selectedTab === 2)
                root.selectedTab = 0
        }
    }

    Keys.priority: Keys.AfterItem
    Keys.forwardTo: root.selectedTab === 0 ? listView : root.selectedTab === 1 ? (bookmarkPane.item ?? bookmarkPane) : chapterView
    Keys.onPressed: (event) => root.Navigation.defaultKeyAction(event)

    component PlaylistToggleButton : Widgets.IconToolButton {
        id: playlistBtn

        focus: true

        font.pixelSize: VLCStyle.icon_banner
        text: VLCIcons.playlist
        description: qsTr("Play queue")

        AccessibleCompat.id: "playqueueToggle"

        width: VLCStyle.bannerButton_width
        height: VLCStyle.bannerButton_height
        //highlighted: MainCtx.playlistVisible

        property Item plListView

        DropArea {
            anchors.fill: parent

            onContainsDragChanged: {
                if (containsDrag) {
                    _timer.restart()

                    if (playlistBtn.plListView)
                        MainCtx.setCursor(Qt.DragCopyCursor)
                } else {
                    _timer.stop()

                    if (playlistBtn.plListView)
                        MainCtx.restoreCursor()
                }
            }

            onEntered: (drag) => {
                const plListView = playlistBtn.plListView
                if (plListView) {
                    console.assert(plListView.isDropAcceptableFunc)
                    console.assert(plListView.model)
                    if (plListView.isDropAcceptableFunc(drag, plListView.model.count)) {
                        drag.accept()
                    } else {
                        drag.accepted = false
                    }
                } else {
                    drag.accepted = false
                }
            }

            onDropped: (drop) => {
                const plListView = playlistBtn.plListView
                if (plListView) {
                    console.assert(plListView.acceptDropFunc)
                    plListView.acceptDropFunc(plListView.model.count, drop)
                }
            }

            Timer {
                id: _timer
                interval: VLCStyle.duration_humanMoment

                onTriggered: {
                    MainCtx.playqueuePanel.visible = true
                }
            }
        }
    }
}
