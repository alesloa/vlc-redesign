/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
import QtQuick
import VLC.MainInterface
import VLC.Style
import VLC.Util

TextFieldExt {
    id: root

    property alias searchPattern: root.text
    property bool _keyPressed: false

    implicitWidth: VLCStyle.widthSearchInput
    implicitHeight: VLCStyle.bannerButton_height + VLCStyle.margin_xsmall
    leftPadding: VLCStyle.icon_small + VLCStyle.margin_small * 2
    rightPadding: clearButton.visible ? clearButton.width + VLCStyle.margin_xsmall : VLCStyle.margin_small
    radius: VLCStyle.button_radius
    placeholderText: qsTr("Filter")
    selectByMouse: true
    focus: true
    activeFocusOnTab: true
    Accessible.name: placeholderText
    Accessible.searchEdit: true

    function expandAndFocus() {
        forceActiveFocus(Qt.ShortcutFocusReason)
        selectAll()
    }

    onActiveFocusChanged: MainCtx.useGlobalShortcuts = !activeFocus

    Keys.priority: Keys.AfterItem
    Keys.onPressed: (event) => {
        _keyPressed = true
        // Source: SearchBox's text-entry guard; Backspace must not navigate away.
        if (event.matches(StandardKey.Backspace))
            event.accepted = true
        Navigation.defaultKeyAction(event)
    }
    Keys.onReleased: (event) => {
        if (!_keyPressed)
            return
        _keyPressed = false
        if (event.matches(StandardKey.Backspace))
            event.accepted = true
        Navigation.defaultKeyReleaseAction(event)
    }
    Keys.onEscapePressed: (event) => {
        if (text.length > 0)
            clear()
        else
            Navigation.defaultKeyAction(event)
    }

    IconLabel {
        anchors.left: parent.left
        anchors.leftMargin: VLCStyle.margin_small
        anchors.verticalCenter: parent.verticalCenter
        text: VLCIcons.search
        font.pixelSize: VLCStyle.icon_small
        color: root.colorContext.fg.secondary
        Accessible.ignored: true
    }

    IconToolButton {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: VLCStyle.margin_xxxsmall
        anchors.verticalCenter: parent.verticalCenter
        width: VLCStyle.icon_normal
        height: root.height
        text: VLCIcons.close
        font.pixelSize: VLCStyle.icon_small
        description: qsTr("Clear")
        visible: root.text.length > 0
        onClicked: {
            root.clear()
            root.forceActiveFocus(Qt.MouseFocusReason)
        }
        Navigation.parentItem: root
        Navigation.leftItem: root

        onVisibleChanged: {
            if (activeFocus && !visible) {
                root.forceActiveFocus(focusReason)
            }
        }
    }
}
