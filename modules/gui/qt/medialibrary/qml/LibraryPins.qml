/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
pragma Singleton
import QtQuick
import QtQml.Models
import VLC.MainInterface
import VLC.MediaLibrary
import VLC.Style

// Pins are user choices. Names and covers are refreshed from the original ML
// entities, rather than storing display text or a second copy of media metadata.
QtObject {
    id: root

    readonly property MLAlbumModel albums: MLAlbumModel {
        ml: MediaLib
    }
    readonly property MLArtistModel artists: MLArtistModel {
        ml: MediaLib
    }
    readonly property MLVideoFoldersModel folders: MLVideoFoldersModel {
        ml: MediaLib
    }
    readonly property MLGenreModel genres: MLGenreModel {
        ml: MediaLib
    }
    readonly property MLVideoGroupsModel groups: MLVideoGroupsModel {
        ml: MediaLib
    }
    readonly property MLMediaModel media: MLMediaModel {
        ml: MediaLib
    }
    readonly property ListModel model: ListModel {
        dynamicRoles: true
    }
    readonly property ListModel frequentFolders: ListModel { dynamicRoles: true }
    readonly property ListModel frequentPlaylists: ListModel { dynamicRoles: true }
    readonly property ListModel frequentArtists: ListModel { dynamicRoles: true }
    readonly property MLRecentAudioModel listeningHistory: MLRecentAudioModel { ml: MediaLib; limit: 1 }
    readonly property int listenedCount: listeningHistory.count
    readonly property Timer artistsRefresh: Timer {
        interval: VLCStyle.duration_short
        onTriggered: root.reloadArtists()
    }
    readonly property Connections listeningEvents: Connections {
        target: root.listeningHistory
        function onModelReset() { root.artistsRefresh.restart() }
        function onDataChanged() { root.artistsRefresh.restart() }
        function onCountChanged() { root.artistsRefresh.restart() }
    }
    readonly property MLPlaylistListModel playlists: MLPlaylistListModel {
        ml: MediaLib
        coverDefault: VLCStyle.noArtVideoCover
    }
    property int revision: 0
    property int visitsRevision: 0
    property int artistsRevision: 0
    property var serializedIds: []
    readonly property string settingsKey: "MediaLibrary/Pins"
    readonly property string visitsKey: "MediaLibrary/CollectionVisits"

    function readVisits() {
        try {
            const value = MainCtx.settingValue(visitsKey, "{}")
            const visits = typeof value === "string" ? JSON.parse(value) : {}
            return visits && typeof visits === "object" && !Array.isArray(visits) ? visits : {}
        } catch (error) { return {} }
    }
    function visit(id) {
        if (!supported(id)) return
        const serialized = id.toString()
        const type = kind(serialized)
        if (type !== "folder" && type !== "playlist") return
        const visits = readVisits()
        const previous = visits[serialized] ?? {}
        const count = Number.isSafeInteger(previous.count) && previous.count > 0 ? previous.count : 0
        // These hidden values count actual GUI navigation actions and use the
        // actual clock; all displayed names still resolve from ML metadata.
        visits[serialized] = {count: Math.min(Number.MAX_SAFE_INTEGER, count + 1), lastVisit: Date.now()}
        MainCtx.setSettingValue(visitsKey, JSON.stringify(visits))
        reloadVisits()
    }
    function reloadVisits() {
        const requestedRevision = ++visitsRevision
        const visits = readVisits()
        const ids = Object.keys(visits).filter(serialized =>
            Number.isSafeInteger(visits[serialized]?.count) && visits[serialized].count > 0 &&
            (kind(serialized) === "folder" || kind(serialized) === "playlist"))
        ids.sort((first, second) => visits[second].count - visits[first].count ||
                 Number(visits[second].lastVisit || 0) - Number(visits[first].lastVisit || 0))
        frequentFolders.clear()
        frequentPlaylists.clear()
        Promise.all(ids.map(serialized => {
            const id = MediaLib.deserializeMlItemIdFromString(serialized)
            if (!supported(id)) return Promise.resolve(null)
            return source(serialized).getDataById(id).then(data => {
                const title = data?.title || data?.name || data?.fileName || ""
                return title.length ? {id: id, mediaId: id, serialized: serialized, title: title,
                    cover: String(data.thumbnail || data.cover || ""), kind: kind(serialized)} : null
            }, () => null)
        })).then(entries => {
            if (requestedRevision !== root.visitsRevision) return
            for (const entry of entries) {
                if (!entry) continue
                const model = entry.kind === "folder" ? root.frequentFolders : root.frequentPlaylists
                model.append(entry)
            }
        })
    }
    function reloadArtists() {
        const requestedRevision = ++artistsRevision
        MediaLib.frequentArtists(3, entries => {
            if (requestedRevision !== root.artistsRevision) return
            root.frequentArtists.clear()
            for (const entry of entries) root.frequentArtists.append(entry)
        })
    }

    function contains(id) {
        return !!id && serializedIds.indexOf(id.toString()) >= 0;
    }
    function kind(serialized) {
        if (serialized.startsWith("VLC_ML_PARENT_GROUP"))
            return "group";
        if (serialized.startsWith("VLC_ML_PARENT_FOLDER"))
            return "folder";
        if (serialized.startsWith("VLC_ML_PARENT_PLAYLIST"))
            return "playlist";
        if (serialized.startsWith("VLC_ML_PARENT_ALBUM"))
            return "album";
        if (serialized.startsWith("VLC_ML_PARENT_ARTIST"))
            return "artist";
        if (serialized.startsWith("VLC_ML_PARENT_GENRE"))
            return "genre";
        return "media";
    }
    function supported(id) {
        return !!id && id.isValid() && (!id.hasParent() || kind(id.toString()) !== "media");
    }
    function reload() {
        const requestedRevision = ++revision;
        const savedIds = MainCtx.settingValue(settingsKey, []);
        // Store the existing IDs as a JSON string: QML arrays passed through a
        // QVariant are not persisted by every native QSettings backend. Accept
        // older QVariant lists as well, preserving any existing user choices.
        let values = [];
        try {
            values = typeof savedIds === "string" ? JSON.parse(savedIds) : savedIds ? Array.from(savedIds) : [];
        } catch (error) { }
        serializedIds = Array.isArray(values) ? values.filter(value => typeof value === "string") : [];
        model.clear();
        // Resolve concurrently but retain the order selected by the user.
        const requested = serializedIds.map(function (serialized) {
            const id = MediaLib.deserializeMlItemIdFromString(serialized);
            if (!supported(id))
                return Promise.resolve(null);
            return source(serialized).getDataById(id).then(function (data) {
                if (!data)
                    return null;
                const title = data.title || data.name || data.fileName || "";
                return title.length > 0 ? {
                    serialized: serialized,
                    mediaId: id,
                    title: title,
                    cover: String(data.small_cover || data.thumbnail || data.cover || ""),
                    kind: kind(serialized)
                } : null;
            }, function () {
                return null;
            });
        });
        Promise.all(requested).then(function (entries) {
            if (requestedRevision !== root.revision)
                return;
            for (const entry of entries)
                if (entry)
                    root.model.append(entry);
        });
    }
    function route(entry) {
        switch (entry.kind) {
        case "group":
        case "folder":
            return {
                path: ["video", "all", "group"],
                properties: {
                    parentId: entry.mediaId,
                    title: entry.title
                }
            };
        case "playlist":
            return {
                path: ["video", "playlists", "list"],
                properties: {
                    parentId: entry.mediaId,
                    title: entry.title
                }
            };
        case "artist":
            return {
                path: ["music", "artists", "albums"],
                properties: {
                    artistId: entry.mediaId
                }
            };
        case "genre":
            return {
                path: ["music", "genres", "albums"],
                properties: {
                    parentId: entry.mediaId,
                    genreName: entry.title
                }
            };
        // Existing albums page expands a selected album. Root can resolve its
        // actual index through albums.getIndexFromId without changing playback.
        case "album":
            return {
                path: ["music", "albums"],
                properties: {
                    albumId: entry.mediaId
                }
            };
        default:
            return null;
        }
    }
    function source(serialized) {
        switch (kind(serialized)) {
        case "group":
            return groups;
        case "folder":
            return folders;
        case "playlist":
            return playlists;
        case "album":
            return albums;
        case "artist":
            return artists;
        case "genre":
            return genres;
        default:
            return media;
        }
    }
    function toggle(id) {
        if (!supported(id))
            return;
        const serialized = id.toString();
        const values = serializedIds.slice();
        const index = values.indexOf(serialized);
        if (index < 0)
            values.push(serialized);
        else
            values.splice(index, 1);
        MainCtx.setSettingValue(settingsKey, JSON.stringify(values));
        reload();
    }

    Component.onCompleted: { reload(); reloadVisits(); reloadArtists() }
}
