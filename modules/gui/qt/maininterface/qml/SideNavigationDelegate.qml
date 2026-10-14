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
import QtQuick.Templates as T
import QtQuick.Layouts


import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Util

T.ItemDelegate {
    id: control

    // Properties

    property string iconTxt: ""

    property url iconSource: ""
    property bool mirrorIcon: false

    property bool showText: true

    property real radius: MainCtx.dp(4)

    // Settings

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: VLCStyle.margin_xxsmall

    leftInset: implicitLeftInset
    rightInset: implicitRightInset

    topInset: implicitTopInset
    bottomInset: implicitBottomInset

    property real implicitLeftInset: VLCStyle.margin_xxsmall
    property real implicitRightInset: VLCStyle.margin_xxsmall

    property real implicitTopInset: VLCStyle.margin_xxxsmall
    property real implicitBottomInset: VLCStyle.margin_xxxsmall

    // Accessible

    Accessible.onPressAction: control.clicked()
    AccessibleCompat.id: {
        if (model.depth !== 0 || !model.uri || model.uri.length === 0) return "";
        const navBarIds = {
            "home": "homeNavBar",
            "video": "videoNavBar",
            "music": "musicNavBar",
            "network": "browseNavBar",
            "recent": "recentNavBar",
            "discover": "discoverNavBar"
        }
        const id = model.uri[0] === "video" && model.uri[1] === "playlists"
            ? "playlistsNavBar" : navBarIds[model.uri[0]]
        if (id !== undefined)
            return id
        else
            return ""
    }

    // Tooltip

    T.ToolTip.visible: (showText === false && T.ToolTip.text && (hovered || visualFocus))

    T.ToolTip.delay: VLCStyle.delayToolTipAppear

    T.ToolTip.text: text

    // Childs

    ColorContext {
        id: theme
        colorSet: ColorContext.TabButton

        focused: control.visualFocus
        hovered: control.hovered
        pressed: control.down
        enabled: control.enabled
    }

    background: Widgets.AnimatedBackground {
        enabled: theme.initialized
        color: (control.checked || control.hovered || control.down)
            ? theme.bg.secondary : "transparent"
        border.color: visualFocus ? theme.visualFocus : "transparent"

        radius: control.radius

        Widgets.CurrentIndicator {
            anchors {
                left: parent.left
                leftMargin: VLCStyle.margin_xxxsmall
                verticalCenter: parent.verticalCenter
            }
            implicitHeight: parent.height - VLCStyle.margin_xsmall
            visible: control.checked && control.showText

            radius: VLCStyle.margin_xxxsmall
        }
    }

    contentItem: RowLayout {
        spacing: VLCStyle.margin_xsmall

        Item {
            Layout.preferredWidth: MainCtx.dp(control.showText ? 32 : 24)
            Layout.fillHeight: true

            Widgets.IconLabel {
                id: iconLabel

                visible: control.iconSource.toString().length === 0 && text.length > 0

                anchors.centerIn: parent

                text: control.iconTxt

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                color: (control.highlighted || control.checked) ? theme.accent : theme.fg.primary

                font.pixelSize: MainCtx.dp(24)
            }

            Image {
                visible: control.iconSource.toString().length > 0
                anchors.centerIn: parent
                width: MainCtx.dp(24)
                height: width
                fillMode: Image.PreserveAspectFit
                mirror: control.mirrorIcon
                source: visible ? SVGColorImage.colorize(control.iconSource)
                    .any({"#8F8F8F": (control.highlighted || control.checked)
                        ? theme.accent : theme.fg.primary}).uri() : ""
            }
        }

        T.Label {
            id: label

            Layout.fillWidth: true
            Layout.fillHeight: true

            text: control.text

            verticalAlignment: Text.AlignVCenter

            color: theme.fg.primary

            elide: Text.ElideRight

            visible: control.showText

            font.pixelSize: VLCStyle.fontSize_normal

            font.weight: Font.Normal

            //button text is already exposed
            Accessible.ignored: true

            Behavior on color {
                enabled: theme.initialized

                ColorAnimation {
                    duration: VLCStyle.duration_short
                }
            }
        }
    }
}
