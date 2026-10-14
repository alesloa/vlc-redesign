/*****************************************************************************
 * Copyright (C) 2022 VLC authors and VideoLAN
 *
 * Authors: Benjamin Arnaud <bunjee@omega.gg>
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


import VLC.MainInterface
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets
import VLC.Player

TracksPage {
    id: root
    initialFocusItem: spinBox

    // Functions

    function textFromValue(value, locale) {
        return qsTr("%1 ms").arg(Number(value).toLocaleString(locale, 'f', 0))
    }

    function valueFromText(text, locale) {
        return Number.fromLocaleString(locale, text.substring(0, text.length - 3))
    }

    // Children

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        spacing: VLCStyle.margin_xxsmall

        Widgets.SubtitleLabel {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: root.inlineMode ? VLCStyle.dp(14, VLCStyle.scale) : VLCStyle.fontSize_xxxlarge
            font.weight: root.inlineMode ? Font.Normal : Font.Bold

            text: qsTr("Audio track synchronization")

            color: root.colorContext.fg.primary
        }

        GridLayout {
            id: delayGrid
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.topMargin: VLCStyle.margin_large

            columns: width >= delayCaption.implicitWidth + spinBox.implicitWidth + reset.implicitWidth + columnSpacing * 2 ? 3 : 2
            columnSpacing: VLCStyle.margin_xsmall
            rowSpacing: VLCStyle.margin_xsmall

            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Audio track delay")

            DelayEstimator {
                id: delayEstimator
                onDelayChanged: Player.addAudioDelay(delayEstimator.delay)
            }

            Widgets.MenuCaption {
                id: delayCaption
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.columnSpan: delayGrid.columns === 3 ? 1 : 2
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideNone

                text: qsTr("Audio track delay")

                color: root.colorContext.fg.primary
            }

            Widgets.SpinBoxExt {
                id: spinBox

                property bool update: false

                Layout.preferredWidth: VLCStyle.dp(128, VLCStyle.scale)
                Layout.minimumWidth: 0

                stepSize: 50
                from: -10000
                to: 10000

                textFromValue: root.textFromValue
                valueFromText: root.valueFromText

                Navigation.parentItem: root
                Navigation.rightItem: reset

                Component.onCompleted: {
                    value = Player.audioDelayMS

                    update = true
                }

                onValueChanged: {
                    if (update === false)
                        return

                    Player.audioDelayMS = value
                }

                Connections {
                    target: Player

                    function onAudioDelayChanged() {
                        spinBox.update = false

                        spinBox.value = Player.audioDelayMS

                        spinBox.update = true
                    }
                }
            }

            Widgets.ActionButtonOverlay {
                id: reset

                text: qsTr("Reset")

                onClicked: {
                    Player.audioDelayMS = 0
                    delayEstimator.reset()
                }

                Navigation.parentItem: root
                Navigation.leftItem: spinBox
            }
        }

        Widgets.SliderExt {
            id: delaySlider
            Layout.fillWidth: true
            from: -10000
            to: 10000
            stepSize: 50
            Accessible.name: qsTr("Audio track delay")
            toolTipTextProvider: (value) => root.textFromValue(value, Qt.locale())
            onMoved: Player.audioDelayMS = Math.round(value)
            Binding on value {
                when: !delaySlider.pressed
                restoreMode: Binding.RestoreNone
                value: Player.audioDelayMS
            }
            Navigation.parentItem: root
            Navigation.upItem: spinBox
            Navigation.downItem: soundHeard
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignRight
            columns: width >= soundHeard.implicitWidth + soundSpotted.implicitWidth + columnSpacing ? 2 : 1
            columnSpacing: VLCStyle.margin_xsmall
            rowSpacing: VLCStyle.margin_xsmall

            Widgets.TrackDelayButton {
                id: soundHeard
                Layout.fillWidth: true
                Layout.minimumWidth: 0

                text: qsTr("Sound Heard")
                iconTxt: VLCIcons.check
                selected: delayEstimator.isSpottedTimeMarked

                onClicked: {
                    delayEstimator.markSpottedTime() //method name should be changed
                    if (!delayEstimator.isHeardTimeMarked && delayEstimator.isSpottedTimeMarked)
                        soundSpotted.animate()
                }
            }

            Widgets.TrackDelayButton {
                id: soundSpotted
                Layout.fillWidth: true
                Layout.minimumWidth: 0

                text: qsTr("Sound Spotted")
                iconTxt: VLCIcons.check
                selected: delayEstimator.isHeardTimeMarked

                onClicked: {
                    delayEstimator.markHeardTime() //method name should be changed
                    if (!delayEstimator.isSpottedTimeMarked && delayEstimator.isHeardTimeMarked)
                        soundHeard.animate()
                }
            }
        }
    }
}
