/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "interface_options_model.hpp"
#include "maininterface/mainctx.hpp"
#include "dialogs/dialogs/dialogmodel.hpp"
#include "qt.hpp"

#include <QColor>
#include <QFontDatabase>
#include <QLocale>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <vlc_configuration.h>
#include <vlc_plugin.h>
#include <vlc_modules.h>
#include "player/player_controller.hpp"
#include "../../../audio_filter/equalizer_presets.h"

InterfaceOptionsModel::InterfaceOptionsModel(QObject* parent)
    : QAbstractListModel(parent)
{
    reload();
}

MainCtx* InterfaceOptionsModel::ctx() const { return m_ctx; }

void InterfaceOptionsModel::setCtx(MainCtx* ctx)
{
    if (m_ctx == ctx)
        return;
    m_ctx = ctx;
    if (filterModule())
        reload();
    emit ctxChanged();
}

void InterfaceOptionsModel::setGroup(Group group)
{
    if (m_group == group || group < SubtitleFormatting || group > RotateFilter)
        return;
    m_group = group;
    reload();
    emit groupChanged();
}

bool InterfaceOptionsModel::dirty() const
{
    if (filterModule() && m_filterEnabled != m_originalFilterEnabled)
        return true;
    for (const auto& row : m_rows)
        if (row.value != row.original)
            return true;
    return false;
}

const char* InterfaceOptionsModel::filterModule() const
{
    switch (m_group)
    {
    case EqualizerFilter: return "equalizer";
    case CompressorFilter: return "compressor";
    case SpatializerFilter: return "spatializer";
    case StereoWidenerFilter: return "stereowiden";
    case PitchFilter: return "scaletempo_pitch";
    case AdjustmentFilter: return "adjust";
    case SharpenFilter: return "sharpen";
    case BandingFilter: return "gradfun";
    case GrainFilter: return "grain";
    case CropFilter: return "croppadd";
    case ExtractionFilter: return "extract";
    case ColorThresholdFilter: return "colorthres";
    case NegateFilter: return "invert";
    case PosterizeFilter: return "posterize";
    case GradientFilter: return "gradient";
    case SepiaFilter: return "sepia";
    case TransformFilter: return "transform";
    case RotateFilter: return "rotate";
    default: return nullptr;
    }
}

bool InterfaceOptionsModel::audioFilter() const
{
    return m_group >= EqualizerFilter && m_group <= PitchFilter;
}

bool InterfaceOptionsModel::filterAvailable() const
{
    const auto* name = filterModule();
    return name && module_find(name);
}

QString InterfaceOptionsModel::filterTitle() const
{
    // Source: Figma Audio/Video filter sections and the original VLC Effects labels.
    switch (m_group)
    {
    case EqualizerFilter: return qtr("Equalizer");
    case CompressorFilter: return qtr("Compressor");
    case SpatializerFilter: return qtr("Spatializer");
    case StereoWidenerFilter: return qtr("Stereo Widener");
    case PitchFilter: return qtr("Adjust pitch");
    case AdjustmentFilter: return qtr("Image adjust");
    case SharpenFilter: return qtr("Sharpen");
    case BandingFilter: return qtr("Banding removal");
    case GrainFilter: return qtr("Film Grain");
    case CropFilter: return qtr("Crop");
    case ExtractionFilter: return qtr("Color Extraction");
    case ColorThresholdFilter: return qtr("Color Threshold");
    case NegateFilter: return qtr("Negate Colors");
    case PosterizeFilter: return qtr("Posterize");
    case GradientFilter: return qtr("Gradient");
    case SepiaFilter: return qtr("Sepia");
    case TransformFilter: return qtr("Transform");
    case RotateFilter: return qtr("Rotate");
    default: return {};
    }
}

void InterfaceOptionsModel::setFilterEnabled(bool enabled)
{
    if (!filterAvailable() || m_filterEnabled == enabled)
        return;
    m_filterEnabled = enabled;
    emit filterEnabledChanged();
    emit dirtyChanged();
}

static QStringList filterChain(const QString& value)
{
    return value.split(QLatin1Char(':'), Qt::SkipEmptyParts);
}

static QString changedFilterChain(const QString& value, const QString& name, bool enabled)
{
    auto entries = filterChain(value);
    const auto matches = [&name](const QString& entry) { return entry.section(QLatin1Char('{'), 0, 0) == name; };
    const auto found = std::find_if(entries.cbegin(), entries.cend(), matches);
    if (enabled && found == entries.cend())
        entries.append(name);
    else if (!enabled)
        entries.erase(std::remove_if(entries.begin(), entries.end(), matches), entries.end());
    return entries.join(QLatin1Char(':'));
}

int InterfaceOptionsModel::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : count();
}

QHash<int, QByteArray> InterfaceOptionsModel::roleNames() const
{
    return {{TitleRole, "title"}, {HelpRole, "help"}, {KindRole, "kind"},
            {ValueRole, "value"}, {ChoicesRole, "choices"},
            {MinimumRole, "minimum"}, {MaximumRole, "maximum"},
            {HasRangeRole, "hasRange"}, {ColorRole, "colorValue"}, {BandsRole, "bands"}};
}

QVariant InterfaceOptionsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= count())
        return {};
    const auto& row = m_rows[index.row()];
    const auto* option = row.option;
    switch (role)
    {
    case Qt::DisplayRole:
    case TitleRole: return qfut(option->psz_text);
    case HelpRole: return option->psz_longtext ? qfut(option->psz_longtext) : QString();
    case KindRole: return row.kind;
    case ValueRole: return row.value;
    case ChoicesRole: return row.choices;
    case MinimumRole:
        if (!strcmp(option->psz_name, "equalizer-preamp")) return -20.f;
        return IsConfigFloatType(option->i_type) ? QVariant(option->min.f) : QVariant::fromValue(option->min.i);
    case MaximumRole:
        if (!strcmp(option->psz_name, "equalizer-preamp")) return 20.f;
        return IsConfigFloatType(option->i_type) ? QVariant(option->max.f) : QVariant::fromValue(option->max.i);
    case HasRangeRole:
        if (!strcmp(option->psz_name, "equalizer-preamp")) return true;
        // Module config uses numeric type limits when no usable range was
        // supplied (src/modules/entry.c). Keep those values in the raw editor;
        // a full-width integer or float range is not a meaningful slider.
        return IsConfigFloatType(option->i_type)
            ? option->min.f < option->max.f && option->min.f > std::numeric_limits<float>::lowest()
                && option->max.f < std::numeric_limits<float>::max()
            : option->min.i < option->max.i && option->min.i > std::numeric_limits<int64_t>::min()
                && option->max.i < std::numeric_limits<int64_t>::max();
    case ColorRole: return QColor::fromRgb(row.value.toUInt());
    case BandsRole: return row.kind == QStringLiteral("bands") ? bands(row) : QVariantList();
    default: return {};
    }
}

void InterfaceOptionsModel::reload()
{
    // These option names are already exposed by VLC's simple preferences and
    // effects panels. Missing plugin options stay absent from the QML model.
    static const char* subtitles[] = {"freetype-font", "sub-text-scale",
        "freetype-color", "freetype-outline-thickness", "freetype-outline-color",
        "sub-margin", "sub-position", "secondary-sub-alignment",
        "secondary-sub-margin", "subsdec-encoding", "sub-language", "sub-track"};
    static const char* audio[] = {"audio-track", "audio-language", "equalizer-preset",
                                 "equalizer-preamp", "equalizer-bands", "equalizer-2pass"};
    static const char* video[] = {"transform-type", "rotate-angle", "contrast",
                                 "brightness", "hue", "saturation", "gamma"};
    static const char* audioDefaults[] = {"audio-track", "audio-language"};
    static const char* equalizer[] = {"equalizer-preset", "equalizer-preamp", "equalizer-bands", "equalizer-2pass"};
    static const char* compressor[] = {"compressor-rms-peak", "compressor-attack", "compressor-release",
                                      "compressor-threshold", "compressor-ratio", "compressor-knee", "compressor-makeup-gain"};
    static const char* spatializer[] = {"spatializer-roomsize", "spatializer-width", "spatializer-wet", "spatializer-dry", "spatializer-damp"};
    static const char* widener[] = {"stereowiden-delay", "stereowiden-feedback", "stereowiden-crossfeed", "stereowiden-dry-mix"};
    static const char* pitch[] = {"pitch-shift"};
    static const char* adjustment[] = {"hue", "brightness", "contrast", "saturation", "gamma"};
    static const char* sharpen[] = {"sharpen-sigma"};
    static const char* banding[] = {"gradfun-radius", "gradfun-strength"};
    static const char* grain[] = {"grain-variance", "grain-period-min", "grain-period-max"};
    static const char* crop[] = {"croppadd-croptop", "croppadd-cropbottom", "croppadd-cropleft", "croppadd-cropright"};
    static const char* extraction[] = {"extract-component"};
    static const char* threshold[] = {"colorthres-color", "colorthres-saturationthres", "colorthres-similaritythres"};
    static const char* posterize[] = {"posterize-level"};
    static const char* gradient[] = {"gradient-mode", "gradient-color", "gradient-cartoon"};
    static const char* sepia[] = {"sepia-intensity"};
    static const char* transform[] = {"transform-type"};
    static const char* rotate[] = {"rotate-angle", "rotate-use-motion"};
    const char* const* names = subtitles;
    size_t size = sizeof(subtitles) / sizeof(subtitles[0]);
    if (m_group == AudioEqualizer) { names = audio; size = sizeof(audio) / sizeof(audio[0]); }
    if (m_group == VideoAdjustment) { names = video; size = sizeof(video) / sizeof(video[0]); }
#define FILTER_OPTIONS(group, array) case group: names = array; size = sizeof(array) / sizeof(array[0]); break
    switch (m_group)
    {
        FILTER_OPTIONS(AudioDefaults, audioDefaults);
        FILTER_OPTIONS(EqualizerFilter, equalizer);
        FILTER_OPTIONS(CompressorFilter, compressor);
        FILTER_OPTIONS(SpatializerFilter, spatializer);
        FILTER_OPTIONS(StereoWidenerFilter, widener);
        FILTER_OPTIONS(PitchFilter, pitch);
        FILTER_OPTIONS(AdjustmentFilter, adjustment);
        FILTER_OPTIONS(SharpenFilter, sharpen);
        FILTER_OPTIONS(BandingFilter, banding);
        FILTER_OPTIONS(GrainFilter, grain);
        FILTER_OPTIONS(CropFilter, crop);
        FILTER_OPTIONS(ExtractionFilter, extraction);
        FILTER_OPTIONS(ColorThresholdFilter, threshold);
        FILTER_OPTIONS(PosterizeFilter, posterize);
        FILTER_OPTIONS(GradientFilter, gradient);
        FILTER_OPTIONS(SepiaFilter, sepia);
        FILTER_OPTIONS(TransformFilter, transform);
        FILTER_OPTIONS(RotateFilter, rotate);
    case NegateFilter: size = 0; break;
    default: break;
    }
#undef FILTER_OPTIONS

    beginResetModel();
    m_rows.clear();
    for (size_t i = 0; i < size; ++i)
    {
        const auto* option = config_FindConfig(names[i]);
        if (!option || !option->psz_text)
            continue;
        Row row;
        row.option = option;
        if (IsConfigStringType(option->i_type))
        {
            char* value = config_GetPsz(option->psz_name);
            row.value = value ? qfu(value) : QString();
            free(value);
            row.kind = option->i_type == CONFIG_ITEM_FONT ? QStringLiteral("font")
                       : !strcmp(option->psz_name, "equalizer-bands") ? QStringLiteral("bands") : QStringLiteral("string");
            if (option->i_type == CONFIG_ITEM_FONT)
            {
                // The native FontConfigControl likewise uses installed font families.
                const auto families = QFontDatabase::families();
                for (const auto& family : families)
                    row.choices.append(QVariantMap{{QStringLiteral("text"), family}, {QStringLiteral("value"), family}});
            }
            else
            {
                char** values = nullptr;
                char** texts = nullptr;
                const ssize_t count = config_GetPszChoices(option->psz_name, &values, &texts);
                for (ssize_t j = 0; j < count; ++j)
                {
                    row.choices.append(QVariantMap{{QStringLiteral("text"), texts[j] ? qfut(texts[j]) : qfu(values[j])},
                                                  {QStringLiteral("value"), qfu(values[j])}});
                    free(values[j]);
                    free(texts[j]);
                }
                free(values);
                free(texts);
            }
        }
        else if (IsConfigIntegerType(option->i_type))
        {
            row.value = QVariant::fromValue(config_GetInt(option->psz_name));
            row.kind = option->i_type == CONFIG_ITEM_RGB || !strcmp(option->psz_name, "extract-component") ? QStringLiteral("color")
                       : option->i_type == CONFIG_ITEM_BOOL ? QStringLiteral("boolean") : QStringLiteral("integer");
            int64_t* values = nullptr;
            char** texts = nullptr;
            const ssize_t count = config_GetIntChoices(option->psz_name, &values, &texts);
            for (ssize_t j = 0; j < count; ++j)
            {
                row.choices.append(QVariantMap{{QStringLiteral("text"), texts[j] ? qfut(texts[j]) : QString::number(values[j])},
                                              {QStringLiteral("value"), QVariant::fromValue(values[j])}});
                free(texts[j]);
            }
            free(values);
            free(texts);
        }
        else if (IsConfigFloatType(option->i_type))
        {
            row.value = config_GetFloat(option->psz_name);
            row.kind = QStringLiteral("float");
        }
        else
            continue;
        row.original = row.value;
        m_rows.push_back(std::move(row));
    }
    const auto* filter = filterModule();
    m_filterEnabled = false;
    if (filter)
    {
        const auto* chainKey = audioFilter() ? "audio-filter" : "video-filter";
        char* chain = config_GetPsz(chainKey);
        const auto readActiveOutput = [this, chainKey, &chain](auto* output)
        {
            // Effects may have unsaved live values. Opening this GUI must
            // reflect those values rather than reset the user's active filter.
            if ((var_Type(output, chainKey) & VLC_VAR_CLASS) == VLC_VAR_STRING)
            {
                free(chain);
                chain = var_GetString(output, chainKey);
            }
            for (auto& row : m_rows)
            {
                const auto* key = row.option->psz_name;
                const int type = var_Type(output, key) & VLC_VAR_CLASS;
                if (type == VLC_VAR_STRING)
                {
                    char* value = var_GetString(output, key);
                    row.value = value ? qfu(value) : QString();
                    free(value);
                }
                else if (type == VLC_VAR_FLOAT)
                    row.value = var_GetFloat(output, key);
                else if (type == VLC_VAR_BOOL)
                    row.value = QVariant::fromValue(int64_t(var_GetBool(output, key)));
                else if (type == VLC_VAR_INTEGER)
                    row.value = QVariant::fromValue(var_GetInteger(output, key));
                row.original = row.value;
            }
        };
        const auto* intf = m_ctx ? m_ctx->getIntf() : nullptr;
        if (intf && intf->p_mainPlayerController)
        {
            if (audioFilter())
            {
                if (const auto output = intf->p_mainPlayerController->getAout())
                    readActiveOutput(output.get());
            }
            else if (const auto output = intf->p_mainPlayerController->getVout())
                readActiveOutput(output.get());
        }
        for (const auto& entry : filterChain(chain ? qfu(chain) : QString()))
            if (entry.section(QLatin1Char('{'), 0, 0) == qfu(filter))
                m_filterEnabled = true;
        free(chain);
    }
    m_originalFilterEnabled = m_filterEnabled;
    endResetModel();
    emit filterEnabledChanged();
    emit countChanged();
    emit dirtyChanged();
}

bool InterfaceOptionsModel::setValue(int index, const QVariant& input)
{
    if (index < 0 || index >= count())
        return false;
    auto& row = m_rows[index];
    const auto* option = row.option;
    QVariant value;
    bool valid = true;
    if (IsConfigStringType(option->i_type))
    {
        value = input.toString();
        if (row.kind == QStringLiteral("bands"))
        {
            const auto gains = value.toString().simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
            valid = gains.size() <= EQZ_BANDS_MAX;
            for (const auto& entry : gains)
            {
                bool numberValid = false;
                const float gain = QLocale::c().toFloat(entry, &numberValid);
                valid = valid && numberValid && std::isfinite(gain) && gain >= -20 && gain <= 20;
            }
        }
    }
    else if (IsConfigFloatType(option->i_type))
    {
        double number = input.toDouble(&valid);
        if (!valid && input.metaType().id() == QMetaType::QString)
            number = QLocale().toDouble(input.toString(), &valid);
        valid = valid && std::isfinite(number) && std::isfinite(float(number))
                && (!(option->min.f < option->max.f) || (number >= option->min.f && number <= option->max.f));
        if (!strcmp(option->psz_name, "equalizer-preamp"))
            valid = valid && number >= -20 && number <= 20;
        value = float(number);
    }
    else
    {
        int64_t number;
        if (row.kind == QStringLiteral("color") && (input.metaType().id() == QMetaType::QColor
            || (input.metaType().id() == QMetaType::QString && input.toString().startsWith(QLatin1Char('#')))))
        {
            const QColor color = input.metaType().id() == QMetaType::QColor ? input.value<QColor>() : QColor(input.toString());
            valid = color.isValid();
            number = int64_t(color.rgb() & 0xffffff);
        }
        else
        {
            number = input.toLongLong(&valid);
            if (!valid && input.metaType().id() == QMetaType::QString)
                number = QLocale().toLongLong(input.toString(), &valid);
        }
        if (input.metaType().id() == QMetaType::Double || input.metaType().id() == QMetaType::Float)
            valid = valid && input.toDouble() == number;
        valid = valid && (!(option->min.i < option->max.i) || (number >= option->min.i && number <= option->max.i));
        if (option->i_type == CONFIG_ITEM_RGB)
            valid = valid && number >= 0 && number <= 0xffffff;
        if (option->i_type == CONFIG_ITEM_BOOL)
            valid = valid && (number == 0 || number == 1);
        value = QVariant::fromValue(number);
    }
    if (!valid)
        return false;
    if (!row.choices.empty() && option->i_type != CONFIG_ITEM_RGB)
    {
        bool found = false;
        for (const auto& choice : row.choices)
            if (choice.toMap().value(QStringLiteral("value")) == value) { found = true; break; }
        if (!found)
            return false;
    }
    if (row.value == value)
        return true;
    row.value = value;
    emit dataChanged(this->index(index), this->index(index), {ValueRole, ColorRole, BandsRole});
    if (!strcmp(option->psz_name, "equalizer-preset"))
        for (const auto& preset : eqz_preset_10b)
            if (value.toString() == qfu(preset.psz_name))
            {
                QStringList gains;
                for (const float gain : preset.f_amp)
                    gains.append(QLocale::c().toString(gain, 'g', std::numeric_limits<float>::max_digits10));
                for (int i = 0; i < count(); ++i)
                    if (m_rows[i].kind == QStringLiteral("bands"))
                        setValue(i, gains.join(QLatin1Char(' ')));
                    else if (!strcmp(m_rows[i].option->psz_name, "equalizer-preamp"))
                        setValue(i, preset.f_preamp);
                break;
            }
    emit dirtyChanged();
    return true;
}

QVariantList InterfaceOptionsModel::bands(const Row& row) const
{
    // Frequencies and presets come from the same table used by VLC's filter
    // and native Equalizer. Its native sliders allow -20..20 dB in 0.1 dB steps.
    const float* frequencies = config_FindConfig("equalizer-vlcfreqs") && config_GetInt("equalizer-vlcfreqs")
                             ? f_vlc_frequency_table_10b : f_iso_frequency_table_10b;
    const eqz_preset_t* preset = nullptr;
    for (const auto& option : m_rows)
        if (!strcmp(option.option->psz_name, "equalizer-preset"))
            for (const auto& candidate : eqz_preset_10b)
                if (option.value.toString() == qfu(candidate.psz_name))
                    preset = &candidate;
    const auto values = row.value.toString().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QVariantList result;
    for (int i = 0; i < EQZ_BANDS_MAX; ++i)
    {
        bool valid = false;
        const float configured = i < values.size() ? QLocale::c().toFloat(values[i], &valid) : 0.f;
        float gain = valid && std::isfinite(configured) ? configured : 0.f;
        if (values.isEmpty() && preset)
            gain = preset->f_amp[i];
        result.append(QVariantMap{{QStringLiteral("text"), QStringLiteral("%1 Hz").arg(frequencies[i])},
                                  {QStringLiteral("value"), gain},
                                  {QStringLiteral("minimum"), -20.f}, {QStringLiteral("maximum"), 20.f},
                                  {QStringLiteral("step"), 0.1f}});
    }
    return result;
}

bool InterfaceOptionsModel::setBand(int row, int band, double value)
{
    if (row < 0 || row >= count() || m_rows[row].kind != QStringLiteral("bands")
        || band < 0 || band >= EQZ_BANDS_MAX || !std::isfinite(value) || value < -20 || value > 20)
        return false;
    const auto current = bands(m_rows[row]);
    QStringList values;
    for (int i = 0; i < current.size(); ++i)
        values.append(QLocale::c().toString(i == band ? value : current[i].toMap().value(QStringLiteral("value")).toDouble(), 'g', std::numeric_limits<float>::max_digits10));
    return setValue(row, values.join(QLatin1Char(' ')));
}

bool InterfaceOptionsModel::apply()
{
    return applyBatch({QVariant::fromValue(static_cast<QObject*>(this))});
}

void InterfaceOptionsModel::writeConfiguration()
{
    for (const auto& row : m_rows)
    {
        // A filter section may have opened with unsaved Effects values from
        // the active output. Explicit Apply saves that section's whole state;
        // ordinary preferences still write only their edited options.
        if (!filterModule() && row.value == row.original)
            continue;
        const auto* option = row.option;
        if (IsConfigStringType(option->i_type))
            config_PutPsz(option->psz_name, qtu(row.value.toString()));
        else if (IsConfigFloatType(option->i_type))
            config_PutFloat(option->psz_name, row.value.toFloat());
        else
            config_PutInt(option->psz_name, row.value.toLongLong());
    }
    if (const auto* filter = filterModule())
    {
        const auto* key = audioFilter() ? "audio-filter" : "video-filter";
        char* chain = config_GetPsz(key);
        const QString changed = changedFilterChain(chain ? qfu(chain) : QString(), qfu(filter), m_filterEnabled);
        free(chain);
        config_PutPsz(key, qtu(changed));
    }
}

bool InterfaceOptionsModel::applyBatch(const QVariantList& objects)
{
    const QPointer<MainCtx> context(m_ctx);
    if (!context || !context->getIntf() || objects.isEmpty())
        return false;
    QVector<QPointer<InterfaceOptionsModel>> models;
    for (const auto& object : objects)
    {
        auto* model = qobject_cast<InterfaceOptionsModel*>(object.value<QObject*>());
        if (!model || model->m_ctx != context)
            return false;
        if (!models.contains(model)) models.append(model);
    }
    // A whole preset uses one existing config save, avoiding partial saves
    // caused by applying each visible GUI section independently.
    for (const auto& model : models) model->writeConfiguration();
    if (config_SaveConfigFile(context->getIntf()) != 0)
    {
        // Same published error strings and error model as PrefsDialog::save().
        DialogErrorModel::getInstance(context->getIntf())->pushError(
            qtr("Cannot save Configuration"), qtr("Preferences file could not be saved"));
        return false;
    }
    for (const auto& model : models) if (model) model->applyLiveFilter();
    if (context) context->reloadPrefs();
    for (const auto& model : models) if (model) model->reload();
    return true;
}

void InterfaceOptionsModel::applyLiveFilter()
{
    const auto* filter = filterModule();
    auto* intf = m_ctx ? m_ctx->getIntf() : nullptr;
    if (!filter || !intf || !intf->p_mainPlayerController)
        return;
    const auto applyOptions = [this](auto* output)
    {
        for (const auto& row : m_rows)
        {
            const auto* option = row.option;
            const int type = var_Type(output, option->psz_name) & VLC_VAR_CLASS;
            if (type == VLC_VAR_STRING)
                var_SetString(output, option->psz_name, qtu(row.value.toString()));
            else if (type == VLC_VAR_FLOAT)
                var_SetFloat(output, option->psz_name, row.value.toFloat());
            else if (type == VLC_VAR_BOOL)
                var_SetBool(output, option->psz_name, row.value.toBool());
            else if (type == VLC_VAR_INTEGER)
                var_SetInteger(output, option->psz_name, row.value.toLongLong());
        }
    };
    if (audioFilter())
    {
        // Same public action used by AudioFilterControlWidget::enable().
        vlc_player_aout_EnableFilter(intf->p_player, filter, m_filterEnabled);
        if (const auto output = intf->p_mainPlayerController->getAout())
            applyOptions(output.get());
    }
    else if (const auto output = intf->p_mainPlayerController->getVout())
    {
        if ((var_Type(output.get(), "video-filter") & VLC_VAR_CLASS) == VLC_VAR_STRING)
        {
            char* chain = var_GetString(output.get(), "video-filter");
            const QString changed = changedFilterChain(chain ? qfu(chain) : QString(), qfu(filter), m_filterEnabled);
            free(chain);
            var_SetString(output.get(), "video-filter", qtu(changed));
        }
        applyOptions(output.get());
    }
}

void InterfaceOptionsModel::cancel() { reload(); }

QVariantMap InterfaceOptionsModel::snapshot() const
{
    QVariantMap options;
    for (const auto& row : m_rows)
        options.insert(qfu(row.option->psz_name), row.value);
    // The config keys and values come from this model's existing whitelist,
    // config metadata and actual active output. These identifiers stay hidden.
    return {{QStringLiteral("group"), int(m_group)},
            {QStringLiteral("options"), options},
            {QStringLiteral("filterEnabled"), m_filterEnabled}};
}

bool InterfaceOptionsModel::restoreSnapshot(const QVariantMap& snapshot)
{
    if (snapshot.value(QStringLiteral("group"), -1).toInt() != int(m_group))
        return false;
    const auto options = snapshot.value(QStringLiteral("options")).toMap();
    const auto previous = m_rows;
    const bool previousEnabled = m_filterEnabled;
    // Native preset selection supplies its gains first. Afterwards restore
    // the saved preamp/bands in their model order, retaining any custom gains.
    for (int row = 0; row < count(); ++row)
    {
        const auto key = qfu(m_rows[row].option->psz_name);
        if (!options.contains(key) || options.value(key) == m_rows[row].value)
            continue;
        if (!setValue(row, options.value(key)))
        {
            m_rows = previous;
            m_filterEnabled = previousEnabled;
            if (count())
                emit dataChanged(index(0), index(count() - 1), {ValueRole, ColorRole, BandsRole});
            emit filterEnabledChanged();
            emit dirtyChanged();
            return false;
        }
    }
    if (filterModule() && filterAvailable())
        setFilterEnabled(snapshot.value(QStringLiteral("filterEnabled"), m_filterEnabled).toBool());
    return true;
}
