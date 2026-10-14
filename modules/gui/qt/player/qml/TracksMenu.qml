
/*****************************************************************************
 * Copyright (C) 2020 VLC authors and VideoLAN
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


import VLC.Style
import VLC.Widgets as Widgets
import VLC.Util

T.Popup {
    id: root

    // Settings
    property var preferredWidth: stackView.currentItem?.preferredWidth ?? VLCStyle.dp(400, VLCStyle.scale)
    property int initialTab: 0
    readonly property bool sideAligned: parent.width >= preferredWidth * 2
    readonly property real panelTop: parent.playerSettingsTop ?? VLCStyle.margin_small
    readonly property real panelBottom: parent.playerControlsY ?? parent.positionSliderY ?? parent.height

    width: sideAligned ? Math.min(preferredWidth, parent.width - VLCStyle.margin_small * 2)
                       : Math.max(0, parent.width - VLCStyle.margin_small * 2)

    height: Math.max(0, sideAligned ? panelBottom - panelTop - VLCStyle.margin_small
                                  : Math.min(VLCStyle.dp(360, VLCStyle.scale),
                                             (panelBottom - panelTop - VLCStyle.margin_small) * 0.65))
    padding: 0
    modal: false
    dim: false

    onAboutToShow: {
        // Build the initial page without an opacity animation while its
        // Popup is still hidden. The render-thread animator can otherwise
        // leave the actual opened page invisible on a software scene graph.
        stackView.clear(T.StackView.Immediate)
        stackView.push(tracksPageComponent, {}, T.StackView.Immediate)
        if (stackView.currentItem)
            stackView.currentItem.opacity = 1
    }

    // Animations

    Behavior on width {
        SmoothedAnimation {
            duration: VLCStyle.duration_veryShort
            easing.type: Easing.InOutSine
        }
    }

    // Children

    readonly property ColorContext colorContext: ColorContext {
        id: popupTheme
        colorSet: ColorContext.Window
    }

    background: Rectangle {
        color: popupTheme.bg.primary
        radius: VLCStyle.dp(10, VLCStyle.scale)
        border.width: VLCStyle.dp(1, VLCStyle.scale)
        border.color: popupTheme.border
    }

    contentItem: T.StackView {
        id: stackView

        focus: true
        clip: true

        //erf, popup are weird, content is not parented to the root
        //so, duplicate the context here for the childrens
        readonly property ColorContext colorContext: ColorContext {
            id: theme
            colorSet: popupTheme.colorSet
            palette: popupTheme.palette
        }

        initialItem: tracksPageComponent

        pushEnter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: VLCStyle.duration_long
            }
        }
        pushExit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: VLCStyle.duration_long
            }
        }
        popEnter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: VLCStyle.duration_long
            }
        }
        popExit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: VLCStyle.duration_long
            }
        }
    }

    Component {
        id: tracksPageComponent
        TracksListPage { trackMenuController: menuController }
    }

    QtObject {
      id: menuController

      readonly property int initialTab: root.initialTab

      signal requestAudioPage()
      signal requestSubtitlePage()
      signal requestPlaybackSpeedPage()
      signal requestBack()
      signal requestClose()

      onRequestClose: root.close()

      onRequestBack: {
          stackView.pop()
      }

      onRequestAudioPage: {
          stackView.push("qrc:///qt/qml/VLC/Player/TracksPageAudio.qml", {"trackMenuController": menuController})
      }

      onRequestSubtitlePage: {
          stackView.push("qrc:///qt/qml/VLC/Player/TracksPageSubtitle.qml", {"trackMenuController": menuController})
      }

      onRequestPlaybackSpeedPage: {
          stackView.push("qrc:///qt/qml/VLC/Player/TracksPageSpeed.qml", {"trackMenuController": menuController})
      }
    }
}
