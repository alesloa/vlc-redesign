/*****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
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
import QtQml.Models

import VLC.Style
import VLC.Widgets as Widgets

import VLC.MainInterface
import VLC.MediaLibrary
import VLC.Dialogs
import VLC.Util

T.Pane {
    id: root

    signal itemClicked(uri : var, item : Item)
    signal pinRequested(uri : var, properties : var)

    //safe area margins for delegate content,
    //so the background of the delegates fills the available space
    //but the content remains within the safe area
    property int safeAreaLeftMargin: 0
    property int safeAreaRightMargin: 0

    property bool useAcrylic: false

    property bool delegateShowText: true

    property alias model: navigationModel

    readonly property int minimumWidth: MainCtx.dp(217) + safeAreaLeftMargin + safeAreaRightMargin

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: VLCStyle.margin_normal

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.Window
    }

    Accessible.name: qsTr("Sidebar")

    NavigationModel {
        id: navigationModel
        hasMedialib: MainCtx.mediaLibraryAvailable
    }

    Connections {
        target: History

        // NOTE: handles cases where the path changes not by clicking in the sidebar
        function onViewPathChanged(viewPath) {
            let bestRow = -1
            let bestScore = -1
            for (let i = 0; i < listView.count; ++i) {
                const rowIndex = navigationModel.index(i, 0)
                const uri = navigationModel.data(rowIndex, NavigationModel.URI)
                if (uri && History.match(viewPath, uri)) {
                    // Prefer a direct rail shortcut over its broader parent category.
                    const score = uri.length * 10
                        + (navigationModel.data(rowIndex, NavigationModel.DEPTH) === 0 ? 1 : 0)
                    if (score > bestScore) { bestScore = score; bestRow = i }
                }
            }
            if (bestRow < 0) return
            listView.currentIndex = bestRow
            const rowIndex = navigationModel.index(bestRow, 0)
            if (navigationModel.data(rowIndex, NavigationModel.EXPANDABLE)
                    && !navigationModel.data(rowIndex, NavigationModel.EXPANDED))
                navigationModel.setData(rowIndex, true, NavigationModel.EXPANDED)
        }
    }

    readonly property ColorContext surfaceTheme: ColorContext { colorSet: ColorContext.View }

    background: Rectangle {
        color: root.delegateShowText ? root.surfaceTheme.bg.primary : theme.bg.secondary
        Rectangle {
            anchors.fill: parent
            anchors.margins: MainCtx.dp(8)
            visible: root.delegateShowText
            radius: MainCtx.dp(6)
            color: theme.bg.secondary
        }
    }

    contentItem:  Item {
        id: contentItemId

        //don't use Layout as top item as items put as children of the Control
        //would be parented (and layouted) to the Layout
        ColumnLayout {
            anchors.fill: parent
            spacing: VLCStyle.margin_xsmall

            Widgets.ListViewExt {
                id: listView

                Layout.fillWidth: true
                Layout.fillHeight: true

                clip: !fadingEdge.implicitClipping && (height < contentHeight)
                focus: true

                model: navigationModel

                Binding {
                    target: listView.T.ScrollBar.vertical
                    property: "policy"
                    when: listView.T.ScrollBar.vertical?.size > (1.0 - Number.EPSILON)
                    value: T.ScrollBar.AlwaysOff
                }

                colorContext.colorSet: ColorContext.Window

                fadingEdge.backgroundColor:  (root.background && (root.background.color.a >= 1.0)) ? root.background.color
                                                                                                   : "transparent"

                component DelegateAnimation : NumberAnimation {
                    easing.type: Easing.InOutSine
                    duration: VLCStyle.duration_long
                }

                reuseItems: false // Not relevant here, we disable it because of QTBUG-131106 when transition is involved.

                // As the docs note, `ListView` transitions do not seem to handle height animation. For that reason,
                // we animate the height directly in the delegate (Qt's recommended workaround). Because of this, we
                // do not need to have `addDisplaced` transition here, but we can have `removeDisplaced` here:
                removeDisplaced: Transition {
                    DelegateAnimation { property: "y" }
                }

                onCurrentIndexChanged: {
                    const rowIndex = navigationModel.index(currentIndex, 0)

                    if (rowIndex.valid && navigationModel.data(rowIndex, NavigationModel.EXPANDABLE)
                            && !navigationModel.data(rowIndex, NavigationModel.EXPANDED)
                            && History.match(History.viewPath, navigationModel.data(rowIndex, NavigationModel.URI)))
                        navigationModel.setData(rowIndex, true, NavigationModel.EXPANDED)
                }

                property bool readyForAnimations: false

                onModelChanged: {
                    if (!listView.readyForAnimations)
                        Qt.callLater(() => { listView.readyForAnimations = true })
                }

                Navigation.parentItem: root
                Navigation.downItem: preferenceButton

                delegate: SideNavigationDelegate {
                    id: delegate

                    width: ListView.view.contentWidth
                    height: preferredHeight

                    property real preferredHeight: shouldShow ? MainCtx.dp(showText && depth > 0 ? 36 : 46) : 0.0

                    leftPadding: root.safeAreaLeftMargin + MainCtx.dp(showText ? 16 : 13)
                    rightPadding: root.safeAreaRightMargin + MainCtx.dp(showText ? 8 : 13)
                    topPadding: MainCtx.dp(4)
                    bottomPadding: MainCtx.dp(showText && depth > 0 ? 8 : 18)

                    leftInset: root.safeAreaLeftMargin + MainCtx.dp(showText ? 4 : 9)
                    rightInset: root.safeAreaRightMargin + MainCtx.dp(showText ? 4 : 9)
                    topInset: 0
                    bottomInset: MainCtx.dp(showText && depth > 0 ? 0 : 14)

                    iconTxt: icon_alias
                    // Original category exports from the owner's Figma library.
                    iconSource: {
                        if (depth !== 0 || !uri || uri.length === 0)
                            return ""
                        const icons = {home: "home", video: "videos", music: "music", network: "network", recent: "recent"}
                        const name = uri[0] === "video" && uri[1] === "playlists"
                            ? "playlists" : icons[uri[0]]
                        return name ? "qrc:/redesign/icons/" + name + ".svg" : ""
                    }
                    mirrorIcon: depth === 0 && uri && ["home", "music", "network", "recent"].includes(uri[0])
                        && uri[1] !== "playlists"
                    text: title

                    showText: root.delegateShowText

                    required property string title
                    required property var uri
                    required property int depth
                    // TODO: Qt 6.2 has property `icon` marked final, so we can't override it:
                    required property string icon_alias
                    required property bool expandable
                    required property bool expanded

                    required property int index

                    visible: (height > 0.0)

                    property bool shouldShow: showText || (iconTxt.length > 0)

                    onShouldShowChanged: {
                        if (listView.readyForAnimations)
                            heightBehavior.enabled = true // At this point, it can keep being enabled for good.
                    }

                    highlighted: !!uri && History.match(History.viewPath, uri)
                        && !(depth === 0 && uri[0] === "video" && uri.length === 1
                             && History.viewPath[1] === "playlists")
                    checked: (!showText || !expanded) && highlighted

                    onClicked: {
                        itemClicked(uri, this)
                        listView.currentIndex = index
                        listView.forceActiveFocus(focusReason)
                    }

                    Behavior on height {
                        id: heightBehavior

                        enabled: false

                        DelegateAnimation {
                            onRunningChanged: {
                                if (running) {
                                    delegate.clip = true
                                } else {
                                    delegate.clip = false
                                }
                            }
                        }
                    }

                    ListView.onAdd: {
                        if (listView.readyForAnimations && delegate.showText) {
                            heightBehavior.enabled = false
                            delegate.height = 0.0
                            heightBehavior.enabled = true
                            delegate.height = Qt.binding(() => delegate.preferredHeight)
                            heightBehavior.enabled = false
                        }
                    }
                }

                footer: Loader {
                    width: listView.width
                    active: MainCtx.mediaLibraryAvailable && LibraryPins.model.count > 0
                    visible: active
                    sourceComponent: Column {
                        width: parent.width
                        Repeater {
                            model: LibraryPins.model
                            delegate: SideNavigationDelegate {
                                id: pinDelegate
                                required property var model
                                readonly property bool expandable: false
                                width: parent.width
                                height: MainCtx.dp(showText ? 42 : 46)
                                showText: root.delegateShowText
                                text: model.title
                                iconSource: "qrc:/redesign/icons/"
                                    + (model.kind === "folder" ? "folder" : model.kind === "playlist"
                                       ? "playlists" : ["album", "artist", "genre"].includes(model.kind)
                                       ? "music" : "videos") + ".svg"
                                mirrorIcon: model.kind === "folder" || ["album", "artist", "genre"].includes(model.kind)
                                leftPadding: MainCtx.dp(showText ? 12 : 13)
                                rightPadding: MainCtx.dp(showText ? 32 : 13)
                                topPadding: MainCtx.dp(showText ? 8 : 4)
                                bottomPadding: MainCtx.dp(showText ? 8 : 18)
                                leftInset: MainCtx.dp(showText ? 4 : 9)
                                rightInset: MainCtx.dp(showText ? 4 : 9)
                                topInset: 0
                                bottomInset: MainCtx.dp(showText ? 0 : 14)
                                focusPolicy: Qt.StrongFocus
                                onClicked: {
                                    const destination = LibraryPins.route(model)
                                    if (destination) root.pinRequested(destination.path, destination.properties)
                                    else MediaLib.addAndPlay(model.mediaId)
                                }
                                Keys.onDeletePressed: LibraryPins.toggle(model.mediaId)
                                Widgets.IconToolButton {
                                    anchors.right: parent.right
                                    anchors.rightMargin: MainCtx.dp(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: MainCtx.dp(24)
                                    height: width
                                    visible: pinDelegate.showText && (pinDelegate.hovered || pinDelegate.activeFocus || hovered || activeFocus)
                                    description: qsTr("Unpin")
                                    text: VLCIcons.close
                                    iconSource: "qrc:/redesign/icons/remove.svg"
                                    onClicked: LibraryPins.toggle(pinDelegate.model.mediaId)
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                id: loaderProgress

                Layout.fillWidth: true

                active: (MainCtx.mediaLibraryAvailable && MainCtx.mediaLibrary.idle === false)
                visible: active

                source: "qrc:///qt/qml/VLC/MediaLibrary/ScanProgressBar.qml"

                onLoaded: {
                    if (item.background) {
                        item.background.opacity = 0.6
                        item.background.radius = Qt.binding(() => VLCStyle.dp(4, VLCStyle.scale))
                    }

                    item.leftPadding = Qt.binding(function() { return root.safeAreaLeftMargin + VLCStyle.margin_small })
                    item.rightPadding = Qt.binding(function() { return root.safeAreaRightMargin + VLCStyle.margin_small })

                    item.leftInset = Qt.binding(() => { return VLCStyle.margin_xxsmall + root.safeAreaLeftMargin })
                    item.rightInset = Qt.binding(() => { return VLCStyle.margin_xxsmall + root.safeAreaRightMargin })
                }
            }

            SideNavigationDelegate {
                id: preferenceButton

                AccessibleCompat.id: "preferencesButton"

                Layout.fillWidth: true
                Layout.preferredHeight: MainCtx.dp(32)

                leftPadding: root.safeAreaLeftMargin + MainCtx.dp(showText ? 12 : 13)
                rightPadding: root.safeAreaRightMargin + MainCtx.dp(showText ? 8 : 13)
                topPadding: MainCtx.dp(4)
                bottomPadding: MainCtx.dp(4)

                leftInset: root.safeAreaLeftMargin + MainCtx.dp(showText ? 4 : 9)
                rightInset: root.safeAreaRightMargin + MainCtx.dp(showText ? 4 : 9)
                topInset: 0
                bottomInset: 0

                iconTxt: VLCIcons.settings
                iconSource: "qrc:/redesign/icons/menu-settings.svg"
                text: qsTr("Preferences")

                checked: DialogsProvider.prefsDialogVisible

                showText: root.delegateShowText

                onClicked: DialogsProvider.prefsDialog()

                //SideNavigationDelegate is an ItemDelegate and has NoFocus by default
                focusPolicy: Qt.StrongFocus

                Navigation.parentItem: root
                Navigation.upItem: listView

                Keys.priority: Keys.AfterItem
                Keys.onPressed: (e) => Navigation.defaultKeyAction(e)
                Keys.onReleased: (e) => Navigation.defaultKeyReleaseAction(e)
            }

        }
    }
}
