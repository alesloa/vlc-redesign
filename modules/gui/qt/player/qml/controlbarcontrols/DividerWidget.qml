/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
import QtQuick
import VLC.MainInterface
import VLC.Style

Item {
    property bool paintOnly: false
    enabled: false
    implicitWidth: paintOnly ? MainCtx.dp(24, VLCStyle.scale) : MainCtx.dp(8, VLCStyle.scale)
    implicitHeight: MainCtx.dp(24, VLCStyle.scale)
    Accessible.ignored: true
    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.ToolButton
        enabled: true
    }
    // This divider is a simple line in the Figma component, not an icon.
    Rectangle {
        anchors.centerIn: parent
        width: MainCtx.dp(1, VLCStyle.scale)
        height: MainCtx.dp(24, VLCStyle.scale)
        color: theme.separator
    }
}
