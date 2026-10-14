/*****************************************************************************
 * preferences.hpp : Preferences
 *****************************************************************************
 * Copyright (C) 2006-2007 the VideoLAN team
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
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

#ifndef QVLC_PREFS_DIALOG_H_
#define QVLC_PREFS_DIALOG_H_ 1

#include "widgets/native/qvlcframe.hpp"
#include "dialogs/preferences/simple_preferences.hpp"
#include <QJsonArray>

class ExpertPrefsTable;
class PrefsTree;
class SPrefsCatList;
class SPrefsPanel;
class QTreeWidgetItem;
class QGroupBox;
class QRadioButton;
class QWidget;
class QCheckBox;
class SearchLineEdit;
class QLineEdit;
class QStackedWidget;
class QSplitter;
class QToolButton;
class PluginDialog;
class QListWidget;
class QTableWidget;

class PrefsDialog : public QVLCDialog
{
    Q_OBJECT
public:
    PrefsDialog( QWindow *, qt_intf_t *, bool hotkeysOnly = false );
    virtual ~PrefsDialog();

protected:
    bool eventFilter( QObject *, QEvent * ) override;

private:
    size_t count;
    module_t **p_list;

    /* View stack */
    QStackedWidget *stack;

    /* View selection */
    enum { SIMPLE, ADVANCED, EXPERT };
    QGroupBox *types;
    QRadioButton *simple, *all, *expert;
    QLineEdit *settings_search;
    QLabel *m_headerTitle;
    QLabel *help_description;
    QLabel *no_results;
    bool m_hotkeysOnly;
    int m_currentGroup = SPrefsGroupGeneral;
    QWidget *m_extensionsWidget = nullptr;
    std::unique_ptr<PluginDialog> m_extensionsManager;
    QList<ConfigControl *> m_extensionsControls;
    QPushButton *m_groupAdvanced;

    void installHelp( QWidget * );
    void updateHelp( QWidget * );
    SPrefsPanel *ensureSimplePanel( int );

    /* Simple view components */
    QWidget *simple_split_widget;
    QWidget *simple_tree_panel;
    SPrefsCatList *simple_tree;
    QStackedWidget *simple_panels_stack;
    SPrefsPanel *simple_panels[SPrefsMax];

    /* Advanced view components */
    QSplitter *advanced_split_widget;
    QWidget *advanced_tree_panel;
    SearchLineEdit *tree_filter;
    QCheckBox *current_filter;
    PrefsTree *advanced_tree;
    QStackedWidget *advanced_panels_stack;

    /* Expert view components */
    QWidget *expert_widget;
    QGridLayout *expert_widget_layout;
    SearchLineEdit *expert_table_filter;
    QCheckBox *expert_table_filter_modified;
    ExpertPrefsTable *expert_table;
    QLabel *expert_text;

private slots:
    void setExpert();
    void setAdvanced();
    void setSimple();

    void changeExpertDesc( const QModelIndex &, const QModelIndex & );
    void changeAdvPanel( QTreeWidgetItem * );
    void changeSimplePanel( int );
    void advancedTreeFilterChanged( const QString & );
    void expertTableFilterChanged( const QString & );
    void expertTableFilterModifiedToggled( bool );
    void onlyLoadedToggled();
    void searchSettings( const QString & );
    void showGroupAdvanced();

    void save();
    void cancel();
    void reset();
    void close() { save(); }
};

/** User-created snapshots of the original configuration and Qt GUI layout.
 * Selecting and inspecting a profile never writes settings; Apply is explicit. */
class SettingsProfilesDialog : public QVLCDialog
{
    Q_OBJECT
public:
    SettingsProfilesDialog(QWindow *, qt_intf_t *, const QString &selectedId = QString());
    static QVariantList profiles(qt_intf_t *);
    static QString currentProfile(qt_intf_t *);
    static bool updateCurrent(qt_intf_t *);
    void selectProfile(const QString &);
    void newProfile();
signals:
    void profilesChanged();
    void aboutToApply();
private:
    QJsonArray m_profiles;
    QString m_current;
    QListWidget *m_list;
    QTableWidget *m_values;
    QLineEdit *m_search;
    QPushButton *m_save;
    QPushButton *m_apply;
    QPushButton *m_delete;
    void refreshList(const QString &selectedId);
    void reviewProfile();
    void filterValues();
    void saveProfile();
    void applyProfile();
    void deleteProfile();
    bool persist();
    void reportSaveError();
};

#endif
