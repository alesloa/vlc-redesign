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


import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Util

T.ToolButton {
    id: control

    // Properties

    property bool paintOnly: false

    required property string description

    // Original 24px SVG artwork from the owner's Figma file can replace the
    // icon font while keeping this button's existing interaction behavior.
    property url iconSource: ""
    property bool mirrorIcon: false

    property color color: (control.checked) ? theme.accent : theme.fg.primary

    property color backgroundColor: (hovered || down) ? theme.bg.primary : "transparent"

    property real radius: VLCStyle.button_radius

    // Settings

    padding: 0

    enabled: !paintOnly

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    baselineOffset: contentItem.y + contentItem.baselineOffset

    font.pixelSize: VLCStyle.icon_toolbar
    font.family: VLCIcons.fontFamily

    // Keys

    Keys.priority: Keys.AfterItem

    Keys.onPressed: (event) => Navigation.defaultKeyAction(event)

    // Accessible

    Accessible.onPressAction: control.clicked()

    Accessible.name: description

    // Tooltip

    T.ToolTip.visible: (hovered || visualFocus)

    T.ToolTip.delay: VLCStyle.delayToolTipAppear

    T.ToolTip.text: description

    // Events

    Component.onCompleted: console.assert(text !== "" || iconSource.toString() !== "", "text is empty")

    // Children

    readonly property ColorContext colorContext : ColorContext {
        id: theme
        colorSet: ColorContext.ToolButton

        enabled: control.paintOnly || control.enabled
        focused: control.visualFocus
        hovered: control.hovered
        pressed: control.down
    }

    background: Widgets.AnimatedBackground {
        implicitWidth: control.font.pixelSize
        implicitHeight: control.font.pixelSize

        enabled: theme.initialized

        color: control.backgroundColor

        border.color: visualFocus ? theme.visualFocus : "transparent"

        radius: control.radius
    }

    contentItem: Item {
        implicitWidth: control.iconSource.toString() !== "" ? MainCtx.dp(24, VLCStyle.scale) : label.implicitWidth
        implicitHeight: control.iconSource.toString() !== "" ? MainCtx.dp(24, VLCStyle.scale) : label.implicitHeight
        baselineOffset: label.baselineOffset

        Image {
            anchors.centerIn: parent
            width: MainCtx.dp(24, VLCStyle.scale)
            height: MainCtx.dp(24, VLCStyle.scale)
            sourceSize: Qt.size(width, height)
            visible: control.iconSource.toString() !== ""
            mirror: control.mirrorIcon
            source: visible ? SVGColorImage.colorize(control.iconSource)
                         .any({"#8F8F8F": control.color, "#161616": control.color,
                               "#6B6B6B": control.color}).uri() : ""
            Accessible.ignored: true
        }

        Widgets.IconLabel {
            id: label
            anchors.fill: parent
            visible: control.iconSource.toString() === ""
            text: control.text

            color: control.color

            DelayedBehavior on color {
                delayedEnabled: theme.initialized

                ColorAnimation {
                    duration: VLCStyle.duration_long
                }
            }

            font: control.font
        }
    }
}
