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
import VLC.Player
import VLC.Util
import VLC.Widgets as Widgets

TracksPage {
    id: root
    initialFocusItem: spinBoxA

    // Functions

    function textFromValueA(value, locale) {
        return qsTr("%1 ms").arg(Number(value).toLocaleString(locale, 'f', 0))
    }

    function valueFromTextA(text, locale) {
        return Number.fromLocaleString(locale, text.substring(0, text.length - 3))
    }

    function textFromValueB(value, locale) {
        return qsTr("%1 fps").arg(Number(value / 1000).toLocaleString(locale, 'f', 3))
    }

    function valueFromTextB(text, locale) {
        return Number.fromLocaleString(locale, text.substring(0, text.length - 4)) * 1000
    }

    // Children

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        spacing: VLCStyle.margin_xsmall

        Widgets.SubtitleLabel {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: root.inlineMode ? VLCStyle.dp(14, VLCStyle.scale) : VLCStyle.fontSize_xxxlarge
            font.weight: root.inlineMode ? Font.Normal : Font.Bold

            text: qsTr("Subtitle synchronization")

            color: root.colorContext.fg.primary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: VLCStyle.margin_large

            spacing: VLCStyle.margin_xxxsmall

            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Primary subtitle delay")

            DelayEstimator {
                id: delayEstimatorPrimary

                onDelayChanged: {
                    Player.addSubtitleDelay(delayEstimatorPrimary.delay)
                }
            }

            GridLayout {
                id: primaryDelayGrid
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= primaryDelayCaption.implicitWidth + spinBoxA.implicitWidth + resetA.implicitWidth + columnSpacing * 2 ? 3 : 2
                columnSpacing: VLCStyle.margin_xsmall
                rowSpacing: VLCStyle.margin_xsmall

                Widgets.MenuCaption {
                    id: primaryDelayCaption
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.columnSpan: primaryDelayGrid.columns === 3 ? 1 : 2
                    Layout.alignment: Qt.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone

                    text: qsTr("Primary subtitle delay")

                    color: root.colorContext.fg.primary
                }

                Widgets.SpinBoxExt {
                    id: spinBoxA

                    property bool update: false

                    Layout.preferredWidth: VLCStyle.dp(128, VLCStyle.scale)
                    Layout.minimumWidth: 0

                    stepSize: 50
                    from: -10000
                    to: 10000

                    textFromValue: root.textFromValueA
                    valueFromText: root.valueFromTextA

                    Navigation.parentItem: root
                    Navigation.rightItem: resetA

                    Component.onCompleted: {
                        spinBoxA.value = Player.subtitleDelayMS

                        spinBoxA.update = true
                    }

                    onValueChanged: {
                        if (update === false)
                            return

                        Player.subtitleDelayMS = spinBoxA.value
                    }

                    Connections {
                        target: Player

                        function onSubtitleDelayChanged() {
                            spinBoxA.update = false

                            spinBoxA.value = Player.subtitleDelayMS

                            spinBoxA.update = true
                        }

                    }
                }

                Widgets.TextToolButton {
                    id: resetA

                    text: qsTr("Reset")

                    focus: true

                    Navigation.parentItem: root
                    Navigation.leftItem: spinBoxA
                    Navigation.downItem: resetB

                    onClicked: {
                        Player.subtitleDelayMS = 0
                        delayEstimatorPrimary.reset()
                    }
                }
            }

            Widgets.SliderExt {
                id: delaySlider
                Layout.fillWidth: true
                from: -10000
                to: 10000
                stepSize: 50
                Accessible.name: qsTr("Primary subtitle delay")
                toolTipTextProvider: (value) => root.textFromValueA(value, Qt.locale())
                onMoved: Player.subtitleDelayMS = Math.round(value)
                Binding on value {
                    when: !delaySlider.pressed
                    restoreMode: Binding.RestoreNone
                    value: Player.subtitleDelayMS
                }
                Navigation.parentItem: root
                Navigation.upItem: spinBoxA
                Navigation.downItem: voiceHeardA
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignRight
                columns: width >= voiceHeardA.implicitWidth + textSeenA.implicitWidth + columnSpacing ? 2 : 1
                columnSpacing: VLCStyle.margin_small
                rowSpacing: VLCStyle.margin_xsmall

                Widgets.TrackDelayButton {
                    id: voiceHeardA
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    iconTxt: VLCIcons.check
                    text: qsTr("Voice Heard")
                    selected: delayEstimatorPrimary.isHeardTimeMarked

                    onClicked: {
                        delayEstimatorPrimary.markHeardTime()
                        if (!delayEstimatorPrimary.isSpottedTimeMarked && delayEstimatorPrimary.isHeardTimeMarked)
                            textSeenA.animate()
                    }
                }

                Widgets.TrackDelayButton {
                    id: textSeenA
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    iconTxt: VLCIcons.check
                    text: qsTr("Text Seen")
                    selected: delayEstimatorPrimary.isSpottedTimeMarked

                    onClicked: {
                        delayEstimatorPrimary.markSpottedTime()
                        if (!delayEstimatorPrimary.isHeardTimeMarked && delayEstimatorPrimary.isSpottedTimeMarked)
                            voiceHeardA.animate()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true

            spacing: VLCStyle.margin_xxxsmall

            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Secondary subtitle delay")

            DelayEstimator {
                id: delayEstimatorSecondary

                onDelayChanged: {
                    Player.addSecondarySubtitleDelay(delayEstimatorSecondary.delay)
                }
            }

            GridLayout {
                id: secondaryDelayGrid
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= secondaryDelayCaption.implicitWidth + spinBoxB.implicitWidth + resetB.implicitWidth + columnSpacing * 2 ? 3 : 2
                columnSpacing: VLCStyle.margin_xsmall
                rowSpacing: VLCStyle.margin_xsmall

                Widgets.MenuCaption {
                    id: secondaryDelayCaption
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.columnSpan: secondaryDelayGrid.columns === 3 ? 1 : 2
                    Layout.alignment: Qt.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone

                    text: qsTr("Secondary subtitle delay")

                    color: root.colorContext.fg.primary
                }

                Widgets.SpinBoxExt {
                    id: spinBoxB

                    property bool update: false

                    Layout.preferredWidth: VLCStyle.dp(128, VLCStyle.scale)
                    Layout.minimumWidth: 0

                    stepSize: 50
                    from: -10000
                    to: 10000

                    textFromValue: root.textFromValueA
                    valueFromText: root.valueFromTextA

                    Navigation.parentItem: root
                    Navigation.rightItem: resetB

                    Component.onCompleted: {
                        value = Player.secondarySubtitleDelayMS

                        update = true
                    }

                    onValueChanged: {
                        if (update === false)
                            return

                        Player.secondarySubtitleDelayMS = spinBoxB.value
                    }

                    Connections {
                        target: Player

                        function onSecondarySubtitleDelayChanged() {
                            spinBoxB.update = false

                            spinBoxB.value = Player.secondarySubtitleDelayMS

                            spinBoxB.update = true
                        }
                    }
                }

                Widgets.TextToolButton {
                    id: resetB

                    text: qsTr("Reset")

                    Navigation.parentItem: root
                    Navigation.leftItem: spinBoxB
                    Navigation.upItem: resetA
                    Navigation.downItem: resetC

                    onClicked: {
                        Player.secondarySubtitleDelayMS = 0
                        delayEstimatorSecondary.reset()
                    }
                }
            }

            Widgets.SliderExt {
                id: secondaryDelaySlider
                Layout.fillWidth: true
                from: -10000
                to: 10000
                stepSize: 50
                Accessible.name: qsTr("Secondary subtitle delay")
                toolTipTextProvider: (value) => root.textFromValueA(value, Qt.locale())
                onMoved: Player.secondarySubtitleDelayMS = Math.round(value)
                Binding on value {
                    when: !secondaryDelaySlider.pressed
                    restoreMode: Binding.RestoreNone
                    value: Player.secondarySubtitleDelayMS
                }
                Navigation.parentItem: root
                Navigation.upItem: spinBoxB
                Navigation.downItem: voiceHeardB
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignRight
                columns: width >= voiceHeardB.implicitWidth + textSeenB.implicitWidth + columnSpacing ? 2 : 1
                columnSpacing: VLCStyle.margin_xsmall
                rowSpacing: VLCStyle.margin_xsmall

                Widgets.TrackDelayButton {
                    id: voiceHeardB
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    text: qsTr("Voice Heard")
                    iconTxt: VLCIcons.check
                    selected: delayEstimatorSecondary.isHeardTimeMarked

                    onClicked: {
                        delayEstimatorSecondary.markHeardTime()
                        if (!delayEstimatorSecondary.isSpottedTimeMarked && delayEstimatorSecondary.isHeardTimeMarked)
                            textSeenB.animate()
                    }
                }

                Widgets.TrackDelayButton {
                    id: textSeenB
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    text: qsTr("Text Seen")
                    iconTxt: VLCIcons.check
                    selected: delayEstimatorSecondary.isSpottedTimeMarked

                    onClicked: {
                        delayEstimatorSecondary.markSpottedTime()
                        if (!delayEstimatorSecondary.isHeardTimeMarked && delayEstimatorSecondary.isSpottedTimeMarked)
                            voiceHeardB.animate()
                    }
                }
            }
        }

        GridLayout {
            id: subtitleSpeedGrid
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: width >= subtitleSpeedCaption.implicitWidth + spinBoxC.implicitWidth + resetC.implicitWidth + columnSpacing * 2 ? 3 : 2
            columnSpacing: VLCStyle.margin_xsmall
            rowSpacing: VLCStyle.margin_xsmall

            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Subtitle Speed")

            Widgets.MenuCaption {
                id: subtitleSpeedCaption
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.columnSpan: subtitleSpeedGrid.columns === 3 ? 1 : 2
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideNone

                text: qsTr("Subtitle Speed")

                color: root.colorContext.fg.primary
            }

            Widgets.SpinBoxExt {
                id: spinBoxC

                property bool update: false

                Layout.preferredWidth: VLCStyle.dp(128, VLCStyle.scale)
                Layout.minimumWidth: 0

                // Source: sub-fps defaults to 0 (automatic); SyncControls uses
                // a 100 fps maximum, three decimals, and a 0.2 fps step.
                // Keep integer SpinBox units in thousandths.
                stepSize: 200
                from: 0
                to: 100000

                textFromValue: root.textFromValueB
                valueFromText: root.valueFromTextB

                Navigation.parentItem: root
                Navigation.rightItem: resetC

                Component.onCompleted: {
                    value = Player.subtitleFPS * 1000

                    update = true
                }

                onValueChanged: {
                    if (update === false)
                        return

                    Player.subtitleFPS = value / 1000
                }

                Connections {
                    target: Player

                    function onSubtitleFPSChanged() {
                        spinBoxC.update = false

                        spinBoxC.value = Player.subtitleFPS * 1000

                        spinBoxC.update = true
                    }
                }
            }

            Widgets.TextToolButton {
                id: resetC

                text: qsTr("Reset")

                onClicked: spinBoxC.value = 0

                Navigation.parentItem: root
                Navigation.leftItem: spinBoxC
                Navigation.upItem: resetB
            }
        }
    }
}
