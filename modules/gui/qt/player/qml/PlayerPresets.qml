/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
import QtQuick
import QtQuick.Layouts
import VLC.MainInterface
import VLC.Player
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets

ColumnLayout {
    id: root
    required property var optionModels
    required property int section
    property bool operationSucceeded: true
    spacing: VLCStyle.margin_xsmall
    Navigation.parentItem: parent
    onActiveFocusChanged: if (activeFocus)
        (presetChoice.enabled ? presetChoice : presetName).forceActiveFocus(Qt.TabFocusReason)

    readonly property ColorContext colorContext: ColorContext { id: theme; colorSet: ColorContext.View }
    InterfacePresetsModel {
        id: presets
        ctx: MainCtx
        section: root.section
        mediaUrl: Player.url
    }
    function availableModels() {
        return optionModels.filter(model => model.filterTitle.length === 0 || model.filterAvailable)
    }
    function captureState() {
        const state = {groups: availableModels().map(model => model.snapshot()), sync: {}}
        if (section === InterfacePresetsModel.Subtitles)
            state.sync = {primary: Player.subtitleDelayMS, secondary: Player.secondarySubtitleDelayMS, fps: Player.subtitleFPS}
        else if (section === InterfacePresetsModel.Audio)
            state.sync = {audio: Player.audioDelayMS}
        return state
    }
    function validDelay(value) {
        // Source: the actual Player delay properties are signed 32-bit milliseconds.
        return Number.isFinite(value) && Number.isInteger(value) && value >= -2147483648 && value <= 2147483647
    }
    function applyState(state) {
        if (!state || !state.groups || typeof state.groups.length !== "number") return false
        const sync = state.sync ?? {}
        if (section === InterfacePresetsModel.Subtitles && (!validDelay(sync.primary) || !validDelay(sync.secondary) ||
                !Number.isFinite(sync.fps) || sync.fps < 0 || sync.fps > 100)) return false
        if (section === InterfacePresetsModel.Audio && !validDelay(sync.audio)) return false
        const models = availableModels()
        const previous = models.map(model => model.snapshot())
        const rollback = () => {
            for (let i = 0; i < models.length; ++i) models[i].restoreSnapshot(previous[i])
        }
        // Earlier GUI snapshots combined transform/rotation/image adjustment
        // in group2. Restore only matching source keys into their individual
        // sections; newer explicit sections below take precedence.
        if (section === InterfacePresetsModel.Video) {
            for (const legacy of Array.from(state.groups).filter(group => group.group === InterfaceOptionsModel.VideoAdjustment)) {
                for (const model of models) {
                    const current = model.snapshot()
                    const options = {}
                    for (const key of Object.keys(legacy.options ?? {}))
                        if (Object.prototype.hasOwnProperty.call(current.options, key)) options[key] = legacy.options[key]
                    if (Object.keys(options).length && !model.restoreSnapshot({group: model.group, options: options, filterEnabled: model.filterEnabled})) {
                        rollback()
                        return false
                    }
                }
            }
        }
        for (const snapshot of Array.from(state.groups)) {
            const model = models.find(candidate => candidate.group === snapshot.group)
            if (model && !model.restoreSnapshot(snapshot)) {
                rollback()
                return false
            }
        }
        if (models.length === 0 || !models[0].applyBatch(models)) return false
        if (section === InterfacePresetsModel.Subtitles) {
            Player.subtitleDelayMS = sync.primary
            Player.secondarySubtitleDelayMS = sync.secondary
            Player.subtitleFPS = sync.fps
        } else if (section === InterfacePresetsModel.Audio) Player.audioDelayMS = sync.audio
        return true
    }

    // Source: the owner's transcript requests saved Subtitle/Audio/Video presets.
    // Names are user input; the optional scope caption is actual ML show metadata
    // or the local media's parent folder. Values come only from existing models.
    Widgets.CaptionLabel { Layout.fillWidth: true; text: qsTr("Presets"); color: theme.fg.secondary }
    Widgets.ComboBoxExt {
        id: presetChoice
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: presets
        textRole: "name"
        currentIndex: -1
        enabled: presets.count > 0
        Accessible.name: qsTr("Presets")
        Navigation.parentItem: root
        Navigation.downItem: presetName
        onActivated: index => presetName.text = presets.get(index).name
    }
    Widgets.TextFieldExt {
        id: presetName
        Layout.fillWidth: true
        selectByMouse: true
        placeholderText: qsTr("Name")
        Accessible.name: qsTr("Name")
        Navigation.parentItem: root
        Navigation.upItem: presetChoice.enabled ? presetChoice : root.Navigation.upItem
        Navigation.downItem: scopedChoice.visible ? scopedChoice : savePreset
        onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
        Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
    }
    Widgets.CheckBoxExt {
        id: scopedChoice
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: presets.scopeAvailable && presets.scopeTitle.length > 0
        checked: presets.scopeAvailable
        text: qsTr("Save for %1").arg(presets.scopeTitle)
        Accessible.name: text
        Navigation.parentItem: root
        Navigation.upItem: presetName
        Navigation.downItem: savePreset
    }
    GridLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        columns: width >= savePreset.implicitWidth + applyPreset.implicitWidth + deletePreset.implicitWidth + columnSpacing * 2 ? 3 : 1
        columnSpacing: VLCStyle.margin_xsmall
        rowSpacing: VLCStyle.margin_xsmall
        Widgets.ButtonExt {
            id: savePreset
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: qsTr("Save")
            enabled: presetName.text.trim().length > 0
            Navigation.parentItem: root
            Navigation.upItem: scopedChoice.visible ? scopedChoice : presetName
            Navigation.downItem: applyPreset
            onClicked: {
                root.operationSucceeded = presets.save(presetName.text, root.captureState(), scopedChoice.checked && presets.scopeAvailable)
                if (root.operationSucceeded)
                    for (let i = 0; i < presets.count; ++i)
                        if (presets.get(i).name === presetName.text.trim() &&
                            presets.get(i).scopeKey === (scopedChoice.checked && presets.scopeAvailable ? presets.scopeKey : "")) {
                            presetChoice.currentIndex = i; break
                        }
            }
        }
        Widgets.ButtonExt {
            id: applyPreset
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: qsTr("Apply")
            enabled: presetChoice.currentIndex >= 0
            Navigation.parentItem: root
            Navigation.upItem: savePreset
            Navigation.downItem: deletePreset
            onClicked: root.operationSucceeded = root.applyState(presets.get(presetChoice.currentIndex).snapshot)
        }
        Widgets.ButtonExt {
            id: deletePreset
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: qsTr("Delete")
            enabled: presetChoice.currentIndex >= 0
            Navigation.parentItem: root
            Navigation.upItem: applyPreset
            Navigation.downItem: root.Navigation.downItem
            onClicked: {
                root.operationSucceeded = presets.remove(presetChoice.currentIndex)
                if (root.operationSucceeded) { presetChoice.currentIndex = -1; presetName.text = "" }
            }
        }
    }
    Widgets.MenuCaption {
        Layout.fillWidth: true
        visible: !root.operationSucceeded
        // Source: the actual save/restore method returned false; generic Error
        // is VLC's existing error label, without invented status or detail.
        text: qsTr("Error")
        color: theme.fg.primary
    }
}
