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
import VLC.MediaLibrary
import VLC.Style
import VLC.Util
import VLC.Widgets as Widgets

// "Recent" is from Figma's library rail; rows come from VLC's actual history.
Widgets.PageExt {
    id: root
    title: qsTr("Recent")
    Accessible.name: title
    AccessibleCompat.id: "recentDisplay"

    MediaView {
        anchors.fill: parent
        focus: true
        // The owner's full-library frames use landscape media covers; history
        // still supplies each item's real video or audio artwork and metadata.
        gridCoverWidth: VLCStyle.gridCover_video_width
        gridCoverHeight: VLCStyle.gridCover_video_height
        model: MLRecentMediaModel {
            ml: MediaLib
            searchPattern: root.search.pattern
            sortCriteria: root.sort.criteria
            sortOrder: root.sort.order
        }
        displayMarginBeginning: root.displayMarginBeginning
        displayMarginEnd: root.displayMarginEnd
        enableBeginningFade: root.enableBeginningFade
        enableEndFade: root.enableEndFade
    }
}
