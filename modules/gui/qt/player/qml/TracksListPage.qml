
/*****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
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
import QtQml.Models


import VLC.MainInterface
import VLC.Style
import VLC.Player
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Dialogs

// Labels reuse VLC's existing menus/preferences and the owner's four-tab brief.
// Tracks, output devices, video choices, delays, rate and metadata all come from Player.
ColumnLayout {
    id: root

    required property QtObject trackMenuController
    property int currentTab: trackMenuController.initialTab
    readonly property int preferredWidth: VLCStyle.dp(400, VLCStyle.scale)

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    InterfaceOptionsModel { id: subtitleOptions; ctx: MainCtx; group: InterfaceOptionsModel.SubtitleFormatting }
    InterfaceOptionsModel { id: audioOptions; ctx: MainCtx; group: InterfaceOptionsModel.AudioEqualizer }
    InterfaceOptionsModel { id: transformOptions; ctx: MainCtx; group: InterfaceOptionsModel.TransformFilter }
    InterfaceOptionsModel { id: rotateOptions; ctx: MainCtx; group: InterfaceOptionsModel.RotateFilter }
    InterfaceOptionsModel { id: audioDefaults; ctx: MainCtx; group: InterfaceOptionsModel.AudioDefaults }
    InterfaceOptionsModel { id: equalizerOptions; ctx: MainCtx; group: InterfaceOptionsModel.EqualizerFilter }
    InterfaceOptionsModel { id: compressorOptions; ctx: MainCtx; group: InterfaceOptionsModel.CompressorFilter }
    InterfaceOptionsModel { id: spatializerOptions; ctx: MainCtx; group: InterfaceOptionsModel.SpatializerFilter }
    InterfaceOptionsModel { id: widenerOptions; ctx: MainCtx; group: InterfaceOptionsModel.StereoWidenerFilter }
    InterfaceOptionsModel { id: pitchOptions; ctx: MainCtx; group: InterfaceOptionsModel.PitchFilter }
    InterfaceOptionsModel { id: adjustmentOptions; ctx: MainCtx; group: InterfaceOptionsModel.AdjustmentFilter }
    InterfaceOptionsModel { id: sharpenOptions; ctx: MainCtx; group: InterfaceOptionsModel.SharpenFilter }
    InterfaceOptionsModel { id: bandingOptions; ctx: MainCtx; group: InterfaceOptionsModel.BandingFilter }
    InterfaceOptionsModel { id: grainOptions; ctx: MainCtx; group: InterfaceOptionsModel.GrainFilter }
    InterfaceOptionsModel { id: cropOptions; ctx: MainCtx; group: InterfaceOptionsModel.CropFilter }
    InterfaceOptionsModel { id: extractionOptions; ctx: MainCtx; group: InterfaceOptionsModel.ExtractionFilter }
    InterfaceOptionsModel { id: thresholdOptions; ctx: MainCtx; group: InterfaceOptionsModel.ColorThresholdFilter }
    InterfaceOptionsModel { id: negateOptions; ctx: MainCtx; group: InterfaceOptionsModel.NegateFilter }
    InterfaceOptionsModel { id: posterizeOptions; ctx: MainCtx; group: InterfaceOptionsModel.PosterizeFilter }
    InterfaceOptionsModel { id: gradientOptions; ctx: MainCtx; group: InterfaceOptionsModel.GradientFilter }
    InterfaceOptionsModel { id: sepiaOptions; ctx: MainCtx; group: InterfaceOptionsModel.SepiaFilter }

    spacing: VLCStyle.dp(1, VLCStyle.scale)
    focus: true
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Extended settings")
    onActiveFocusChanged: if (activeFocus) tabs.forceActiveFocus()

    Widgets.NavigableRow {
        id: tabs

        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: VLCStyle.dp(50, VLCStyle.scale)
        leftPadding: VLCStyle.dp(6, VLCStyle.scale)
        rightPadding: leftPadding
        spacing: VLCStyle.dp(1, VLCStyle.scale)
        readonly property bool compact: availableWidth < VLCStyle.dp(360, VLCStyle.scale)
        readonly property real longTabWidth: (availableWidth - VLCStyle.dp(170, VLCStyle.scale) - spacing * 3) / 2
        readonly property real compactTabWidth: Math.max(0, (availableWidth - spacing * 3) / 4)

        Navigation.parentItem: root
        Navigation.downItem: settingsFlick

        SettingsTab {
            text: qsTr("Playback")
            sourceName: "playback"
            width: tabs.compact ? tabs.compactTabWidth : tabs.longTabWidth
            checked: root.currentTab === 3
            onClicked: root.currentTab = 3
        }
        SettingsTab {
            text: qsTr("Video")
            sourceName: "video"
            mirrorIcon: true
            width: tabs.compact ? tabs.compactTabWidth : VLCStyle.dp(85, VLCStyle.scale)
            checked: root.currentTab === 2
            onClicked: root.currentTab = 2
        }
        SettingsTab {
            text: qsTr("Audio")
            sourceName: "audio"
            width: tabs.compact ? tabs.compactTabWidth : VLCStyle.dp(85, VLCStyle.scale)
            checked: root.currentTab === 1
            onClicked: root.currentTab = 1
        }
        SettingsTab {
            text: qsTr("Subtitles")
            sourceName: "subtitles"
            width: tabs.compact ? tabs.compactTabWidth : tabs.longTabWidth
            checked: root.currentTab === 0
            onClicked: root.currentTab = 0
        }
    }

    Flickable {
        id: settingsFlick

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: VLCStyle.dp(20, VLCStyle.scale)
        Layout.rightMargin: VLCStyle.dp(20, VLCStyle.scale)
        contentWidth: width
        contentHeight: settingsContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        T.ScrollBar.vertical: Widgets.ScrollBarExt { }
        Navigation.parentItem: root
        Navigation.upItem: tabs
        onActiveFocusChanged: {
            if (!activeFocus)
                return
            if (tracksList.visible && tracksList.count > 0)
                tracksList.setCurrentItemFocus(Qt.TabFocusReason)
            else if (settingsLoader.item)
                settingsLoader.item.forceActiveFocus(Qt.TabFocusReason)
        }

        Connections {
            target: root
            function onCurrentTabChanged() { settingsFlick.contentY = 0 }
        }

        ColumnLayout {
            id: settingsContent
            width: settingsFlick.width
            spacing: VLCStyle.margin_normal

            TrackList {
                id: tracksList

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, VLCStyle.dp(160, VLCStyle.scale))
                visible: root.currentTab < 3 && count > 0
                tracksModel: root.currentTab === 0 ? Player.subtitleTracks
                            : root.currentTab === 1 ? Player.audioTracks : Player.videoTracks
                listTitle: qsTr("Track list")
                Navigation.parentItem: settingsFlick
                Navigation.upItem: tabs
                Navigation.downItem: trackActions
            }

            Widgets.NavigableRow {
                id: trackActions

                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.currentTab < 3
                spacing: VLCStyle.margin_xsmall
                Navigation.parentItem: settingsFlick
                Navigation.upItem: tracksList.visible ? tracksList : tabs
                Navigation.downItem: audioDevices.visible ? audioDevices : settingsLoader

                Widgets.ButtonExt {
                    text: qsTr("Add")
                    iconTxt: VLCIcons.add
                    onClicked: {
                        if (root.currentTab === 0)
                            DialogsProvider.loadSubtitlesFile()
                        else if (root.currentTab === 1)
                            DialogsProvider.loadAudioFile()
                        else
                            DialogsProvider.loadVideoFile()
                    }
                }
                Widgets.ButtonExt {
                    text: qsTr("Menu")
                    iconTxt: VLCIcons.expand
                    visible: root.currentTab !== 2
                    onClicked: {
                        const menuPos = mapToGlobal(0, height)
                        if (root.currentTab === 0)
                            menuSubtitle.popup(menuPos)
                        else
                            menuAudio.popup(menuPos)
                    }
                }
            }

            ColumnLayout {
                id: audioDevices

                Layout.fillWidth: true
                visible: root.currentTab === 1 && deviceList.count > 0
                spacing: VLCStyle.margin_xxsmall
                Navigation.parentItem: settingsFlick
                Navigation.upItem: trackActions
                Navigation.downItem: settingsLoader
                onActiveFocusChanged: if (activeFocus) deviceList.setCurrentItemFocus(Qt.TabFocusReason)

                Widgets.CaptionLabel {
                    Layout.fillWidth: true
                    text: qsTr("Audio Device")
                    color: theme.fg.secondary
                }
                TrackList {
                    id: deviceList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, VLCStyle.dp(120, VLCStyle.scale))
                    tracksModel: Player.audioDevices
                    listTitle: qsTr("Audio Device")
                    Navigation.parentItem: audioDevices
                }
            }

            Loader {
                id: settingsLoader

                Layout.fillWidth: true
                Layout.preferredHeight: item?.implicitHeight ?? 0
                sourceComponent: root.currentTab === 0 ? subtitleSettings
                               : root.currentTab === 1 ? audioSettings
                               : root.currentTab === 2 ? videoSettings : playbackSettings
                Navigation.parentItem: settingsFlick
                Navigation.upItem: trackActions.visible ? trackActions : tabs
                onLoaded: item.Navigation.parentItem = settingsLoader
            }
        }
    }

    component SettingsTab: Widgets.ButtonExt {
        id: tabButton
        required property string sourceName
        property bool mirrorIcon: false
        height: VLCStyle.dp(50, VLCStyle.scale)
        implicitHeight: VLCStyle.dp(50, VLCStyle.scale)
        topPadding: VLCStyle.dp(14, VLCStyle.scale)
        bottomPadding: VLCStyle.dp(16, VLCStyle.scale)
        leftPadding: 0
        rightPadding: 0
        color: checked ? theme.fg.primary : theme.fg.secondary
        Accessible.name: text
        readonly property ColorContext tabTheme: ColorContext { colorSet: ColorContext.TextField }
        background: Rectangle {
            color: tabButton.tabTheme.bg.primary
            border.width: tabButton.visualFocus ? VLCStyle.dp(2, VLCStyle.scale) : 0
            border.color: theme.visualFocus
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                height: VLCStyle.dp(2, VLCStyle.scale)
                width: Math.max(0, parent.width - VLCStyle.dp(16, VLCStyle.scale))
                color: tabButton.checked ? theme.accent : "transparent"
            }
        }
        contentItem: Item {
            implicitWidth: tabContents.implicitWidth
            implicitHeight: VLCStyle.dp(20, VLCStyle.scale)
            Row {
                id: tabContents
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: VLCStyle.dp(8, VLCStyle.scale)
                Image {
                    width: VLCStyle.dp(20, VLCStyle.scale)
                    height: width
                    mirror: tabButton.mirrorIcon
                    source: SVGColorImage.colorize("qrc:///redesign/icons/player-tab-" + tabButton.sourceName + ".svg")
                             .any({"#6B6B6B": tabButton.color, "#8F8F8F": tabButton.color}).uri()
                }
                T.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !tabs.compact
                    text: tabButton.text
                    color: tabButton.color
                    font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                    font.weight: Font.Normal
                }
            }
        }
    }

    Component {
        id: subtitleSettings
        ColumnLayout {
            spacing: VLCStyle.margin_normal
            onActiveFocusChanged: if (activeFocus) (subtitleFormatting.visible ? subtitleFormatting : subtitleSync).forceActiveFocus(Qt.TabFocusReason)
            PlayerPresets { optionModels: [subtitleOptions]; section: InterfacePresetsModel.Subtitles; Layout.fillWidth: true }
            PlayerOptions {
                id: subtitleFormatting
                optionsModel: subtitleOptions
                Layout.fillWidth: true
                Navigation.upItem: trackActions
                Navigation.downItem: subtitleSync
            }
            TracksPageSubtitle {
                id: subtitleSync
                inlineMode: true
                trackMenuController: root.trackMenuController
                Layout.fillWidth: true
                Navigation.parentItem: parent
                Navigation.upItem: subtitleFormatting.visible ? subtitleFormatting : trackActions
                Navigation.downItem: subtitlePreferences
            }
            Widgets.ButtonExt {
                id: subtitlePreferences
                text: qsTr("Preferences")
                iconTxt: VLCIcons.settings
                onClicked: DialogsProvider.prefsDialog()
                Navigation.parentItem: parent
                Navigation.upItem: subtitleSync
            }
        }
    }

    Component {
        id: audioSettings
        ColumnLayout {
            spacing: VLCStyle.margin_normal
            onActiveFocusChanged: {
                if (activeFocus)
                    (stereoChoice.visible ? stereoChoice : mixChoice.visible ? mixChoice : audioSync).forceActiveFocus(Qt.TabFocusReason)
            }
            ChoiceControl {
                id: stereoChoice
                title: qsTr("Stereo Mode")
                choicesModel: Player.audioStereoMode
                visible: count > 0 && mixChoice.count === 0
                Navigation.parentItem: parent
                Navigation.downItem: mixChoice
            }
            ChoiceControl {
                id: mixChoice
                title: qsTr("Mix Mode")
                choicesModel: Player.audioMixMode
                Navigation.parentItem: parent
                Navigation.upItem: stereoChoice
                Navigation.downItem: audioSync
            }
            TracksPageAudio {
                id: audioSync
                inlineMode: true
                trackMenuController: root.trackMenuController
                Layout.fillWidth: true
                Navigation.parentItem: parent
                Navigation.upItem: mixChoice
                Navigation.downItem: audioEffects
            }
            Widgets.ButtonExt {
                id: audioEffects
                text: qsTr("Audio Effects")
                iconTxt: VLCIcons.effect_filter
                onClicked: DialogsProvider.audioEffectsDialog()
                Navigation.parentItem: parent
                Navigation.upItem: audioSync
            }
            PlayerOptions { optionsModel: audioDefaults; captionText: qsTr("Defaults"); Layout.fillWidth: true }
            PlayerPresets {
                optionModels: [audioDefaults, equalizerOptions, compressorOptions, spatializerOptions, widenerOptions, pitchOptions]
                section: InterfacePresetsModel.Audio
                Layout.fillWidth: true
            }
            Widgets.MenuCaption { Layout.fillWidth: true; text: qsTr("Filters"); color: theme.fg.primary }
            PlayerOptions { optionsModel: equalizerOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: compressorOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: spatializerOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: widenerOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: pitchOptions; Layout.fillWidth: true }
        }
    }

    Component {
        id: videoSettings
        ColumnLayout {
            spacing: VLCStyle.margin_normal
            onActiveFocusChanged: {
                if (!activeFocus)
                    return
                for (const child of children) {
                    if (child.visible && child.enabled) {
                        child.forceActiveFocus(Qt.TabFocusReason)
                        return
                    }
                }
            }
            ChoiceControl { id: aspectChoice; title: qsTr("Aspect ratio"); choicesModel: Player.aspectRatio }
            ChoiceControl { title: qsTr("Crop"); choicesModel: Player.crop }
            ChoiceControl { title: qsTr("Zoom"); choicesModel: Player.zoom }
            ChoiceControl { title: qsTr("Deinterlace"); choicesModel: Player.deinterlace }
            ChoiceControl { title: qsTr("Deinterlace mode"); choicesModel: Player.deinterlaceMode }
            Widgets.ButtonExt {
                text: qsTr("Video Effects")
                iconTxt: VLCIcons.effect_filter
                onClicked: DialogsProvider.videoEffectsDialog()
                Navigation.parentItem: parent
            }
            PlayerPresets {
                optionModels: [transformOptions, rotateOptions, adjustmentOptions, sharpenOptions, bandingOptions, grainOptions, cropOptions,
                               extractionOptions, thresholdOptions, negateOptions, posterizeOptions, gradientOptions, sepiaOptions]
                section: InterfacePresetsModel.Video
                Layout.fillWidth: true
            }
            Widgets.MenuCaption { Layout.fillWidth: true; text: qsTr("Filters"); color: theme.fg.primary }
            PlayerOptions { optionsModel: transformOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: rotateOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: adjustmentOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: sharpenOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: bandingOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: grainOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: cropOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: extractionOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: thresholdOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: negateOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: posterizeOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: gradientOptions; Layout.fillWidth: true }
            PlayerOptions { optionsModel: sepiaOptions; Layout.fillWidth: true }
        }
    }

    Component {
        id: playbackSettings
        ColumnLayout {
            spacing: VLCStyle.margin_normal
            onActiveFocusChanged: {
                if (activeFocus)
                    (speedControl.enabled ? speedControl.slider : playbackActions).forceActiveFocus(Qt.TabFocusReason)
            }
            PlaybackSpeed {
                id: speedControl
                inlineMode: true
                enabled: Player.ratechangable
                Layout.fillWidth: true
                Navigation.parentItem: parent
            }
            ColumnLayout {
                id: playbackActions
                Layout.fillWidth: true
                spacing: VLCStyle.margin_xsmall
                Navigation.parentItem: parent
                onActiveFocusChanged: if (activeFocus)
                    (reverseAction.visible ? reverseAction : informationAction).forceActiveFocus(Qt.TabFocusReason)
                Widgets.ButtonExt {
                    id: reverseAction
                    Layout.fillWidth: true
                    text: qsTr("Reverse")
                    visible: Player.rewindable
                    enabled: visible
                    Navigation.parentItem: playbackActions
                    Navigation.upItem: speedControl.slider
                    Navigation.downItem: informationAction
                    onClicked: Player.reverse()
                }
                Widgets.ButtonExt {
                    id: informationAction
                    Layout.fillWidth: true
                    text: qsTr("Information")
                    enabled: Player.isStarted
                    iconTxt: VLCIcons.info
                    Navigation.parentItem: playbackActions
                    Navigation.upItem: reverseAction.visible ? reverseAction : speedControl.slider
                    Navigation.downItem: statisticsAction
                    onClicked: DialogsProvider.mediaInfoDialog()
                }
                Widgets.ButtonExt {
                    id: statisticsAction
                    Layout.fillWidth: true
                    text: qsTr("Show Statistics")
                    enabled: Player.isStarted
                    Navigation.parentItem: playbackActions
                    Navigation.upItem: informationAction
                    onClicked: DialogsProvider.statisticsDialog()
                }
            }
            ChoiceControl {
                title: qsTr("Audio Visualizer")
                choicesModel: Player.audioVisualization
                Navigation.parentItem: parent
            }
            ColumnLayout {
                id: sleepTimerControls
                Layout.fillWidth: true
                spacing: VLCStyle.margin_xsmall
                function enteredMinutes() {
                    try { return Number.fromLocaleString(Qt.locale(), sleepMinutes.text) }
                    catch (error) { return NaN }
                }
                Widgets.MenuCaption {
                    Layout.fillWidth: true
                    // Source: Figma Playback / Sleep Timer; remaining time is
                    // derived from the user duration and GUI monotonic clock.
                    text: qsTr("Sleep Timer")
                    color: theme.fg.primary
                }
                Widgets.ListSubtitleLabel {
                    Layout.fillWidth: true
                    text: PlaybackTimer.active ? PlaybackTimer.remaining.formatHMS() : qsTr("Off")
                    color: theme.fg.secondary
                }
                Widgets.TextFieldExt {
                    id: sleepMinutes
                    Layout.fillWidth: true
                    selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    Accessible.name: qsTr("Sleep Timer") + " (" + qsTr("min") + ")"
                    placeholderText: qsTr("min")
                    onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
                    Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
                    Binding on text {
                        when: !sleepMinutes.activeFocus
                        restoreMode: Binding.RestoreNone
                        value: PlaybackTimer.active ? Number(PlaybackTimer.minutes).toLocaleString(Qt.locale(), 'g') : ""
                    }
                }
                Widgets.NavigableRow {
                    Layout.fillWidth: true
                    spacing: VLCStyle.margin_xsmall
                    Widgets.ButtonExt {
                        text: qsTr("Apply")
                        enabled: Number.isFinite(sleepTimerControls.enteredMinutes()) && sleepTimerControls.enteredMinutes() > 0
                        onClicked: PlaybackTimer.start(sleepTimerControls.enteredMinutes())
                    }
                    Widgets.ButtonExt {
                        text: qsTr("Cancel")
                        enabled: PlaybackTimer.active
                        onClicked: PlaybackTimer.cancel()
                    }
                }
            }
            Widgets.ListLabel {
                Layout.fillWidth: true
                visible: Player.title.length > 0
                text: Player.title
                color: theme.fg.primary
            }
            Widgets.ListSubtitleLabel {
                Layout.fillWidth: true
                visible: Player.artist.length > 0
                text: Player.artist
                color: theme.fg.secondary
            }
            Widgets.ListSubtitleLabel {
                Layout.fillWidth: true
                visible: Player.album.length > 0
                text: Player.album
                color: theme.fg.secondary
            }
        }
    }

    component ChoiceControl: RowLayout {
        id: choiceControl
        required property string title
        required property var choicesModel
        readonly property int count: choice.count
        Layout.fillWidth: true
        visible: choice.count > 0
        spacing: VLCStyle.margin_small
        onActiveFocusChanged: if (activeFocus) choice.forceActiveFocus(Qt.TabFocusReason)

        Widgets.MenuCaption {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: choiceControl.title
            color: theme.fg.primary
        }
        Widgets.ComboBoxExt {
            id: choice
            Layout.preferredWidth: VLCStyle.dp(140, VLCStyle.scale)
            Layout.fillWidth: false
            Layout.minimumWidth: 0
            model: choiceControl.choicesModel
            textRole: "display"
            currentIndex: -1
            Accessible.name: choiceControl.title
            onActivated: (index) => model.toggleIndex(index)
            function syncSelection() {
                if (!model) {
                    currentIndex = -1
                    return
                }
                for (let i = 0; i < count; ++i) {
                    if (model.data(model.index(i, 0), Qt.CheckStateRole)) {
                        currentIndex = i
                        return
                    }
                }
                currentIndex = -1
            }
            Component.onCompleted: syncSelection()
            onCountChanged: syncSelection()
            onModelChanged: syncSelection()
            Connections {
                target: choice.model
                function onDataChanged() { choice.syncSelection() }
                function onModelReset() { choice.syncSelection() }
                function onRowsInserted() { choice.syncSelection() }
                function onRowsRemoved() { choice.syncSelection() }
            }
            Navigation.parentItem: choiceControl
        }
    }

    component TrackList: Widgets.ListViewExt {
        id: trackList
        required property var tracksModel
        required property string listTitle
        model: tracksModel
        focus: true
        clip: !fadingEdge.implicitClipping && (height < contentHeight)
        fadingEdge.backgroundColor: theme.bg.primary
        Accessible.role: Accessible.List
        Accessible.name: listTitle
        Keys.priority: Keys.AfterItem
        Keys.onPressed: (event) => Navigation.defaultKeyAction(event)

        delegate: Widgets.CheckedDelegate {
            readonly property bool isModelChecked: model.checked
            text: model.display
            width: trackList.width
            height: VLCStyle.dp(40, VLCStyle.scale)
            focus: true
            font.pixelSize: VLCStyle.fontSize_normal
            opacity: hovered || activeFocus || checked ? 1 : .8
            font.weight: checked ? Font.DemiBold : Font.Normal
            onIsModelCheckedChanged: {
                if (model.checked !== checked)
                    checked = model.checked
            }
            onCheckedChanged: {
                if (model.checked !== checked)
                    model.checked = checked
            }
            Component.onCompleted: checked = model.checked
            onClicked: {
                trackList.currentIndex = index
                trackList.setCurrentItemFocus(Qt.MouseFocusReason)
            }
            Navigation.parentItem: trackList
        }
    }

    QmlSubtitleMenu {
        id: menuSubtitle
        player: Player
        ctx: MainCtx
        onTriggered: {
            if (action === QmlSubtitleMenu.Open)
                DialogsProvider.loadSubtitlesFile()
            else if (action === QmlSubtitleMenu.Synchronize) {
                settingsFlick.contentY = settingsLoader.y
                settingsLoader.forceActiveFocus()
            } else if (action === QmlSubtitleMenu.Download)
                Player.openVLsub()
        }
    }
    QmlAudioMenu {
        id: menuAudio
        ctx: MainCtx
        onTriggered: {
            if (action === QmlAudioMenu.Open)
                DialogsProvider.loadAudioFile()
            else if (action === QmlAudioMenu.Synchronize) {
                settingsFlick.contentY = settingsLoader.y
                settingsLoader.forceActiveFocus()
            }
        }
    }
}
