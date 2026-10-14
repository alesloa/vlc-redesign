/*****************************************************************************
 * Copyright (C) 2025 VLC authors and VideoLAN
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
import VLC.Menus
import VLC.Util

T.Page {
    id: root

    //path of the current page loader
    property var pagePrefix: []

    //note that T.Page introduce an intermediate Item, so to access our delegate,
    //we need to use contentChildren[0] rather than contentItem
    readonly property Item _firstChild: contentChildren[0] ?? null

    //indicates whether the subview support grid/list mode
    property bool hasGridListMode: _firstChild?.hasGridListMode ?? false

    property bool isSearchable: _firstChild?.isSearchable ?? false

    // Counts come from the active VLC model, never the reference's sample media.
    readonly property int itemCount: Number.isFinite(_firstChild?.model?.count)
        ? _firstChild.model.count : -1
    property int displayedItemCount: itemCount

    property var sortModel: _firstChild?.sortModel ?? null

    //property is *not* readOnly, a PageLoader may define a localMenuDelegate common for its subviews (music, video)
    property SortMenu sortMenu: null

    property int displayMarginBeginning: 0
    property int displayMarginEnd: 0

    property bool enableBeginningFade: true
    property bool enableEndFade: true

    readonly property SearchCtx search: _searchCtx
    readonly property SortCtx sort: _sortCtx


    SearchCtx {
        id: _searchCtx
        available: root.isSearchable
    }

    SortCtx {
        id: _sortCtx

        readonly property string _sortCriteriaKey: ["sortCriteria", ...root.pagePrefix].join("/")
        readonly property string _sortOrderKey:  ["sortOrder", ...root.pagePrefix].join("/")

        available: Helpers.isArray(root.sortModel) && (root.sortModel).length > 0
        model: root.sortModel

        //save & restore setting of the page
        Component.onCompleted: {
            const criteria = MainCtx.settingValue(_sortCriteriaKey, undefined)
            if (criteria !== undefined)
                _sortCtx.criteria = criteria

            const order = MainCtx.settingValue(_sortOrderKey, undefined)
            if (order !== undefined)
                _sortCtx.order = parseInt(order)
        }

        Component.onDestruction: {
            MainCtx.setSettingValue(_sortCriteriaKey, _sortCtx.criteria)
            MainCtx.setSettingValue(_sortOrderKey, _sortCtx.order)
        }
    }

    Binding {
        target: MainCtx
        property: "hasGridListMode";
        value: root.hasGridListMode
    }

    on_FirstChildChanged: {
        if (!_firstChild)
            return
        _firstChild.Navigation.parentItem = root
        _firstChild.Navigation.upItem = root.header
    }

    function positionContentAtBeginning() {
        _firstChild?.positionContentAtBeginning?.()
    }

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding
                             + (implicitHeaderHeight > 0 ? implicitHeaderHeight + spacing : 0)
                             + (implicitFooterHeight > 0 ? implicitFooterHeight + spacing : 0))

    header: DefaultPageHeader {
        text: root.title

        leftPadding: MainCtx.dp(20, VLCStyle.scale) + root.leftPadding
        rightPadding: MainCtx.dp(20, VLCStyle.scale) + root.rightPadding

        sortMenu: root.sortMenu

        search: _searchCtx
        sort: _sortCtx

        Navigation.parentItem: root
        Navigation.downAction: function() {
            if (typeof root.setCurrentItemFocus === "function")
                root.setCurrentItemFocus(Qt.TabFocusReason)
            else if (typeof root._firstChild?.setCurrentItemFocus === "function")
             root._firstChild.setCurrentItemFocus(Qt.TabFocusReason)
            else if (root._firstChild)
                root._firstChild.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    component DefaultPageHeader: T.ToolBar {
        id: defaultPageHeader

        // Properties
        property alias text: label.text

        property alias sortMenu: gridSortFilter.sortMenu

        property alias search: gridSortFilter.search
        property alias sort: gridSortFilter.sort

        position: T.ToolBar.Header

        topPadding: MainCtx.dp(20, VLCStyle.scale)
        bottomPadding: MainCtx.dp(17, VLCStyle.scale)

        // FIXME: `GridItem`'s background extends beyond its
        //        bounding rect, violating the hypothetical
        //        clip test (see 7e6b23db).
        bottomInset: (MainCtx.hasGridListMode && MainCtx.gridView) ? VLCStyle.gridItemSelectedBorder : undefined

        // Settings

        implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                                implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                                 implicitContentHeight + topPadding + bottomPadding)

        Navigation.navigable: gridSortFilter.enabled

        // Children

        readonly property ColorContext colorContext: ColorContext {
            id: theme
            colorSet: ColorContext.View
        }

        background: Rectangle {
            color: theme.bg.primary
        }

        RowLayout {
            id: row

            anchors.fill: parent
            spacing: MainCtx.dp(10, VLCStyle.scale)

            IconToolButton {
                text: VLCIcons.back
                description: qsTr("Previous")
                iconSource: "qrc:/redesign/icons/library-back.svg"
                mirrorIcon: true
                Layout.preferredWidth: MainCtx.dp(24, VLCStyle.scale)
                Layout.preferredHeight: MainCtx.dp(32, VLCStyle.scale)
                enabled: !History.previousEmpty
                onClicked: History.previous()
                Navigation.parentItem: defaultPageHeader
                AccessibleCompat.id: "pageHistoryBackButton"
            }

            IconToolButton {
                text: VLCIcons.back
                // Back/Forward are named in the owner's walkthrough.
                description: qsTr("Forward")
                iconSource: "qrc:/redesign/icons/library-forward.svg"
                mirrorIcon: true
                Layout.preferredWidth: MainCtx.dp(24, VLCStyle.scale)
                Layout.preferredHeight: MainCtx.dp(32, VLCStyle.scale)
                enabled: !History.nextEmpty
                onClicked: History.next()
                Navigation.parentItem: defaultPageHeader
                AccessibleCompat.id: "pageHistoryForwardButton"
            }

            T.ToolButton {
                id: categoryButton
                // Category names are published in Figma's library navigation.
                readonly property var captions: ({home: qsTr("Home"), video: qsTr("Videos"),
                    music: qsTr("Music"), network: qsTr("Network"), discover: qsTr("Discover"),
                    recent: qsTr("Recent")})
                text: captions[root.pagePrefix[0]] || ""
                visible: text.length > 0 && text !== defaultPageHeader.text
                implicitWidth: contentItem.implicitWidth
                implicitHeight: MainCtx.dp(32, VLCStyle.scale)
                onClicked: History.push([root.pagePrefix[0]])
                contentItem: ListLabel { text: categoryButton.text; color: theme.fg.secondary; font.weight: Font.Normal }
                background: Rectangle {
                    color: categoryButton.hovered ? theme.bg.secondary : "transparent"
                    border.color: categoryButton.visualFocus ? theme.visualFocus : "transparent"
                    radius: MainCtx.dp(4, VLCStyle.scale)
                }
                Navigation.parentItem: defaultPageHeader
            }

            Image {
                visible: categoryButton.visible
                Layout.preferredWidth: MainCtx.dp(12, VLCStyle.scale)
                Layout.preferredHeight: MainCtx.dp(12, VLCStyle.scale)
                rotation: -90
                source: SVGColorImage.colorize("qrc:/redesign/icons/settings-chevron.svg")
                    .any({"#8F8F8F": theme.fg.secondary}).uri()
            }

            SubtitleLabel {
                id: label

                Layout.fillWidth: true

                color: theme.fg.secondary
                font.pixelSize: MainCtx.dp(16, VLCStyle.scale)
                font.weight: Font.Normal
                elide: Text.ElideRight
            }

            ListLabel {
                visible: root.displayedItemCount >= 0
                // "items" comes from the Figma header; the count is the model's.
                text: (root.displayedItemCount === 1 ? qsTr("%1 item") : qsTr("%1 items"))
                    .arg(root.displayedItemCount)
                color: theme.fg.secondary
                font.pixelSize: MainCtx.dp(12, VLCStyle.scale)
                font.weight: Font.Normal
            }

            GridSortFilterControls {
                id: gridSortFilter
                focus: true
                sort: _sortCtx
                search: _searchCtx
                Navigation.parentItem: defaultPageHeader
            }
            IconToolButton {
                text: VLCIcons.more
                iconSource: "qrc:/redesign/icons/library-more.svg"
                mirrorIcon: true
                description: qsTr("Menu")
                Layout.preferredWidth: MainCtx.dp(24, VLCStyle.scale)
                Layout.preferredHeight: MainCtx.dp(32, VLCStyle.scale)
                checked: pageMenu.shown
                onClicked: pageMenu.popup(mapToGlobal(0, height))
                Navigation.parentItem: defaultPageHeader
                QmlGlobalMenu { id: pageMenu; ctx: MainCtx }
            }
        }
    }
}
