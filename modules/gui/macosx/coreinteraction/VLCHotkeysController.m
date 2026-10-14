/*****************************************************************************
 * VLCHotkeysController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2003-2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan dot org>
 *          David Fuhrmann <dfuhrmann # videolan dot org>
 *          Derk-Jan Hartman <hartman # videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCHotkeysController.h"

#import "main/VLCMain.h"
#import "extensions/NSString+Helpers.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import <vlc_configuration.h>
#import <vlc_actions.h>
#import <vlc_plugin.h>
#import <vlc_modules.h>

@interface VLCHotkeysController()
{
    NSArray *_usedHotkeys;
}
- (void)displaySeekFeedbackForKeycode:(uint32_t)keycode instance:(vlc_object_t *)instance;
- (void)clearPlaybackFeedbackForFrameKeycode:(uint32_t)keycode instance:(vlc_object_t *)instance;
@end

@implementation VLCHotkeysController

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self updateCurrentlyUsedHotkeys];
    }
    return self;
}

- (void)updateCurrentlyUsedHotkeys
{
    NSMutableArray *mutArray = [[NSMutableArray alloc] init];
    /* Get the main Module */
    module_t *p_main = module_get_main();
    assert(p_main);
    unsigned confsize;
    module_config_t *p_config;

    p_config = module_config_get(p_main, &confsize);

    for (size_t i = 0; i < confsize; i++) {
        module_config_t *p_item = p_config + i;

        if (p_item->i_type == CONFIG_ITEM_KEY
            && strncmp( p_item->psz_name, "global-", 7 ) != 0
            && !EMPTY_STR(p_item->psz_text)) {
            if (p_item->value.psz)
                [mutArray addObject:toNSStr(p_item->value.psz)];
        }
    }
    module_config_free(p_config);

    _usedHotkeys = [[NSArray alloc] initWithArray:mutArray copyItems:YES];
}

- (BOOL)handleVideoOutputKeyDown:(id)anEvent forVideoOutput:(vout_thread_t *)p_vout
{
    VLCPlayerController * const playerController = VLCMain.sharedInstance.playQueueController.playerController;
    unichar key = 0;
    vlc_value_t val;
    NSEventModifierFlags i_pressed_modifiers = 0;
    val.i_int = 0;

    i_pressed_modifiers = [anEvent modifierFlags];

    if (i_pressed_modifiers & NSEventModifierFlagShift)
        val.i_int |= KEY_MODIFIER_SHIFT;
    if (i_pressed_modifiers & NSEventModifierFlagControl)
        val.i_int |= KEY_MODIFIER_CTRL;
    if (i_pressed_modifiers & NSEventModifierFlagOption)
        val.i_int |= KEY_MODIFIER_ALT;
    if (i_pressed_modifiers & NSEventModifierFlagCommand)
        val.i_int |= KEY_MODIFIER_COMMAND;

    NSString *characters = [anEvent charactersIgnoringModifiers];
    if ([characters length] > 0) {
        key = [[characters lowercaseString] characterAtIndex: 0];

        if (key) {
            /* Escape should always get you out of fullscreen */
            if (key == (unichar) 0x1b) {
                if (playerController.fullscreen) {
                    [playerController toggleFullscreen];
                }
            }
            /* handle Lion's default key combo for fullscreen-toggle in addition to our own hotkeys */
            else if (key == 'f' && i_pressed_modifiers & NSEventModifierFlagControl && i_pressed_modifiers & NSEventModifierFlagCommand) {
                [playerController toggleFullscreen];
            } else if (p_vout) {
                val.i_int |= (int)CocoaKeyToVLC(key);
                vlc_object_t * const instance = VLC_OBJECT(vlc_object_instance(p_vout));
                [self clearPlaybackFeedbackForFrameKeycode:(uint32_t)val.i_int instance:instance];
                var_Set(instance, "key-pressed", val);
                [self displaySeekFeedbackForKeycode:(uint32_t)val.i_int instance:instance];
            }
            else
                msg_Dbg(getIntf(), "could not send keyevent to VLC core");

            return YES;
        }
    }

    return NO;
}

- (BOOL)performKeyEquivalent:(NSEvent *)anEvent
{
    BOOL enforced = NO;
    // these are key events which should be handled by vlc core, but are attached to a main menu item
    if (![self isEvent:anEvent forKey:"key-vol-up"] &&
        ![self isEvent:anEvent forKey:"key-vol-down"] &&
        ![self isEvent:anEvent forKey:"key-vol-mute"] &&
        ![self isEvent:anEvent forKey:"key-prev"] &&
        ![self isEvent:anEvent forKey:"key-next"] &&
        ![self isEvent:anEvent forKey:"key-jump+short"] &&
        ![self isEvent:anEvent forKey:"key-jump-short"]) {
        /* We indeed want to prioritize some Cocoa key equivalent against libvlc,
         so we perform the menu equivalent now. */
        if ([[NSApp mainMenu] performKeyEquivalent:anEvent]) {
            return TRUE;
        }
    } else {
        enforced = YES;
    }

    return [self hasDefinedShortcutKey:anEvent force:enforced] || [self keyEvent:anEvent];
}

- (BOOL)isEvent:(NSEvent *)anEvent forKey:(const char *)keyString
{
    char *key = config_GetPsz(keyString);
    unsigned int keyModifiers = VLCModifiersToCocoa(key);
    NSString *vlcKeyString = VLCKeyToString(key);
    FREENULL(key);

    NSString *characters = [anEvent charactersIgnoringModifiers];
    if ([characters length] > 0) {
        return [[characters lowercaseString] isEqualToString: vlcKeyString] &&
        (keyModifiers & NSEventModifierFlagShift)     == ([anEvent modifierFlags] & NSEventModifierFlagShift) &&
        (keyModifiers & NSEventModifierFlagControl)   == ([anEvent modifierFlags] & NSEventModifierFlagControl) &&
        (keyModifiers & NSEventModifierFlagOption) == ([anEvent modifierFlags] & NSEventModifierFlagOption) &&
        (keyModifiers & NSEventModifierFlagCommand)   == ([anEvent modifierFlags] & NSEventModifierFlagCommand);
    }
    return NO;
}

- (BOOL)keyEvent:(NSEvent *)anEvent
{
    BOOL eventHandled = NO;
    NSString * characters = [anEvent charactersIgnoringModifiers];
    if ([characters length] > 0) {
        unichar key = [characters characterAtIndex: 0];

        if (key) {
            VLCPlayerController * const playerController = VLCMain.sharedInstance.playQueueController.playerController;
            vout_thread_t * const p_vout = playerController.mainVideoOutputThread;
            if (p_vout != NULL) {
                /* Escape */
                if (key == (unichar) 0x1b) {
                    if (var_GetBool(p_vout, "fullscreen")) {
                        [playerController toggleFullscreen];
                        eventHandled = YES;
                    }
                }
                vout_Release(p_vout);
            }
        }
    }
    return eventHandled;
}

- (BOOL)hasDefinedShortcutKey:(NSEvent *)o_event force:(BOOL)enforced
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return NO;

    unichar key = 0;
    vlc_value_t val;
    NSEventModifierFlags i_pressed_modifiers = 0;

    val.i_int = 0;
    i_pressed_modifiers = [o_event modifierFlags];

    if (i_pressed_modifiers & NSEventModifierFlagControl)
        val.i_int |= KEY_MODIFIER_CTRL;

    if (i_pressed_modifiers & NSEventModifierFlagOption)
        val.i_int |= KEY_MODIFIER_ALT;

    if (i_pressed_modifiers & NSEventModifierFlagShift)
        val.i_int |= KEY_MODIFIER_SHIFT;

    if (i_pressed_modifiers & NSEventModifierFlagCommand)
        val.i_int |= KEY_MODIFIER_COMMAND;

    NSString * characters = [o_event charactersIgnoringModifiers];
    if ([characters length] > 0) {
        key = [[characters lowercaseString] characterAtIndex: 0];

        /* handle Lion's default key combo for fullscreen-toggle in addition to our own hotkeys */
        if (key == 'f' && i_pressed_modifiers & NSEventModifierFlagControl && i_pressed_modifiers & NSEventModifierFlagCommand) {
            [VLCMain.sharedInstance.playQueueController.playerController toggleFullscreen];
            return YES;
        }

        if (!enforced) {
            switch(key) {
                case NSDeleteCharacter:
                case NSDeleteFunctionKey:
                case NSDeleteCharFunctionKey:
                case NSBackspaceCharacter:
                case NSUpArrowFunctionKey:
                case NSDownArrowFunctionKey:
                case NSEnterCharacter:
                case NSCarriageReturnCharacter:
                    return NO;
            }
        }

        val.i_int |= CocoaKeyToVLC(key);

        BOOL b_found_key = NO;
        NSUInteger numberOfUsedHotkeys = [_usedHotkeys count];
        for (NSUInteger i = 0; i < numberOfUsedHotkeys; i++) {
            const char *str = [[_usedHotkeys objectAtIndex:i] UTF8String];
            unsigned int i_keyModifiers = VLCModifiersToCocoa((char *)str);

            if ([[characters lowercaseString] isEqualToString:VLCKeyToString((char *)str)] &&
                (i_keyModifiers & NSEventModifierFlagShift)     == (i_pressed_modifiers & NSEventModifierFlagShift) &&
                (i_keyModifiers & NSEventModifierFlagControl)   == (i_pressed_modifiers & NSEventModifierFlagControl) &&
                (i_keyModifiers & NSEventModifierFlagOption) == (i_pressed_modifiers & NSEventModifierFlagOption) &&
                (i_keyModifiers & NSEventModifierFlagCommand)   == (i_pressed_modifiers & NSEventModifierFlagCommand)) {
                b_found_key = YES;
                break;
            }
        }

        if (b_found_key) {
            vlc_object_t * const instance = VLC_OBJECT(vlc_object_instance(p_intf));
            [self clearPlaybackFeedbackForFrameKeycode:(uint32_t)val.i_int instance:instance];
            var_SetInteger(instance, "key-pressed", val.i_int);
            [self displaySeekFeedbackForKeycode:(uint32_t)val.i_int instance:instance];
            return YES;
        }
    }

    return NO;
}

- (void)clearPlaybackFeedbackForFrameKeycode:(uint32_t)keycode instance:(vlc_object_t *)instance
{
    const char * const frameActions[] = {"frame-next", "frame-previous"};
    for (size_t i = 0; i < sizeof(frameActions) / sizeof(frameActions[0]); ++i) {
        uint_fast32_t *configuredKeys = NULL;
        const size_t count = vlc_actions_get_keycodes(instance, frameActions[i], false, &configuredKeys);
        BOOL matches = NO;
        for (size_t keyIndex = 0; keyIndex < count; ++keyIndex) {
            if (configuredKeys[keyIndex] == keycode) {
                matches = YES;
                break;
            }
        }
        free(configuredKeys);
        if (matches) {
            [VLCMain.sharedInstance.playQueueController.playerController clearPlaybackFeedback];
            return;
        }
    }
}

- (void)displaySeekFeedbackForKeycode:(uint32_t)keycode instance:(vlc_object_t *)instance
{
    // Use the action resolved by VLC, rather than assuming an arrow always seeks.
    // Verify its configured keycodes because an unbound key leaves key-action unchanged.
    const vlc_action_id_t action = (vlc_action_id_t)var_GetInteger(instance, "key-action");
    static const struct {
        vlc_action_id_t action;
        const char *name;
        const char *interval;
        BOOL navigation;
    } seeks[] = {
        {ACTIONID_JUMP_BACKWARD_EXTRASHORT, "jump-extrashort", "extrashort-jump-size", NO},
        {ACTIONID_JUMP_FORWARD_EXTRASHORT, "jump+extrashort", "extrashort-jump-size", NO},
        {ACTIONID_JUMP_BACKWARD_SHORT, "jump-short", "short-jump-size", NO},
        {ACTIONID_JUMP_FORWARD_SHORT, "jump+short", "short-jump-size", NO},
        {ACTIONID_JUMP_BACKWARD_MEDIUM, "jump-medium", "medium-jump-size", NO},
        {ACTIONID_JUMP_FORWARD_MEDIUM, "jump+medium", "medium-jump-size", NO},
        {ACTIONID_JUMP_BACKWARD_LONG, "jump-long", "long-jump-size", NO},
        {ACTIONID_JUMP_FORWARD_LONG, "jump+long", "long-jump-size", NO},
        {ACTIONID_NAV_LEFT, "nav-left", "short-jump-size", YES},
        {ACTIONID_NAV_RIGHT, "nav-right", "short-jump-size", YES},
    };

    for (size_t i = 0; i < sizeof(seeks) / sizeof(seeks[0]); ++i) {
        if (seeks[i].action != action)
            continue;

        uint_fast32_t *configuredKeys = NULL;
        const size_t count = vlc_actions_get_keycodes(instance, seeks[i].name, false, &configuredKeys);
        BOOL matches = NO;
        for (size_t keyIndex = 0; keyIndex < count; ++keyIndex) {
            if (configuredKeys[keyIndex] == keycode) {
                matches = YES;
                break;
            }
        }
        free(configuredKeys);
        if (!matches || var_InheritInteger(instance, seeks[i].interval) <= 0)
            return;

        VLCPlayerController * const player = VLCMain.sharedInstance.playQueueController.playerController;
        if (!player.seekable || (player.playerState != VLC_PLAYER_STATE_PLAYING &&
                                player.playerState != VLC_PLAYER_STATE_PAUSED))
            return;

        if (seeks[i].navigation) {
            const struct vlc_player_title * const title = player.selectedTitle;
            if (title && (title->flags & (VLC_PLAYER_TITLE_MENU | VLC_PLAYER_TITLE_INTERACTIVE)))
                return;

            // Navigation keys rotate 360-degree video instead of seeking.
            BOOL changesViewpoint = NO;
            for (NSValue *output in player.allVideoOutputThreads) {
                vout_thread_t * const vout = output.pointerValue;
                changesViewpoint |= var_GetBool(vout, "viewpoint-changeable");
                vout_Release(vout);
            }
            if (changesViewpoint)
                return;
        }

        [player displaySeekFeedback];
        return;
    }
}

@end
