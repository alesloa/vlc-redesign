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
import QtQuick.Templates as T


import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Player
import VLC.Playlist
import VLC.Util

T.Control {
    id: root

    // Properties

    property bool paintOnly: false

    readonly property ColorContext colorContext: ColorContext {
        id: theme

        colorSet: ColorContext.ToolButton

        enabled: root.enabled || root.paintOnly
        focused: root.activeFocus
        hovered: root.cursorInside
        pressed: mouseArea.containsPress
    }

    property bool _keyOkPressed: false

    // Aliases

    property alias cursorInside: mouseArea.cursorInside

    // Settings

    implicitWidth: implicitBackgroundWidth + leftInset + rightInset
    implicitHeight: implicitBackgroundHeight + topInset + bottomInset

    scale: (_keyOkPressed || (mouseArea.pressed && cursorInside)) ? 0.95
                                                                  : 1.00

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Play/Pause")
    AccessibleCompat.id: "playButton"
    Accessible.checkable: true
    Accessible.checked: Player.playingState !== Player.PLAYING_STATE_PAUSED
                        && Player.playingState !== Player.PLAYING_STATE_STOPPED
    Accessible.onPressAction: MainPlaylistController.togglePlayPause()
    Accessible.onToggleAction: MainPlaylistController.togglePlayPause()

    // Tooltip

    T.ToolTip.visible: (hovered || visualFocus)
    T.ToolTip.delay: VLCStyle.delayToolTipAppear
    T.ToolTip.text: root.Accessible.name

    // States

    states: [
        State {
            name: "hovered"
            when: cursorInside

            PropertyChanges {
                target: hoverShadow
                opacity: 1.0
            }
        }
    ]

    transitions: Transition {
        from: ""; to: "*"
        reversible: true
        NumberAnimation {
            properties: "opacity"
            easing.type: Easing.InOutSine
            duration: VLCStyle.duration_veryShort
        }
    }

    // Keys

    Keys.onPressed: (event) => {
        if (KeyHelper.matchOk(event) ) {
            if (!event.isAutoRepeat) {
                _keyOkPressed = true
                keyHoldTimer.restart()
                innerRectangle.state = "diminished"
            }
            event.accepted = true
        }
        Navigation.defaultKeyAction(event)
    }

    Keys.onReleased: (event) => {
        if (KeyHelper.matchOk(event)) {
            if (!event.isAutoRepeat) {
                _keyOkPressed = false
                keyHoldTimer.stop()
                innerRectangle.state = ""
                if (Player.playingState !== Player.PLAYING_STATE_STOPPED)
                    MainPlaylistController.togglePlayPause()
            }
            event.accepted = true
        }
    }

    // Functions

    function _pressAndHoldAction() {
        innerRectangle.state = ""
        _keyOkPressed = false
        MainPlaylistController.stop()
    }

    // Children

    Timer {
        id: keyHoldTimer

        interval: mouseArea.pressAndHoldInterval
        repeat: false

        Component.onCompleted: {
            triggered.connect(_pressAndHoldAction)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent

        hoverEnabled: true

        readonly property bool cursorInside: containsMouse

        onCursorInsideChanged: {
            if (pressed && !cursorInside) {
                // Press and hold action can no longer be done,
                // so reset the state in order to reset the
                // animation:
                innerRectangle.state = ""
            }
        }

        onPressed: (mouse) => {
            if (!cursorInside) {
                mouse.accepted = false
                return
            }

            root.forceActiveFocus(Qt.MouseFocusReason)
            innerRectangle.state = "diminished"
        }

        onReleased: {
            innerRectangle.state = ""
        }

        onClicked: (mouse) => {
            MainPlaylistController.togglePlayPause()
            mouse.accepted = true
        }

        onPressAndHold: (mouse) => {
            if (!cursorInside) {
                mouse.accepted = false
                return
            }

            _pressAndHoldAction()
            mouse.accepted = true
        }
    }

    contentItem: Item {
        Accessible.ignored: true

        readonly property ColorContext colorContext: ColorContext {
            id: playTheme
            colorSet: ColorContext.ButtonAccent
            enabled: root.enabled || root.paintOnly
            hovered: root.cursorInside
            pressed: mouseArea.containsPress
        }

        Image {
            anchors.centerIn: parent
            width: VLCStyle.dp(24, VLCStyle.scale)
            height: VLCStyle.dp(24, VLCStyle.scale)
            sourceSize: Qt.size(width, height)
            source: {
                const state = Player.playingState
                const paused = !root.paintOnly && state !== Player.PLAYING_STATE_PAUSED
                                                && state !== Player.PLAYING_STATE_STOPPED
                const icon = paused ? "qrc:///redesign/icons/pause.svg" : "qrc:///redesign/icons/play.svg"
                return SVGColorImage.colorize(icon).any({"#161616": playTheme.fg.primary}).uri()
            }
        }
    }

    background: Item {
        implicitWidth: VLCStyle.dp(54, VLCStyle.scale)
        implicitHeight: VLCStyle.dp(28, VLCStyle.scale)

        Widgets.AnimatedBackground {
            anchors.fill: parent
            anchors.margins: -border.width * 2

            radius: VLCStyle.dp(6, VLCStyle.scale)
            border.pixelAligned: false

            enabled: theme.initialized

            border.color: root.visualFocus ? theme.visualFocus : Qt.alpha(theme.visualFocus, 0.0)
        }

        Rectangle {
            anchors.fill: parent

            radius: VLCStyle.dp(6, VLCStyle.scale)
            color: theme.accent

            Widgets.RoundedRectangleShadow {
                id: hoverShadow

                visible: opacity > 0
                opacity: 0

                blurRadius: VLCStyle.dp(4, VLCStyle.scale)
                yOffset: 0

                color: theme.accent.alpha(0.29)
            }

            Rectangle {
                id: innerRectangle

                color: theme.accent

                anchors.fill: parent
                anchors.margins: _diminished ? (parent.width / 2)
                                             : VLCStyle.dp(1, VLCStyle.scale)

                radius: VLCStyle.dp(5, VLCStyle.scale)

                property bool _diminished: false

                onStateChanged: {
                    if (state === "diminished") {
                        marginBehavior.enabled = true
                        bindingTimer.start()
                    } else {
                        bindingTimer.stop()
                        marginBehavior.enabled = false
                        _diminished = false
                    }
                }

                Timer {
                    // Do not immediately start the animation.
                    // Give some time if the intention is not
                    // to hold the button.
                    id: bindingTimer
                    interval: mouseArea.pressAndHoldInterval / 3
                    onTriggered: innerRectangle._diminished = true
                }

                Behavior on anchors.margins {
                    id: marginBehavior
                    NumberAnimation {
                        // Press and hold action must be triggered
                        // as soon as the inner rectangle diminishes.
                        // Subtract the interval here so that we satisfy
                        // that condition.
                        duration: mouseArea.pressAndHoldInterval - bindingTimer.interval
                    }
                }
            }
        }
    }
}
