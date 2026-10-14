/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import VLC.MainInterface
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets
import VLC.Dialogs

ColumnLayout {
    id: root
    required property InterfaceOptionsModel optionsModel
    property string captionText: qsTr("Preferences")
    readonly property bool collapsible: optionsModel.filterTitle.length > 0
    property bool expanded: !collapsible
    visible: collapsible ? optionsModel.filterAvailable : optionsModel.count > 0
    spacing: VLCStyle.margin_small

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }
    function setCurrentItemFocus(reason) {
        if (collapsible && !expanded) {
            filterToggle.forceActiveFocus(reason)
            return
        }
        const editor = optionRepeater.itemAt(0)
        if (editor)
            editor.focusEditor(reason)
        else
            preferenceActions.forceActiveFocus(reason)
    }
    Navigation.parentItem: parent

    // Source: the native preferences/effects config metadata supplies labels,
    // help, ranges, choices and values. Apply/Cancel retain deferred preferences semantics.
    Widgets.CaptionLabel {
        visible: !root.collapsible
        Layout.fillWidth: true
        text: root.captionText
        color: theme.fg.secondary
    }

    GridLayout {
        id: filterHeader
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: root.collapsible
        columns: width >= filterToggle.implicitWidth + expandSettings.implicitWidth + columnSpacing ? 2 : 1
        columnSpacing: VLCStyle.margin_xsmall
        rowSpacing: VLCStyle.margin_xsmall
        Navigation.parentItem: root
        Navigation.upItem: root.Navigation.upItem
        Navigation.downItem: optionRepeater.itemAt(0) ?? preferenceActions
        Widgets.CheckBoxExt {
            id: filterToggle
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            checked: root.optionsModel.filterEnabled
            text: root.optionsModel.filterTitle
            Accessible.name: text
            Navigation.parentItem: filterHeader
            Navigation.downItem: expandSettings.visible ? expandSettings : preferenceActions
            Navigation.rightItem: expandSettings.visible ? expandSettings : null
            onToggled: root.optionsModel.filterEnabled = checked
        }
        Widgets.ButtonExt {
            id: expandSettings
            Layout.fillWidth: filterHeader.columns === 1
            Layout.minimumWidth: 0
            // Source: Figma's expandable Audio/Video filter settings sections.
            text: root.expanded ? qsTr("Collapse Settings") : qsTr("Expand Settings")
            visible: root.optionsModel.count > 0
            Navigation.parentItem: filterHeader
            Navigation.leftItem: filterToggle
            Navigation.upItem: filterToggle
            Navigation.downItem: optionRepeater.itemAt(0) ?? preferenceActions
            onClicked: root.expanded = !root.expanded
        }
    }

    Repeater {
        id: optionRepeater
        model: root.expanded ? root.optionsModel : 0
        OptionEditor {
            required property int index
            required property var model
            optionIndex: index
            optionData: model
            Layout.fillWidth: true
        }
    }

    Widgets.NavigableRow {
        id: preferenceActions
        Layout.fillWidth: true
        visible: !root.collapsible || root.expanded || root.optionsModel.dirty
        spacing: VLCStyle.margin_xsmall
        Navigation.parentItem: root
        Navigation.upItem: optionRepeater.itemAt(optionRepeater.count - 1)
        Navigation.downItem: root.Navigation.downItem
        Widgets.ButtonExt {
            text: qsTr("Apply")
            enabled: root.optionsModel.dirty
            onClicked: root.optionsModel.apply()
        }
        Widgets.ButtonExt {
            text: qsTr("Cancel")
            enabled: root.optionsModel.dirty
            onClicked: root.optionsModel.cancel()
        }
    }

    component OptionEditor: ColumnLayout {
        id: optionEditor
        required property int optionIndex
        required property var optionData
        spacing: VLCStyle.margin_xxsmall
        Navigation.parentItem: root
        Navigation.upItem: optionIndex > 0 ? optionRepeater.itemAt(optionIndex - 1) : root.Navigation.upItem
        Navigation.downItem: optionIndex < optionRepeater.count - 1 ? optionRepeater.itemAt(optionIndex + 1) : preferenceActions
        function focusEditor(reason) { if (editorLoader.item) editorLoader.item.forceActiveFocus(reason) }
        onActiveFocusChanged: if (activeFocus) focusEditor(Qt.TabFocusReason)

        Widgets.MenuCaption {
            Layout.fillWidth: true
            text: optionEditor.optionData.title
            color: theme.fg.primary
            wrapMode: Text.WordWrap
        }
        Loader {
            id: editorLoader
            Layout.fillWidth: true
            Layout.preferredHeight: item?.implicitHeight ?? 0
            sourceComponent: optionEditor.optionData.kind === "color" ? colorEditor
                           : optionEditor.optionData.kind === "bands" ? bandsEditor
                           : optionEditor.optionData.choices.length > 0 ? choiceEditor
                           : optionEditor.optionData.kind === "boolean" ? booleanEditor
                           : optionEditor.optionData.kind === "integer" || optionEditor.optionData.kind === "float" ? numberEditor
                           : textEditor
        }

        Component {
            id: choiceEditor
            Widgets.ComboBoxExt {
                model: optionEditor.optionData.choices
                textRole: "text"
                currentIndex: {
                    for (let i = 0; i < count; ++i)
                        if (model[i].value === optionEditor.optionData.value)
                            return i
                    return -1
                }
                displayText: currentIndex >= 0 ? currentText : String(optionEditor.optionData.value)
                Accessible.name: optionEditor.optionData.title
                Navigation.parentItem: optionEditor
                T.ToolTip.text: optionEditor.optionData.help
                T.ToolTip.visible: hovered && T.ToolTip.text.length > 0
                onActivated: (index) => root.optionsModel.setValue(optionEditor.optionIndex, model[index].value)
            }
        }
        Component {
            id: booleanEditor
            Widgets.CheckBoxExt {
                Accessible.name: optionEditor.optionData.title
                Navigation.parentItem: optionEditor
                checked: Boolean(optionEditor.optionData.value)
                onToggled: root.optionsModel.setValue(optionEditor.optionIndex, checked)
            }
        }
        Component {
            id: textEditor
            Widgets.TextFieldExt {
                id: textValue
                Accessible.name: optionEditor.optionData.title
                Navigation.parentItem: optionEditor
                selectByMouse: true
                onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
                Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
                T.ToolTip.text: optionEditor.optionData.help
                T.ToolTip.visible: hovered && T.ToolTip.text.length > 0
                onEditingFinished: root.optionsModel.setValue(optionEditor.optionIndex, text)
                Binding on text { when: !textValue.activeFocus; restoreMode: Binding.RestoreNone; value: String(optionEditor.optionData.value) }
            }
        }
        Component {
            id: numberEditor
            ColumnLayout {
                spacing: VLCStyle.margin_xxsmall
                onActiveFocusChanged: if (activeFocus) numberValue.forceActiveFocus(Qt.TabFocusReason)
                Widgets.TextFieldExt {
                    id: numberValue
                    Layout.fillWidth: true
                    selectByMouse: true
                    onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
                    Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    Accessible.name: optionEditor.optionData.title
                    Navigation.parentItem: optionEditor
                    Navigation.downItem: numberSlider.visible ? numberSlider : optionEditor.Navigation.downItem
                    T.ToolTip.text: optionEditor.optionData.help
                    T.ToolTip.visible: hovered && T.ToolTip.text.length > 0
                    onEditingFinished: root.optionsModel.setValue(optionEditor.optionIndex, text)
                    Binding on text { when: !numberValue.activeFocus; restoreMode: Binding.RestoreNone; value: String(optionEditor.optionData.value) }
                }
                Widgets.SliderExt {
                    id: numberSlider
                    Layout.fillWidth: true
                    // Pixel crop fields keep their real metadata limits in the
                    // editor; an INT_MAX-range slider does not help enter pixels.
                    visible: optionEditor.optionData.hasRange && root.optionsModel.group !== InterfaceOptionsModel.CropFilter
                    from: optionEditor.optionData.minimum
                    to: optionEditor.optionData.maximum
                    stepSize: optionEditor.optionData.kind === "integer" ? 1 : 0
                    Accessible.name: optionEditor.optionData.title
                    Navigation.parentItem: optionEditor
                    Navigation.upItem: numberValue
                    toolTipTextProvider: (value) => String(value)
                    onMoved: root.optionsModel.setValue(optionEditor.optionIndex, value)
                    Binding on value { when: !numberSlider.pressed; restoreMode: Binding.RestoreNone; value: Number(optionEditor.optionData.value) }
                }
            }
        }
        Component {
            id: bandsEditor
            Flickable {
                id: bandFlick
                implicitHeight: VLCStyle.dp(190, VLCStyle.scale)
                contentWidth: bandRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                T.ScrollBar.horizontal: Widgets.ScrollBarExt {}
                Row {
                    id: bandRow
                    spacing: VLCStyle.dp(4, VLCStyle.scale)
                    Repeater {
                        id: bandRepeater
                        model: optionEditor.optionData.bands.length
                        Column {
                            id: bandColumn
                            required property int index
                            readonly property var modelData: optionEditor.optionData.bands[index]
                            function focusEditor(reason) { bandSlider.forceActiveFocus(reason) }
                            width: VLCStyle.dp(38, VLCStyle.scale)
                            spacing: VLCStyle.dp(6, VLCStyle.scale)
                            Widgets.CaptionLabel {
                                width: parent.width
                                text: bandColumn.modelData.text
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                color: theme.fg.secondary
                            }
                            T.Slider {
                                id: bandSlider
                                width: bandColumn.width
                                height: VLCStyle.dp(135, VLCStyle.scale)
                                orientation: Qt.Vertical
                                from: bandColumn.modelData.minimum
                                to: bandColumn.modelData.maximum
                                stepSize: bandColumn.modelData.step
                                snapMode: T.Slider.SnapAlways
                                hoverEnabled: true
                                Accessible.name: bandColumn.modelData.text
                                Navigation.parentItem: optionEditor
                                Navigation.upItem: optionEditor.Navigation.upItem
                                Navigation.downItem: optionEditor.Navigation.downItem
                                onMoved: root.optionsModel.setBand(optionEditor.optionIndex, bandColumn.index, value)
                                Binding on value { when: !bandSlider.pressed; restoreMode: Binding.RestoreNone; value: bandColumn.modelData.value }
                                T.ToolTip.text: bandColumn.modelData.text + ": " + Number(value).toFixed(1) + " " + qsTr("dB")
                                T.ToolTip.visible: hovered || visualFocus || pressed
                                background: Rectangle {
                                    x: (bandSlider.width - width) / 2
                                    width: VLCStyle.dp(4, VLCStyle.scale)
                                    height: bandSlider.availableHeight
                                    radius: VLCStyle.dp(2, VLCStyle.scale)
                                    color: theme.bg.secondary
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: bandSlider.position * parent.height
                                        radius: parent.radius
                                        color: theme.accent
                                    }
                                }
                                handle: Rectangle {
                                    x: (bandSlider.width - width) / 2
                                    y: bandSlider.visualPosition * (bandSlider.availableHeight - height)
                                    width: VLCStyle.dp(24, VLCStyle.scale)
                                    height: VLCStyle.dp(8, VLCStyle.scale)
                                    radius: VLCStyle.dp(2, VLCStyle.scale)
                                    color: bandSlider.visualFocus ? theme.visualFocus : theme.fg.primary
                                }
                            }
                            Widgets.CaptionLabel {
                                width: parent.width
                                text: Number(bandSlider.value).toFixed(1)
                                horizontalAlignment: Text.AlignHCenter
                                color: theme.fg.primary
                            }
                        }
                    }
                }
                onActiveFocusChanged: if (activeFocus && bandRepeater.count > 0) bandRepeater.itemAt(0).focusEditor(Qt.TabFocusReason)
            }
        }
        Component {
            id: colorEditor
            RowLayout {
                spacing: VLCStyle.margin_xsmall
                onActiveFocusChanged: if (activeFocus) colorValue.forceActiveFocus(Qt.TabFocusReason)
                Widgets.ButtonExt {
                    Accessible.name: optionEditor.optionData.title
                    Navigation.parentItem: optionEditor
                    implicitWidth: VLCStyle.dp(40, VLCStyle.scale)
                    implicitHeight: VLCStyle.dp(32, VLCStyle.scale)
                    background: Rectangle {
                        radius: VLCStyle.button_radius
                        color: optionEditor.optionData.colorValue
                        border.color: theme.border
                        border.width: VLCStyle.dp(1, VLCStyle.scale)
                    }
                    onClicked: DialogsProvider.chooseColor(optionEditor.optionData.colorValue,
                        optionEditor.optionData.title, optionEditor,
                        selected => root.optionsModel.setValue(optionEditor.optionIndex, selected))
                }
                Widgets.TextFieldExt {
                    id: colorValue
                    Layout.fillWidth: true
                    Accessible.name: optionEditor.optionData.title
                    Navigation.parentItem: optionEditor
                    selectByMouse: true
                    onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus
                    Component.onDestruction: if (activeFocus) MainCtx.useGlobalShortcuts = true
                    onEditingFinished: root.optionsModel.setValue(optionEditor.optionIndex, text)
                    Binding on text { when: !colorValue.activeFocus; restoreMode: Binding.RestoreNone; value: String(optionEditor.optionData.colorValue) }
                }
            }
        }
    }
    onActiveFocusChanged: if (activeFocus) setCurrentItemFocus(Qt.TabFocusReason)
}
