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
import QtQuick.Layouts
import QtQuick.Controls.Basic


import VLC.MainInterface
import VLC.Player
import VLC.Style
import VLC.Widgets as Widgets
import VLC.Util

ColumnLayout {
    id: root

    property alias slider: slider
    property bool inlineMode: false

    signal radioButtonClicked(T.AbstractButton button)

    // Private

    // NOTE: 0.96 and 1.04 are useful for video enthusiasts.
    property var _values: [ 0.25, 0.5, 0.75, 0.96, 1.0, 1.04, 1.25, 1.5, 1.75, 2 ]

    property bool _update: true

    // FIXME: Currently we are not updating the ShiftModifier status while dragging. This could be
    //        fixed with a custom Slider based on a MouseArea.
    property bool _shiftPressed: false

    property real _value: 1.0

    property real _minimum: 0.25
    property real _maximum: 4.0

    property real _threshold: 0.03

    property color _color: (slider.visualFocus || slider.pressed) ? theme.accent
                                                                  : theme.fg.primary

    // Settings

    Layout.fillWidth: true
    Layout.fillHeight: true

    spacing: VLCStyle.margin_normal

    // Events

    Component.onCompleted: _updateValue(Player.rate)

    // Function

    function _updateValue(value) {
        _update = false

        _applySlider(value)

        _update = true
    }

    function _applySlider(value) {
        // Reverse retains the player's signed rate; slider geometry describes
        // its speed magnitude and must remain finite for supported rewind.
        value = 17 * Math.log(Math.abs(value)) / Math.log(2)

        if (value <= 1.0)
            slider.value = Math.max(slider.from, value)
        else
            slider.value = Math.min(value, slider.to)
    }

    function sliderToSpeed(value) {
        return Math.pow(2, value / 17)
    }

    function _applyPlayer(value) {
        if (_update === false)
            return

        value = sliderToSpeed(value)

        if (_shiftPressed === false) {
            for (let i = 0; i < _values.length; i++) {
                const clamp = _values[i]

                if (_testClamp(value, clamp)) {
                    value = clamp

                    break
                }
            }
        }

        _update = false

        Player.rate = value

        _update = true
    }

    function _testClamp(value, target) {
        return (Math.abs(value - target) < _threshold)
    }

    // Connections

    Connections {
        target: Player

        function onRateChanged() {
            _updateValue(Player.rate)
        }
    }

    // Children

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.Window
    }

    Widgets.SubtitleLabel {
        id: label

        Layout.fillWidth: true

        Layout.alignment: Qt.AlignTop

        text: qsTr("Playback Speed")

        AccessibleCompat.id: "playbackSpeedLabel"

        color: theme.fg.primary
        visible: !root.inlineMode
    }

    RowLayout {
        visible: root.inlineMode
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: VLCStyle.margin_xsmall
        Widgets.MenuCaption {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            // Source: Figma playback row5187:24541 uses Speed at14px.
            text: qsTr("Speed")
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            color: theme.fg.secondary
        }
        Widgets.TextFieldExt {
            id: rateValue
            Layout.preferredWidth: VLCStyle.dp(140, VLCStyle.scale)
            Layout.maximumWidth: VLCStyle.dp(140, VLCStyle.scale)
            Layout.minimumWidth: 0
            implicitHeight: VLCStyle.dp(32, VLCStyle.scale)
            rightPadding: VLCStyle.dp(24, VLCStyle.scale)
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            selectByMouse: true
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            Accessible.name: qsTr("Playback speed")
            Navigation.parentItem: root
            Navigation.downItem: slider
            validator: DoubleValidator { bottom: root._minimum; top: root._maximum; decimals: 3 }
            onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
            Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
            onEditingFinished: {
                const value = Number.fromLocaleString(Qt.locale(), text)
                if (Number.isFinite(value) && value >= root._minimum && value <= root._maximum)
                    Player.rate = value
            }
            Binding on text {
                when: !rateValue.activeFocus
                restoreMode: Binding.RestoreNone
                value: Number(Player.rate).toLocaleString(Qt.locale(), 'g', 6)
            }
            Widgets.MenuCaption {
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(10, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                // Source: Figma row5187:24543's rate suffix. Its numeric value
                // always comes from Player.rate, including the original4×range.
                text: "x"
                color: theme.fg.secondary
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                Accessible.ignored: true
            }
        }
    }

    Item {
        id: rowA

        Layout.fillWidth: true

        Layout.alignment: Qt.AlignTop

        Navigation.parentItem: root
        Navigation.upItem: root.inlineMode ? rateValue : null
        Navigation.downItem: slider

        Widgets.CaptionLabel {
            anchors.verticalCenter: parent.verticalCenter

            text: qsTr("0.25")

            color: theme.fg.primary

            font.pixelSize: VLCStyle.fontSize_normal
        }

        Widgets.CaptionLabel {
            anchors.right: parent.right

            anchors.verticalCenter: parent.verticalCenter

            text: qsTr("4.00")

            color: theme.fg.primary

            font.pixelSize: VLCStyle.fontSize_normal
        }
    }

    Widgets.SliderExt {
        id: slider

        Layout.fillWidth: true

        topPadding: 0

        // NOTE: These values come from the VLC 3.x implementation.
        from: -34
        to: 34

        stepSize: 1

        wheelEnabled: true

        toolTipTextProvider: function (value) {
            return sliderToSpeed(value).toFixed(2)
        }

        toolTipFollowsMouse: true

        Accessible.name: qsTr("Playback speed")
        AccessibleCompat.id: "playbackSpeedSlider"

        Navigation.parentItem: root
        Navigation.upItem: root.inlineMode ? rateValue : null

        Keys.priority: Keys.AfterItem
        Keys.onPressed: (event) => Navigation.defaultKeyAction(event)

        onValueChanged: root._applyPlayer(value)

        MouseArea {
            anchors.fill: parent

            acceptedButtons: Qt.LeftButton

            onPressed: (mouse) => {
                mouse.accepted = false

                root._shiftPressed = (mouse.modifiers === Qt.ShiftModifier)
            }
        }

        Rectangle {
            id: tickmark

            parent: slider.background
            x: parent.width * .5
            width: VLCStyle.dp(1, VLCStyle.scale)
            height: parent.height
            visible: root.sliderToSpeed(slider.value) !== 1
            color: {
                const theme = slider.colorContext
                return root.sliderToSpeed(slider.value) > 1 ? theme.fg.negative : theme.fg.primary
            }
        }
    }

    Widgets.ListLabel {
        visible: !root.inlineMode
        text: qsTr("Presets:")
        color: colorContext.fg.primary
        Layout.fillWidth: true
    }

    GridLayout {
        visible: !root.inlineMode
        Layout.fillWidth: true
        Layout.fillHeight: true

        rows: radioButtonRepeater.count / 2 // two columns
        flow: GridLayout.TopToBottom

        rowSpacing: VLCStyle.margin_small
        columnSpacing: VLCStyle.margin_small

        ButtonGroup {
            id: buttonGroup

            onClicked: function(button /* : AbstractButton */) {
                Player.rate = button.modelData
                root.radioButtonClicked(button)
            }
        }

        Repeater {
            id: radioButtonRepeater

            model: root._values

            delegate: Widgets.RadioButtonExt {
                required property double modelData

                Layout.fillWidth: true

                text: modelData

                checked: Math.abs(Player.rate - modelData) < 0.01 // need some generous epsilon here

                padding: 0 // we use spacing instead of paddings here

                ButtonGroup.group: buttonGroup
            }
        }
    }
}
