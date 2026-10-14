/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#ifndef VLC_WIDGET_THEME_HPP
#define VLC_WIDGET_THEME_HPP

#include <QApplication>
#include <QEvent>
#include <QFontDatabase>
#include <QPointer>
#include <QTimer>
#include <QWidget>

#include "maininterface/mainctx.hpp"
#include "style/systempalette.hpp"

// QWidget dialogs and menus use the QML color-scheme model and accent preference.
// Typography and geometry come from Figma NbLN6ylrDsmWVVTS8Jo10z,
// settings 999:5047 and menus 6062:13354 / 6065:13616.
class WidgetTheme final : public QObject
{
public:
    explicit WidgetTheme(MainCtx *ctx)
        : QObject(ctx), m_colors(new SystemPalette(this))
    {
        for (const char *font : {"Inter-Light.ttf", "Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf"})
            QFontDatabase::addApplicationFont(QStringLiteral(":/redesign/fonts/") + QLatin1String(font));
        QFont interfaceFont = qApp->font();
        interfaceFont.setFamily(QStringLiteral("Inter"));
        interfaceFont.setPixelSize(ctx->dp(14));
        qApp->setFont(interfaceFont);

        m_colors->setCtx(ctx);
        m_colors->setSource(ctx->getColorScheme()->currentScheme());
        m_colors->componentComplete();
        connect(ctx->getColorScheme(), &ColorSchemeModel::currentChanged,
                this, [this, ctx] {
            m_colors->setSource(ctx->getColorScheme()->currentScheme());
        });
        connect(m_colors, &SystemPalette::paletteChanged,
                this, [this] { refresh(); });

        qApp->installEventFilter(this);
        m_originalStyleSheet = qApp->styleSheet();
        m_styleSheet = QStringLiteral(R"(
            QWidget { color: palette(window-text); }
            QWidget:disabled { color: palette(disabled-text); }
            QDialog { background: palette(window); }
            QMenu { background: palette(window); color: palette(window-text);
                    border: 1px solid palette(mid); padding: 4px; }
            QMenu::item { padding: 12px 28px 12px 14px; border-radius: 2px; }
            QMenu::item:selected { background: palette(mid); color: palette(bright-text); }
            QMenu::separator { height: 1px; background: palette(mid); margin: 4px 8px; }
            QPushButton { border: 1px solid palette(mid); border-radius: 4px;
                          padding: 6px 12px; background: palette(button); }
            QPushButton:hover { border-color: palette(highlight); }
            QPushButton:focus { border: 2px solid palette(highlight); padding: 5px 11px; }
            QPushButton:checked, QPushButton:default { background: palette(highlight);
                          color: palette(highlighted-text); border-color: palette(highlight); }
            QLineEdit, QAbstractSpinBox, QComboBox { background: palette(base);
                          border: 1px solid palette(mid); border-radius: 6px; padding: 6px; }
            QLineEdit:focus, QAbstractSpinBox:focus, QComboBox:focus { border-color: palette(highlight); }
            QCheckBox, QRadioButton { spacing: 8px; }
            QCheckBox::indicator, QRadioButton::indicator {
                width: 16px; height: 16px; border: 1px solid palette(window-text);
                background: palette(base); }
            QCheckBox::indicator { border-radius: 2px; }
            QRadioButton::indicator { border-radius: 9px; }
            QCheckBox::indicator:checked {
                border-color: palette(highlight); background: palette(highlight);
                image: url(:/redesign/icons/checkbox-check.svg); }
            QRadioButton::indicator:checked { border-color: palette(highlight); background: palette(highlight); }
            QCheckBox::indicator:indeterminate { background: palette(mid); border-color: palette(highlight); }
            QCheckBox::indicator:hover, QRadioButton::indicator:hover { border-color: palette(highlight); }
            QCheckBox::indicator:disabled, QRadioButton::indicator:disabled { border-color: palette(disabled-text); }
            QGroupBox { border: 0; margin-top: 24px; padding: 12px 0 8px; }
            QGroupBox::title { subcontrol-origin: margin; left: 0; padding: 0;
                              font-size: 16px; color: palette(bright-text); }
            QHeaderView::section { background: palette(window); padding: 8px;
                                  border: 0; border-bottom: 1px solid palette(mid); }
            QAbstractItemView { border: 1px solid palette(mid); border-radius: 4px;
                                alternate-background-color: palette(alternate-base); }
            QAbstractItemView::item { padding: 6px; }
            QAbstractItemView::item:selected { background: palette(mid);
                                               color: palette(bright-text); }
            QWidget#preferencesHeader { background: palette(base); border-bottom: 1px solid palette(mid); }
            QWidget#preferencesSidebar { background: palette(alternate-base); border-radius: 0; }
            QWidget#preferencesSidebar QToolButton { background: transparent; color: palette(window-text); }
            QWidget#preferencesSidebar QToolButton:hover { background: palette(mid); color: palette(bright-text); }
            QWidget#preferencesSidebar QToolButton:checked { background: palette(mid); color: palette(bright-text); }
            QLabel#preferencesSection { color: palette(window-text); }
            QWidget#preferencesThemeSegments { background: palette(alternate-base); border-radius: 6px; }
            QPushButton#preferencesThemeChoice { background: transparent; color: palette(window-text);
                                                border: 0; border-radius: 4px; padding: 0; }
            QPushButton#preferencesThemeChoice:hover { background: palette(button); }
            QPushButton#preferencesThemeChoice:checked { background: palette(accent-surface);
                                                        color: palette(accent-label); border: 0; }
            QPushButton#preferencesThemeChoice:focus { border: 1px solid palette(highlight); padding: 0; }
            QToolButton#effectSettingsDisclosure { background: transparent; color: palette(window-text);
                                                   border: 0; padding: 0; }
            QToolButton#effectSettingsDisclosure:hover { color: palette(highlight); }
            QToolButton#effectSettingsDisclosure:focus { border: 1px solid palette(highlight); }
            QWidget[effectSettingsCard="true"] { background: palette(button); border: 0; border-radius: 6px; }
            QWidget[effectValueField="true"] { background: palette(base); border: 0; border-radius: 6px; }
            QTabWidget[effectPanels="true"]::pane { border: 0; background: transparent; }
            QSlider[filterOption="true"]::groove:horizontal {
                height: 14px; background: palette(base); border: 0; border-radius: 3px; }
            QSlider[filterOption="true"]::sub-page:horizontal {
                height: 14px; background: palette(accent-surface); border-radius: 3px; }
            QSlider[filterOption="true"]::handle:horizontal {
                width: 8px; margin: -5px 0; background: palette(highlight); border: 0; border-radius: 3px; }
            QSlider[filterOption="true"]::handle:horizontal:disabled { background: palette(disabled-text); }
            QSlider[filterOption="true"]::sub-page:horizontal:disabled { background: palette(mid); }
            QLabel#onboardingKeycap { background: palette(base); color: palette(bright-text);
                                     border: 1px solid palette(mid); border-radius: 4px; }
            QPushButton#onboardingThemeCard { background: palette(alternate-base); color: palette(window-text); }
            QPushButton#onboardingThemeCard:checked { border: 2px solid palette(highlight); }
            QWidget#preferencesHelp { background: palette(alternate-base);
                                      border-top: 1px solid palette(mid); padding: 8px; }
            QWidget#preferencesSidebar QPushButton { text-align: left; border: 0;
                                                      padding: 10px 12px; }
            QListWidget#dialogNavigation { background: palette(window); border: 0;
                                            border-right: 1px solid palette(mid); }
            QListWidget#dialogNavigation::item { padding: 8px; margin: 4px 8px; border-radius: 2px; }
            QToolTip { background: palette(tool-tip-base); color: palette(tool-tip-text);
                       border: 1px solid palette(mid); padding: 8px; }
        )");
        refresh();
    }

    ~WidgetTheme() override
    {
        if (qApp)
            qApp->removeEventFilter(this);
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() == QEvent::Polish)
            if (auto widget = qobject_cast<QWidget *>(object))
                // Style-sheet polishing runs after event filters and can reset
                // the palette. Apply ours after that work has completed.
                QTimer::singleShot(0, this, [this, guard = QPointer<QWidget>(widget)] {
                    if (guard)
                        guard->setPalette(m_palette);
                });
        return QObject::eventFilter(object, event);
    }

private:
    void refresh()
    {
        if (m_refreshing)
            return;
        m_refreshing = true;
        using C = ColorContext;
        const auto color = [this](C::ColorSet set, C::ColorSection section,
                                  C::ColorName name, C::ColorState state = C::Normal) {
            return m_colors->getColor(set, section, name, state);
        };
        m_palette = qApp->palette();
        m_palette.setColor(QPalette::Window, color(C::View, C::Bg, C::Primary));
        m_palette.setColor(QPalette::WindowText, color(C::View, C::Fg, C::Primary));
        m_palette.setColor(QPalette::Base, color(C::View, C::Bg, C::Secondary));
        m_palette.setColor(QPalette::AlternateBase, color(C::Window, C::Bg, C::Secondary));
        m_palette.setColor(QPalette::Text, color(C::View, C::Fg, C::Primary));
        m_palette.setColor(QPalette::PlaceholderText, color(C::View, C::Fg, C::Primary));
        m_palette.setColor(QPalette::Button, color(C::Window, C::Bg, C::Primary));
        m_palette.setColor(QPalette::ButtonText, color(C::View, C::Fg, C::Primary));
        m_palette.setColor(QPalette::BrightText, color(C::Item, C::Fg, C::Highlight));
        m_palette.setColor(QPalette::Mid, color(C::View, C::Decoration, C::Separator));
        m_palette.setColor(QPalette::Light, color(C::Window, C::Bg, C::Secondary));
        m_palette.setColor(QPalette::Midlight, color(C::Window, C::Bg, C::Secondary));
        m_palette.setColor(QPalette::Dark, color(C::View, C::Bg, C::Secondary));
        m_palette.setColor(QPalette::Shadow, color(C::View, C::Bg, C::Secondary));
        const bool dark = color(C::View, C::Bg, C::Primary).lightness()
                        < color(C::View, C::Fg, C::Primary).lightness();
        m_palette.setColor(QPalette::Highlight, dark ? m_colors->get_orange500()
                                                    : m_colors->get_orange800());
        m_palette.setColor(QPalette::HighlightedText, color(C::ButtonAccent, C::Fg, C::Primary));
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        m_palette.setColor(QPalette::Accent, m_palette.color(QPalette::Highlight));
#endif
        m_palette.setColor(QPalette::Link, color(C::View, C::Fg, C::Link));
        m_palette.setColor(QPalette::ToolTipBase, color(C::Tooltip, C::Bg, C::Primary));
        m_palette.setColor(QPalette::ToolTipText, color(C::Tooltip, C::Fg, C::Primary));
        for (auto role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText})
            m_palette.setColor(QPalette::Disabled, role, color(C::View, C::Fg, C::Primary, C::Disabled));

        // Resolve stylesheet colors here. Qt otherwise resolves palette(...) at
        // application-style polish time, before the per-widget palette exists.
        QString sheet = m_styleSheet;
        // Source: PreferenceToggle's Figma checked chamber and accent text.
        const QColor accent = m_palette.color(QPalette::Highlight);
        const bool referenceAccent = dark && accent == QColor(QStringLiteral("#D37918"));
        sheet.replace(QStringLiteral("palette(accent-surface)"),
                      (referenceAccent ? QColor(QStringLiteral("#371F06")) : accent.darker(384)).name(QColor::HexRgb));
        sheet.replace(QStringLiteral("palette(accent-label)"), accent.name(QColor::HexRgb));
        sheet.replace(QStringLiteral("palette(disabled-text)"),
                      m_palette.color(QPalette::Disabled, QPalette::Text).name(QColor::HexRgb));
        const QPair<const char *, QPalette::ColorRole> roles[] = {
            {"window", QPalette::Window}, {"window-text", QPalette::WindowText},
            {"base", QPalette::Base}, {"alternate-base", QPalette::AlternateBase},
            {"button", QPalette::Button}, {"mid", QPalette::Mid},
            {"highlight", QPalette::Highlight}, {"highlighted-text", QPalette::HighlightedText},
            {"bright-text", QPalette::BrightText},
            {"tool-tip-base", QPalette::ToolTipBase}, {"tool-tip-text", QPalette::ToolTipText}
        };
        for (const auto &role : roles)
            sheet.replace(QStringLiteral("palette(") + QLatin1String(role.first) + QLatin1Char(')'),
                          m_palette.color(role.second).name(QColor::HexRgb));
        qApp->setStyleSheet(m_originalStyleSheet + sheet);

        // Leave the application's native palette intact for System/Auto theme
        // detection, while every existing widget gets the redesigned roles.
        for (auto widget : QApplication::allWidgets())
            widget->setPalette(m_palette);
        m_refreshing = false;
    }

    SystemPalette *m_colors;
    QPalette m_palette;
    QString m_originalStyleSheet;
    QString m_styleSheet;
    bool m_refreshing = false;
};

#endif
