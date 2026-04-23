import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'go_men_billing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoMenPlanStorage.ensureLoaded();
  await GoMenThemeStorage.ensureLoaded();
  if (!GoMenPlanStorage.isProSync &&
      GoMenThemeStorage.notifier.value == GoMenThemeMode.gold) {}
  runApp(const GoMenApp());
}

Future<void> copyText(
  BuildContext context,
  String text, {
  String label = 'コピーしました',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
}

Color goMenMutedTextColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFFE7D7BE) : const Color(0xFF5E6975);
}

String formatDateTime(String isoString) {
  try {
    final dt = DateTime.parse(isoString).toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  } catch (_) {
    return isoString;
  }
}

String extractConsultTheme(String title) {
  const prefix = '相談 / ';
  if (title.startsWith(prefix)) {
    return title.substring(prefix.length).trim();
  }
  return '';
}

enum GoMenPlan { free, pro }

// === go-men personality types start ===
class TypeOption {
  final String key;
  final String label;
  final String aiHint;

  const TypeOption({
    required this.key,
    required this.label,
    required this.aiHint,
  });
}

const String unknownTypeKey = 'UNKNOWN';

const TypeOption unknownTypeOption = TypeOption(
  key: unknownTypeKey,
  label: '不明 / 無回答',
  aiHint: '',
);

const List<TypeOption> standard16TypeOptions = [
  TypeOption(key: 'INTJ', label: 'INTJ（戦略家）', aiHint: '長期目線・構造化・結論重視'),
  TypeOption(key: 'INTP', label: 'INTP（探究家）', aiHint: '分析好き・仮説思考・距離感重視'),
  TypeOption(key: 'ENTJ', label: 'ENTJ（指揮官）', aiHint: '主導力・決断力・効率重視'),
  TypeOption(key: 'ENTP', label: 'ENTP（発明家）', aiHint: '柔軟・議論好き・刺激志向'),
  TypeOption(key: 'INFJ', label: 'INFJ（提唱者）', aiHint: '洞察・理想志向・深い共感'),
  TypeOption(key: 'INFP', label: 'INFP（仲介者）', aiHint: '価値観重視・繊細・内省的'),
  TypeOption(key: 'ENFJ', label: 'ENFJ（主人公）', aiHint: '対人配慮・巻き込み力・温かさ'),
  TypeOption(key: 'ENFP', label: 'ENFP（運動家）', aiHint: '感情表現豊か・好奇心・自由さ'),
  TypeOption(key: 'ISTJ', label: 'ISTJ（管理者）', aiHint: '誠実・安定志向・責任感'),
  TypeOption(key: 'ISFJ', label: 'ISFJ（擁護者）', aiHint: '気配り・献身性・慎重さ'),
  TypeOption(key: 'ESTJ', label: 'ESTJ（幹部）', aiHint: '実務力・明快・秩序重視'),
  TypeOption(key: 'ESFJ', label: 'ESFJ（領事官）', aiHint: '社交性・思いやり・協調重視'),
  TypeOption(key: 'ISTP', label: 'ISTP（巨匠）', aiHint: '冷静・観察力・単独行動も得意'),
  TypeOption(key: 'ISFP', label: 'ISFP（冒険家）', aiHint: '感性・やさしさ・自然体'),
  TypeOption(key: 'ESTP', label: 'ESTP（起業家）', aiHint: '行動力・即断即決・現場対応力'),
  TypeOption(key: 'ESFP', label: 'ESFP（エンターテイナー）', aiHint: '明るさ・親しみやすさ・今を楽しむ'),
];

const List<TypeOption> standard16TypeOptionsWithUnknown = [
  unknownTypeOption,
  ...standard16TypeOptions,
];

const List<TypeOption> love16TypeOptions = [
  TypeOption(key: 'LCRO', label: 'LCRO（ボス猫）', aiHint: '自分のペース・我が道・繊細さもある'),
  TypeOption(
    key: 'LCRE',
    label: 'LCRE（隠れベイビー）',
    aiHint: '誠実・不器用・甘えたい気持ちを隠しやすい',
  ),
  TypeOption(key: 'LCPO', label: 'LCPO（主役体質）', aiHint: '存在感・影響力・華やかさ'),
  TypeOption(key: 'LCPE', label: 'LCPE（ツンデレヤンキー）', aiHint: '元気・照れ屋・仲間想い'),
  TypeOption(key: 'LARO', label: 'LARO（憧れの先輩）', aiHint: '大人っぽい・さっぱり・信頼されやすい'),
  TypeOption(key: 'LARE', label: 'LARE（カリスマバランサー）', aiHint: '統率力・調整力・安定感'),
  TypeOption(key: 'LAPO', label: 'LAPO（パーフェクトカメレオン）', aiHint: '多面性・器用さ・切り替え上手'),
  TypeOption(key: 'LAPE', label: 'LAPE（キャプテンライオン）', aiHint: '強さ・優しさ・包容力'),
  TypeOption(key: 'FCRO', label: 'FCRO（ロマンスマジシャン）', aiHint: '距離感上手・観察力・空気を読む'),
  TypeOption(key: 'FCRE', label: 'FCRE（ちゃっかりうさぎ）', aiHint: '人懐っこい・冷静・危機察知が早い'),
  TypeOption(key: 'FCPO', label: 'FCPO（恋愛モンスター）', aiHint: '愛され力・ノリの良さ・感情表現'),
  TypeOption(key: 'FCPE', label: 'FCPE（忠犬ハチ公）', aiHint: '素直・情が深い・まっすぐ'),
  TypeOption(key: 'FARO', label: 'FARO（不思議生命体）', aiHint: '独特さ・自然体・読み切れない魅力'),
  TypeOption(key: 'FARE', label: 'FARE（敏腕マネージャー）', aiHint: '冷静・観察力・支えるのが上手い'),
  TypeOption(key: 'FAPO', label: 'FAPO（デビル天使）', aiHint: '自由さ・優しさ・意外性'),
  TypeOption(key: 'FAPE', label: 'FAPE（最後の恋人）', aiHint: '包容力・安心感・長く寄り添える'),
];

const List<TypeOption> love16TypeOptionsWithUnknown = [
  unknownTypeOption,
  ...love16TypeOptions,
];

bool hasKnownTypeKey(String? key) {
  final normalized = (key ?? '').trim().toUpperCase();
  return normalized.isNotEmpty && normalized != unknownTypeKey;
}

TypeOption resolveTypeOption(List<TypeOption> options, String? key) {
  final normalized = (key ?? '').trim().toUpperCase();
  if (normalized.isEmpty || normalized == unknownTypeKey) {
    return unknownTypeOption;
  }

  for (final option in options) {
    if (option.key == normalized) {
      return option;
    }
  }

  return unknownTypeOption;
}

String typeLabelFor(List<TypeOption> options, String? key) {
  return resolveTypeOption(options, key).label;
}

String typeAiHintFor(List<TypeOption> options, String? key) {
  return resolveTypeOption(options, key).aiHint;
}

class ProfileTypeSelection {
  final String selfStandardTypeKey;
  final String selfLoveTypeKey;
  final String partnerStandardTypeKey;
  final String partnerLoveTypeKey;

  const ProfileTypeSelection({
    this.selfStandardTypeKey = unknownTypeKey,
    this.selfLoveTypeKey = unknownTypeKey,
    this.partnerStandardTypeKey = unknownTypeKey,
    this.partnerLoveTypeKey = unknownTypeKey,
  });

  static const empty = ProfileTypeSelection();

  String get selfStandardTypeLabel =>
      typeLabelFor(standard16TypeOptions, selfStandardTypeKey);

  String get selfLoveTypeLabel =>
      typeLabelFor(love16TypeOptions, selfLoveTypeKey);

  String get partnerStandardTypeLabel =>
      typeLabelFor(standard16TypeOptions, partnerStandardTypeKey);

  String get partnerLoveTypeLabel =>
      typeLabelFor(love16TypeOptions, partnerLoveTypeKey);

  bool get hasAnyKnownType =>
      hasKnownTypeKey(selfStandardTypeKey) ||
      hasKnownTypeKey(selfLoveTypeKey) ||
      hasKnownTypeKey(partnerStandardTypeKey) ||
      hasKnownTypeKey(partnerLoveTypeKey);

  ProfileTypeSelection copyWith({
    String? selfStandardTypeKey,
    String? selfLoveTypeKey,
    String? partnerStandardTypeKey,
    String? partnerLoveTypeKey,
  }) {
    return ProfileTypeSelection(
      selfStandardTypeKey: selfStandardTypeKey ?? this.selfStandardTypeKey,
      selfLoveTypeKey: selfLoveTypeKey ?? this.selfLoveTypeKey,
      partnerStandardTypeKey:
          partnerStandardTypeKey ?? this.partnerStandardTypeKey,
      partnerLoveTypeKey: partnerLoveTypeKey ?? this.partnerLoveTypeKey,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'selfStandardTypeKey': selfStandardTypeKey,
      'selfLoveTypeKey': selfLoveTypeKey,
      'partnerStandardTypeKey': partnerStandardTypeKey,
      'partnerLoveTypeKey': partnerLoveTypeKey,
    };
  }

  factory ProfileTypeSelection.fromMap(Map<String, dynamic> map) {
    String readKey(String name) {
      final raw = (map[name] ?? '').toString().trim().toUpperCase();
      return raw.isEmpty ? unknownTypeKey : raw;
    }

    return ProfileTypeSelection(
      selfStandardTypeKey: readKey('selfStandardTypeKey'),
      selfLoveTypeKey: readKey('selfLoveTypeKey'),
      partnerStandardTypeKey: readKey('partnerStandardTypeKey'),
      partnerLoveTypeKey: readKey('partnerLoveTypeKey'),
    );
  }
}

List<String> buildProfileTypeContextLines(
  ProfileTypeSelection selection, {
  bool includeLoveTypes = true,
}) {
  final lines = <String>[];

  if (hasKnownTypeKey(selection.selfStandardTypeKey)) {
    final option = resolveTypeOption(
      standard16TypeOptions,
      selection.selfStandardTypeKey,
    );
    lines.add('自分の通常16タイプ: ${option.label}');
    if (option.aiHint.isNotEmpty) {
      lines.add('自分の通常16タイプの短い傾向: ${option.aiHint}');
    }
  }

  if (includeLoveTypes && hasKnownTypeKey(selection.selfLoveTypeKey)) {
    final option = resolveTypeOption(
      love16TypeOptions,
      selection.selfLoveTypeKey,
    );
    lines.add('自分の恋愛16タイプ: ${option.label}');
    if (option.aiHint.isNotEmpty) {
      lines.add('自分の恋愛16タイプの短い傾向: ${option.aiHint}');
    }
  }

  if (hasKnownTypeKey(selection.partnerStandardTypeKey)) {
    final option = resolveTypeOption(
      standard16TypeOptions,
      selection.partnerStandardTypeKey,
    );
    lines.add('相手の通常16タイプ: ${option.label}');
    if (option.aiHint.isNotEmpty) {
      lines.add('相手の通常16タイプの短い傾向: ${option.aiHint}');
    }
  }

  if (includeLoveTypes && hasKnownTypeKey(selection.partnerLoveTypeKey)) {
    final option = resolveTypeOption(
      love16TypeOptions,
      selection.partnerLoveTypeKey,
    );
    lines.add('相手の恋愛16タイプ: ${option.label}');
    if (option.aiHint.isNotEmpty) {
      lines.add('相手の恋愛16タイプの短い傾向: ${option.aiHint}');
    }
  }

  return lines;
}

String buildProfileTypeContext(
  ProfileTypeSelection selection, {
  bool includeLoveTypes = true,
}) {
  return buildProfileTypeContextLines(
    selection,
    includeLoveTypes: includeLoveTypes,
  ).join('\n');
}

class ProfileTypeStorage {
  static const _key = 'go_men_profile_type_selection_map_v1';

  static Future<Map<String, ProfileTypeSelection>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }

      final result = <String, ProfileTypeSelection>{};

      decoded.forEach((key, value) {
        final id = key.toString().trim();
        if (id.isEmpty) {
          return;
        }

        if (value is Map<String, dynamic>) {
          result[id] = ProfileTypeSelection.fromMap(value);
          return;
        }

        if (value is Map) {
          result[id] = ProfileTypeSelection.fromMap(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      });

      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveAll(
    Map<String, ProfileTypeSelection> selections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};

    selections.forEach((key, value) {
      final id = key.trim();
      if (id.isEmpty) {
        return;
      }
      map[id] = value.toMap();
    });

    await prefs.setString(_key, jsonEncode(map));
  }

  static Future<ProfileTypeSelection> loadForProfileId(String profileId) async {
    final id = profileId.trim();
    if (id.isEmpty) {
      return ProfileTypeSelection.empty;
    }

    final all = await loadAll();
    return all[id] ?? ProfileTypeSelection.empty;
  }

  static Future<void> saveForProfileId(
    String profileId,
    ProfileTypeSelection selection,
  ) async {
    final id = profileId.trim();
    if (id.isEmpty) {
      return;
    }

    final all = await loadAll();
    all[id] = selection;
    await saveAll(all);
  }

  static Future<void> removeForProfileId(String profileId) async {
    final id = profileId.trim();
    if (id.isEmpty) {
      return;
    }

    final all = await loadAll();
    all.remove(id);
    await saveAll(all);
  }
}
// === go-men personality types end ===

class PlanLimits {
  static const int freeDailyUses = 3;
  static const int freeSavedResults = 3;
  static const int freeProfiles = 1;
  static const int proSavedResults = 9999;
  static const int proProfiles = 9999;

  static int savedResultsForPlan(GoMenPlan plan) {
    return plan == GoMenPlan.pro ? proSavedResults : freeSavedResults;
  }

  static int profilesForPlan(GoMenPlan plan) {
    return plan == GoMenPlan.pro ? proProfiles : freeProfiles;
  }

  static String labelForPlan(GoMenPlan plan) {
    return plan == GoMenPlan.pro ? 'Go-men Pro' : '無料版';
  }
}

class GoMenPlanStorage {
  static const _key = 'go_men_plan';
  static final ValueNotifier<GoMenPlan> notifier = ValueNotifier(
    GoMenPlan.free,
  );

  static bool get isProSync => notifier.value == GoMenPlan.pro;

  static Future<void> ensureLoaded() async {
    notifier.value = await loadPlan();
  }

  static Future<GoMenPlan> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == 'pro') {
      return GoMenPlan.pro;
    }
    return GoMenPlan.free;
  }

  static Future<void> setPlan(GoMenPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, plan == GoMenPlan.pro ? 'pro' : 'free');
    notifier.value = plan;
  }
}

List<String> uniquePreserveOrder(List<String> items) {
  final seen = <String>{};
  final result = <String>[];

  for (final item in items) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) {
      result.add(trimmed);
    }
  }

  return result;
}

String _typeLabelFromOptions(String typeKey, List<TypeOption> options) {
  final normalized = typeKey.trim();
  for (final option in options) {
    if (option.key == normalized) {
      return option.label;
    }
  }
  return '不明 / 無回答';
}

List<String> activeProfileTypeLines(RelationshipProfile profile) {
  final selfParts = <String>[
    _typeLabelFromOptions(profile.selfStandardTypeId, standard16TypeOptions),
  ];
  final partnerParts = <String>[
    _typeLabelFromOptions(profile.partnerStandardTypeId, standard16TypeOptions),
  ];

  if (profile.relationType == 'couple') {
    selfParts.add(
      _typeLabelFromOptions(profile.selfLoveTypeId, love16TypeOptions),
    );
    partnerParts.add(
      _typeLabelFromOptions(profile.partnerLoveTypeId, love16TypeOptions),
    );
  }

  return ['自分：${selfParts.join('、')}', '相手：${partnerParts.join('、')}'];
}

String buildTrendHeadline(List<SavedResultItem> items) {
  if (items.isEmpty) {
    return 'まだこの相手との相談履歴はありません。';
  }

  final themes = uniquePreserveOrder(
    items
        .map((item) => extractConsultTheme(item.title))
        .where((item) => item.isNotEmpty)
        .toList(),
  );

  final latest = items.first;

  if (themes.isNotEmpty) {
    final themeText = themes.take(2).join('・');
    return '最近は「$themeText」で流れがこじれやすいです。直近では「${latest.subtitle}」が提案されています。';
  }

  return '最近はこの相手との送信前チェックが続いています。直近では「${latest.subtitle}」が提案されています。';
}

List<String> buildTrendBullets(List<SavedResultItem> items) {
  if (items.isEmpty) {
    return [];
  }

  final bullets = <String>[];
  final themes = uniquePreserveOrder(
    items
        .map((item) => extractConsultTheme(item.title))
        .where((item) => item.isNotEmpty)
        .toList(),
  );

  bullets.add('直近${items.length}件の記録を踏まえて次の提案を出します。');

  if (themes.isNotEmpty) {
    bullets.add('最近の相談テーマ: ${themes.take(3).join(' / ')}');
  }

  bullets.add('直近の提案: ${items.first.subtitle}');

  if (items.length >= 2) {
    bullets.add('同じ相手との流れを踏まえて、今回も悪化しにくい返し方を優先します。');
  }

  return bullets.take(3).toList();
}

enum GoMenThemeMode { ivory, gold, pink }

class GoMenThemeSpec {
  const GoMenThemeSpec({
    required this.mode,
    required this.label,
    required this.isPremium,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.cardColor,
    required this.accentColor,
    required this.previewTextColor,
    required this.description,
  });

  final GoMenThemeMode mode;
  final String label;
  final bool isPremium;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color cardColor;
  final Color accentColor;
  final Color previewTextColor;
  final String description;
}

GoMenThemeSpec goMenThemeSpecFor(GoMenThemeMode mode) {
  switch (mode) {
    case GoMenThemeMode.gold:
      return const GoMenThemeSpec(
        mode: GoMenThemeMode.gold,
        label: 'Gold',
        isPremium: true,
        backgroundTop: Color(0xFFFFF3CC),
        backgroundBottom: Color(0xFFE7C86A),
        cardColor: Color(0xFFFFFBF0),
        accentColor: Color(0xFFB8860B),
        previewTextColor: Color(0xFF4A3510),
        description: '見やすさを保ったプレミアムゴールドテーマ',
      );

    case GoMenThemeMode.ivory:
      return const GoMenThemeSpec(
        mode: GoMenThemeMode.ivory,
        label: 'Ivory',
        isPremium: false,
        backgroundTop: Color(0xFFFBF7F0),
        backgroundBottom: Color(0xFFF3ECE2),
        cardColor: Colors.white,
        accentColor: Color(0xFFC6A87A),
        previewTextColor: Color(0xFF5E4A34),
        description: 'Go-men の標準テーマ。やさしく上品な印象',
      );

    case GoMenThemeMode.pink:
      return const GoMenThemeSpec(
        mode: GoMenThemeMode.pink,
        label: 'Pink',
        isPremium: true,
        backgroundTop: Color(0xFFFFF2F7),
        backgroundBottom: Color(0xFFFFE0EC),
        cardColor: Colors.white,
        accentColor: Color(0xFFE75480),
        previewTextColor: Color(0xFF7A274A),
        description: '恋愛相談に寄せたやわらかいプレミアムテーマ',
      );
  }
}

ThemeData buildGoMenTheme(GoMenThemeSpec spec) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: spec.accentColor,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: spec.backgroundBottom,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: spec.cardColor,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.cardColor.withValues(alpha: 0.78),
      foregroundColor: Colors.black87,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black87,
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
  );
}

class GoMenThemeStorage {
  static const _key = 'go_men_theme_mode';
  static final ValueNotifier<GoMenThemeMode> notifier = ValueNotifier(
    GoMenThemeMode.ivory,
  );

  static bool canUse(GoMenThemeMode mode) {
    return mode == GoMenThemeMode.ivory || GoMenPlanStorage.isProSync;
  }

  static Future<void> ensureLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    final loaded =
        GoMenThemeMode.values.where((e) => e.name == raw).firstOrNull ??
        GoMenThemeMode.ivory;

    notifier.value = canUse(loaded) ? loaded : GoMenThemeMode.ivory;
  }

  static Future<void> setTheme(GoMenThemeMode mode) async {
    final nextMode = canUse(mode) ? mode : GoMenThemeMode.ivory;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, nextMode.name);
    notifier.value = nextMode;
  }
}

class GoMenApp extends StatelessWidget {
  const GoMenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GoMenThemeMode>(
      valueListenable: GoMenThemeStorage.notifier,
      builder: (context, mode, _) {
        final spec = goMenThemeSpecFor(mode);

        return MaterialApp(
          title: 'Go-men',
          debugShowCheckedModeBanner: false,
          theme: buildGoMenTheme(spec),
          builder: (context, child) {
            return _AppViewport(child: child ?? const SizedBox.shrink());
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}

const double kAppMaxWidth = 460;

class _AppViewport extends StatelessWidget {
  const _AppViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = goMenThemeSpecFor(GoMenThemeStorage.notifier.value);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [spec.backgroundTop, spec.backgroundBottom],
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kAppMaxWidth),
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -30,
                  child: _ThemeGlow(
                    size: 220,
                    color: spec.accentColor.withValues(
                      alpha: isDark ? 0.22 : 0.16,
                    ),
                  ),
                ),
                Positioned(
                  top: 120,
                  left: -70,
                  child: _ThemeGlow(
                    size: 180,
                    color: spec.accentColor.withValues(
                      alpha: isDark ? 0.14 : 0.10,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: spec.backgroundBottom.withValues(
                      alpha: isDark ? 0.86 : 0.72,
                    ),
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeGlow extends StatelessWidget {
  const _ThemeGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class RelationshipProfile {
  const RelationshipProfile({
    required this.id,
    required this.displayName,
    required this.relationType,
    this.relationDetails = const [],
    required this.sensitiveTo,
    required this.worksWellWith,
    required this.distancePreference,
    required this.commonConflicts,
    required this.avoidWords,
    required this.notes,
    required this.createdAt,
    this.selfStandardTypeId = 'unknown',
    this.selfLoveTypeId = 'unknown',
    this.partnerStandardTypeId = 'unknown',
    this.partnerLoveTypeId = 'unknown',
  });

  final String id;
  final String displayName;
  final String relationType;
  final List<String> relationDetails;
  final String sensitiveTo;
  final String worksWellWith;
  final String distancePreference;
  final String commonConflicts;
  final String avoidWords;
  final String notes;
  final String createdAt;
  final String selfStandardTypeId;
  final String selfLoveTypeId;
  final String partnerStandardTypeId;
  final String partnerLoveTypeId;

  String get relationDetailSummary {
    return relationDetails
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' / ');
  }

  String get relationSummaryLabel {
    if (relationDetailSummary.isEmpty) {
      return relationLabel;
    }
    return '$relationLabel / $relationDetailSummary';
  }

  String get relationLabel {
    switch (relationType) {
      case 'couple':
        return '恋人・パートナー';
      case 'friend':
        return '友人';
      case 'family':
        return '家族';
      case 'family_parent_child':
      case 'parent_child':
        return '家族 / 親子';
      case 'family_sibling':
        return '家族 / 兄弟姉妹';
      case 'family_inlaw':
        return '家族 / 義家族';
      case 'family_other':
        return '家族 / その他';
      case 'other':
        return 'その他';
      default:
        return '未設定';
    }
  }

  String toProfileContext() {
    TypeOption? findOption(List<TypeOption> options, String id) {
      for (final option in options) {
        if (option.key == id) {
          return option;
        }
      }
      return null;
    }

    final lines = <String>[
      '相手の名前・呼び名: $displayName',
      '関係性: $relationSummaryLabel',
      '傷つきやすい言い方: ${sensitiveTo.isEmpty ? '未設定' : sensitiveTo}',
      '通りやすい伝え方: ${worksWellWith.isEmpty ? '未設定' : worksWellWith}',
      '距離感の傾向: ${distancePreference.isEmpty ? '未設定' : distancePreference}',
      'よく揉めるテーマ: ${commonConflicts.isEmpty ? '未設定' : commonConflicts}',
      '避けたいワード: ${avoidWords.isEmpty ? '未設定' : avoidWords}',
      '補足メモ: ${notes.isEmpty ? '未設定' : notes}',
    ];

    void addTypeLines(String title, String id, List<TypeOption> options) {
      final normalized = id.trim().isEmpty ? 'unknown' : id.trim();
      final option = findOption(options, normalized);
      final label = option?.label ?? '不明 / 無回答';
      lines.add('$title: $label');
      final hint = (option?.aiHint ?? '').trim();
      if (hint.isNotEmpty && normalized != 'unknown') {
        lines.add('$titleの短い傾向: $hint');
      }
    }

    addTypeLines('自分の通常16タイプ', selfStandardTypeId, standard16TypeOptions);
    if (relationType == 'couple') {
      addTypeLines('自分の恋愛16タイプ', selfLoveTypeId, love16TypeOptions);
    }
    addTypeLines('相手の通常16タイプ', partnerStandardTypeId, standard16TypeOptions);
    if (relationType == 'couple') {
      addTypeLines('相手の恋愛16タイプ', partnerLoveTypeId, love16TypeOptions);
    }

    return lines.join('\n');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'relationType': relationType,
      'relationDetails': relationDetails,
      'sensitiveTo': sensitiveTo,
      'worksWellWith': worksWellWith,
      'distancePreference': distancePreference,
      'commonConflicts': commonConflicts,
      'avoidWords': avoidWords,
      'notes': notes,
      'createdAt': createdAt,
      'selfStandardTypeId': selfStandardTypeId,
      'selfLoveTypeId': selfLoveTypeId,
      'partnerStandardTypeId': partnerStandardTypeId,
      'partnerLoveTypeId': partnerLoveTypeId,
    };
  }

  factory RelationshipProfile.fromMap(Map<String, dynamic> map) {
    List<String> readStringList(dynamic raw) {
      if (raw is! List) return const <String>[];
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    String readString(String key, [String fallback = '']) {
      final raw = map[key];
      if (raw == null) return fallback;
      final value = raw.toString().trim();
      return value.isEmpty ? fallback : value;
    }

    return RelationshipProfile(
      id: readString('id', DateTime.now().millisecondsSinceEpoch.toString()),
      displayName: readString('displayName'),
      relationType: readString('relationType'),
      relationDetails: readStringList(map['relationDetails']),
      sensitiveTo: readString('sensitiveTo'),
      worksWellWith: readString('worksWellWith'),
      distancePreference: readString('distancePreference'),
      commonConflicts: readString('commonConflicts'),
      avoidWords: readString('avoidWords'),
      notes: readString('notes'),
      createdAt: readString('createdAt', DateTime.now().toIso8601String()),
      selfStandardTypeId: readString('selfStandardTypeId', 'unknown'),
      selfLoveTypeId: readString('selfLoveTypeId', 'unknown'),
      partnerStandardTypeId: readString('partnerStandardTypeId', 'unknown'),
      partnerLoveTypeId: readString('partnerLoveTypeId', 'unknown'),
    );
  }

  RelationshipProfile copyWith({
    String? id,
    String? displayName,
    String? relationType,
    List<String>? relationDetails,
    String? sensitiveTo,
    String? worksWellWith,
    String? distancePreference,
    String? commonConflicts,
    String? avoidWords,
    String? notes,
    String? createdAt,
    String? selfStandardTypeId,
    String? selfLoveTypeId,
    String? partnerStandardTypeId,
    String? partnerLoveTypeId,
  }) {
    return RelationshipProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      relationType: relationType ?? this.relationType,
      relationDetails: relationDetails ?? this.relationDetails,
      sensitiveTo: sensitiveTo ?? this.sensitiveTo,
      worksWellWith: worksWellWith ?? this.worksWellWith,
      distancePreference: distancePreference ?? this.distancePreference,
      commonConflicts: commonConflicts ?? this.commonConflicts,
      avoidWords: avoidWords ?? this.avoidWords,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      selfStandardTypeId: selfStandardTypeId ?? this.selfStandardTypeId,
      selfLoveTypeId: selfLoveTypeId ?? this.selfLoveTypeId,
      partnerStandardTypeId:
          partnerStandardTypeId ?? this.partnerStandardTypeId,
      partnerLoveTypeId: partnerLoveTypeId ?? this.partnerLoveTypeId,
    );
  }
}

class DraftScreenshot {
  const DraftScreenshot({required this.name, required this.bytesBase64});

  final String name;
  final String bytesBase64;
}

class ConsultationDraft {
  const ConsultationDraft({
    this.relationType,
    this.relationLabel,
    this.relationDetails = const [],
    this.theme,
    this.themeAnswers = const [],
    this.themeAnswerKeys = const [],
    this.currentStatus,
    this.currentStatusKey,
    this.emotionLevel,
    this.goal,
    this.goalKey,
    this.chatText,
    this.note,
    this.screenshotNames = const [],
    this.screenshots = const [],
    this.selectedProfile,
  });

  final String? relationType;
  final String? relationLabel;
  final List<String> relationDetails;
  final String? theme;
  final List<String> themeAnswers;
  final List<String> themeAnswerKeys;
  final String? currentStatus;
  final String? currentStatusKey;
  final String? emotionLevel;
  final String? goal;
  final String? goalKey;
  final String? chatText;
  final String? note;
  final List<String> screenshotNames;
  final List<DraftScreenshot> screenshots;
  final RelationshipProfile? selectedProfile;

  ConsultationDraft copyWith({
    String? relationType,
    String? relationLabel,
    List<String>? relationDetails,
    String? theme,
    List<String>? themeAnswers,
    List<String>? themeAnswerKeys,
    String? currentStatus,
    String? currentStatusKey,
    String? emotionLevel,
    String? goal,
    String? goalKey,
    String? chatText,
    String? note,
    List<String>? screenshotNames,
    List<DraftScreenshot>? screenshots,
    RelationshipProfile? selectedProfile,
  }) {
    return ConsultationDraft(
      relationType: relationType ?? this.relationType,
      relationLabel: relationLabel ?? this.relationLabel,
      relationDetails: relationDetails ?? this.relationDetails,
      theme: theme ?? this.theme,
      themeAnswers: themeAnswers ?? this.themeAnswers,
      themeAnswerKeys: themeAnswerKeys ?? this.themeAnswerKeys,
      currentStatus: currentStatus ?? this.currentStatus,
      currentStatusKey: currentStatusKey ?? this.currentStatusKey,
      emotionLevel: emotionLevel ?? this.emotionLevel,
      goal: goal ?? this.goal,
      goalKey: goalKey ?? this.goalKey,
      chatText: chatText ?? this.chatText,
      note: note ?? this.note,
      screenshotNames: screenshotNames ?? this.screenshotNames,
      screenshots: screenshots ?? this.screenshots,
      selectedProfile: selectedProfile ?? this.selectedProfile,
    );
  }
}

class PrecheckDraft {
  const PrecheckDraft({
    this.relationType,
    this.relationLabel,
    this.relationDetails = const [],
    this.draftMessage,
    this.optionalContextText,
    this.selectedProfile,
  });

  final String? relationType;
  final String? relationLabel;
  final List<String> relationDetails;
  final String? draftMessage;
  final String? optionalContextText;
  final RelationshipProfile? selectedProfile;

  PrecheckDraft copyWith({
    String? relationType,
    String? relationLabel,
    List<String>? relationDetails,
    String? draftMessage,
    String? optionalContextText,
    RelationshipProfile? selectedProfile,
  }) {
    return PrecheckDraft(
      relationType: relationType ?? this.relationType,
      relationLabel: relationLabel ?? this.relationLabel,
      relationDetails: relationDetails ?? this.relationDetails,
      draftMessage: draftMessage ?? this.draftMessage,
      optionalContextText: optionalContextText ?? this.optionalContextText,
      selectedProfile: selectedProfile ?? this.selectedProfile,
    );
  }
}

class ConsultationResult {
  const ConsultationResult({
    required this.sendTimingLabel,
    required this.sendTimingReason,
    required this.situationSummary,
    required this.partnerFeelingEstimate,
    required this.heardAsInterpretations,
    required this.avoidPhrases,
    required this.replyOptions,
    required this.nextActions,
    required this.preSendCautions,
  });

  final String sendTimingLabel;
  final String sendTimingReason;
  final String situationSummary;
  final String partnerFeelingEstimate;
  final List<String> heardAsInterpretations;
  final List<String> avoidPhrases;
  final List<ReplyOption> replyOptions;
  final List<String> nextActions;
  final List<String> preSendCautions;

  factory ConsultationResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final sendTiming =
        data['send_timing_recommendation'] as Map<String, dynamic>;
    final replyOptionsRaw = data['reply_options'] as List<dynamic>;

    return ConsultationResult(
      sendTimingLabel: sendTiming['label'] as String,
      sendTimingReason: sendTiming['reason'] as String,
      situationSummary: data['situation_summary'] as String,
      partnerFeelingEstimate: data['partner_feeling_estimate'] as String,
      heardAsInterpretations:
          ((data['heard_as_interpretations'] as List?) ?? const [])
              .whereType<String>()
              .toList(),
      avoidPhrases: ((data['avoid_phrases'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      replyOptions: replyOptionsRaw
          .map(
            (item) => ReplyOption(
              title: item['title'] as String,
              body: item['body'] as String,
            ),
          )
          .toList(),
      nextActions: (data['next_actions'] as List<dynamic>).cast<String>(),
      preSendCautions: (data['pre_send_cautions'] as List<dynamic>)
          .cast<String>(),
    );
  }
}

class PrecheckResult {
  const PrecheckResult({
    required this.label,
    required this.reason,
    required this.riskPoints,
    required this.heardAsInterpretations,
    required this.avoidPhrases,
    required this.softenedMessage,
    required this.revisedMessageOptions,
    required this.suggestConsultMode,
  });

  final String label;
  final String reason;
  final List<String> riskPoints;
  final List<String> heardAsInterpretations;
  final List<String> avoidPhrases;
  final String softenedMessage;
  final List<String> revisedMessageOptions;
  final bool suggestConsultMode;

  factory PrecheckResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final safeToSend = data['is_safe_to_send'] as Map<String, dynamic>;

    return PrecheckResult(
      label: safeToSend['label'] as String,
      reason: safeToSend['reason'] as String,
      riskPoints: (data['risk_points'] as List<dynamic>).cast<String>(),
      heardAsInterpretations:
          ((data['heard_as_interpretations'] as List?) ?? const [])
              .whereType<String>()
              .toList(),
      avoidPhrases: ((data['avoid_phrases'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      softenedMessage: data['softened_message'] as String,
      revisedMessageOptions: (data['revised_message_options'] as List<dynamic>)
          .cast<String>(),
      suggestConsultMode: data['suggest_consult_mode'] as bool,
    );
  }
}

class SavedResultItem {
  const SavedResultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.bestText,
    required this.createdAt,
    this.profileId,
    this.profileName,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String bestText;
  final String createdAt;
  final String? profileId;
  final String? profileName;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'bestText': bestText,
      'createdAt': createdAt,
      'profileId': profileId,
      'profileName': profileName,
    };
  }

  factory SavedResultItem.fromMap(Map<String, dynamic> map) {
    return SavedResultItem(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String,
      bestText: map['bestText'] as String,
      createdAt: map['createdAt'] as String,
      profileId: map['profileId'] as String?,
      profileName: map['profileName'] as String?,
    );
  }
}

List<RelationshipProfile> _profilesAvailableForCurrentPlan(
  List<RelationshipProfile> profiles,
) {
  final maxProfiles = PlanLimits.profilesForPlan(
    GoMenPlanStorage.notifier.value,
  );
  if (maxProfiles <= 0) return const <RelationshipProfile>[];
  if (profiles.length <= maxProfiles) return profiles;
  return profiles.take(maxProfiles).toList();
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.profile,
    required this.profiles,
    required this.profileItems,
    required this.allItems,
  });

  final RelationshipProfile? profile;
  final List<RelationshipProfile> profiles;
  final List<SavedResultItem> profileItems;
  final List<SavedResultItem> allItems;
}

class SavedResultsViewData {
  const SavedResultsViewData({
    required this.activeProfile,
    required this.items,
  });

  final RelationshipProfile? activeProfile;
  final List<SavedResultItem> items;
}

class DailyUsageStatus {
  const DailyUsageStatus({required this.dateKey, required this.usedCount});

  int get dailyLimit =>
      GoMenPlanStorage.isProSync ? 999999 : PlanLimits.freeDailyUses;

  final String dateKey;
  final int usedCount;

  int get remainingCount {
    final remaining = dailyLimit - usedCount;
    return remaining < 0 ? 0 : remaining;
  }
}

class DailyUsageStorage {
  static const _dateKey = 'go_men_daily_usage_date';
  static const _countKey = 'go_men_daily_usage_count';

  static String _todayKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static Future<DailyUsageStatus> loadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final storedDate = prefs.getString(_dateKey);
    final storedCount = prefs.getInt(_countKey) ?? 0;

    if (storedDate != today) {
      await prefs.setString(_dateKey, today);
      await prefs.setInt(_countKey, 0);
      return DailyUsageStatus(dateKey: today, usedCount: 0);
    }

    return DailyUsageStatus(dateKey: today, usedCount: storedCount);
  }

  static Future<bool> canUseAi() async {
    final status = await loadStatus();
    return status.remainingCount > 0;
  }

  static Future<void> recordSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final status = await loadStatus();
    await prefs.setString(_dateKey, status.dateKey);
    await prefs.setInt(_countKey, status.usedCount + 1);
  }
}

class ProfileStorage {
  static const _legacyKey = 'go_men_relationship_profile';
  static const _listKey = 'go_men_relationship_profiles';
  static const _activeIdKey = 'go_men_active_profile_id';

  static Future<List<RelationshipProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final profiles = decoded
            .map(
              (item) =>
                  RelationshipProfile.fromMap(item as Map<String, dynamic>),
            )
            .toList();

        if (profiles.isNotEmpty) {
          await _normalizeActiveProfileId(prefs, profiles);
        }
        return profiles;
      } catch (_) {}
    }

    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(legacyRaw) as Map<String, dynamic>;
      final profile = RelationshipProfile.fromMap(decoded);
      final profiles = [profile];

      await prefs.setString(
        _listKey,
        jsonEncode(profiles.map((e) => e.toMap()).toList()),
      );
      await prefs.setString(_activeIdKey, profile.id);

      return profiles;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _normalizeActiveProfileId(
    SharedPreferences prefs,
    List<RelationshipProfile> profiles,
  ) async {
    final activeId = prefs.getString(_activeIdKey);
    final resolvedId = profiles.any((item) => item.id == activeId)
        ? activeId
        : profiles.first.id;

    if (resolvedId != null) {
      await prefs.setString(_activeIdKey, resolvedId);
    }
  }

  static Future<String?> loadActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdKey);
  }

  static Future<void> setActiveProfileId(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();

    if (profileId == null || profileId.isEmpty) {
      await prefs.remove(_activeIdKey);
      return;
    }

    await prefs.setString(_activeIdKey, profileId);
  }

  static Future<RelationshipProfile?> loadProfile() async {
    final profiles = await loadProfiles();
    if (profiles.isEmpty) {
      return null;
    }

    final activeId = await loadActiveProfileId();
    for (final profile in profiles) {
      if (profile.id == activeId) {
        return profile;
      }
    }

    return profiles.first;
  }

  static Future<void> saveProfiles(List<RelationshipProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _listKey,
      jsonEncode(profiles.map((e) => e.toMap()).toList()),
    );

    if (profiles.isEmpty) {
      await prefs.remove(_activeIdKey);
    } else {
      await _normalizeActiveProfileId(prefs, profiles);
    }
  }

  static Future<void> saveProfile(RelationshipProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((item) => item.id == profile.id);

    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.insert(0, profile);
    }

    await saveProfiles(profiles);
    await setActiveProfileId(profile.id);
  }

  static Future<void> deleteProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await loadProfiles();
    profiles.removeWhere((item) => item.id == profileId);

    await prefs.setString(
      _listKey,
      jsonEncode(profiles.map((e) => e.toMap()).toList()),
    );

    final activeId = prefs.getString(_activeIdKey);
    if (profiles.isEmpty) {
      await prefs.remove(_activeIdKey);
    } else if (activeId == profileId) {
      await prefs.setString(_activeIdKey, profiles.first.id);
    }
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey);
    await prefs.remove(_listKey);
    await prefs.remove(_activeIdKey);
  }
}

class LocalHistoryStorage {
  static const _key = 'go_men_saved_results';

  static int get maxItems =>
      PlanLimits.savedResultsForPlan(GoMenPlanStorage.notifier.value);

  static Future<int> _maxItems() async {
    final plan = await GoMenPlanStorage.loadPlan();
    return PlanLimits.savedResultsForPlan(plan);
  }

  static Future<List<SavedResultItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => SavedResultItem.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveItem(SavedResultItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadItems();
    final updated = [item, ...current];
    final maxItems = await _maxItems();
    final trimmed = updated.take(maxItems).toList();

    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toMap()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<List<SavedResultItem>> loadItemsForProfile(
    String profileId,
  ) async {
    final all = await loadItems();
    return all.where((item) => item.profileId == profileId).toList();
  }

  static Future<String?> buildRecentPatternSummary(String profileId) async {
    final items = await loadItemsForProfile(profileId);
    if (items.isEmpty) return null;

    final recent = items.take(8).toList();
    final titles = uniquePreserveOrder(
      recent
          .map((item) => item.title.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
    final subtitles = uniquePreserveOrder(
      recent
          .map((item) => item.subtitle.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );

    final buffer = StringBuffer();
    buffer.writeln('この相手に関する直近相談要約:');
    buffer.writeln('件数: ${recent.length}件');
    if (titles.isNotEmpty) {
      buffer.writeln('繰り返し出やすい相談テーマ: ${titles.take(5).join(' / ')}');
    }
    if (subtitles.isNotEmpty) {
      buffer.writeln('よく出る不安・論点: ${subtitles.take(5).join(' / ')}');
    }
    buffer.writeln('直近の相談一覧:');
    for (final item in recent) {
      buffer.writeln('・${item.title}: ${item.subtitle}');
    }

    final summary = buffer.toString().trim();
    return summary.isEmpty ? null : summary;
  }
}

class ThemeQuestion {
  const ThemeQuestion({required this.title, required this.options});

  final String title;
  final List<String> options;
}

class FlowChoice {
  final String value;
  final String label;

  const FlowChoice({required this.value, required this.label});
}

class FlowQuestionConfig {
  final String id;
  final String title;
  final List<FlowChoice> options;

  const FlowQuestionConfig({
    required this.id,
    required this.title,
    required this.options,
  });
}

class ThemeFlowConfig {
  final String relationType;
  final String theme;
  final List<FlowQuestionConfig> detailQuestions;
  final String statusTitle;
  final String statusSubtitle;
  final List<FlowChoice> statusOptions;
  final String goalTitle;
  final String goalSubtitle;
  final List<FlowChoice> goalOptions;

  const ThemeFlowConfig({
    required this.relationType,
    required this.theme,
    required this.detailQuestions,
    required this.statusTitle,
    required this.statusSubtitle,
    required this.statusOptions,
    required this.goalTitle,
    required this.goalSubtitle,
    required this.goalOptions,
  });
}

final Map<String, ThemeFlowConfig> _kCoupleThemeFlowConfigs = {
  '連絡頻度': ThemeFlowConfig(
    relationType: 'couple',
    theme: '連絡頻度',
    detailQuestions: [
      FlowQuestionConfig(
        id: 'contact_gap_type',
        title: '連絡のどこでズレを感じますか？',
        options: [
          FlowChoice(value: 'unread_continues', label: '未読が続いている'),
          FlowChoice(value: 'read_no_reply', label: '既読のあと返ってこない'),
          FlowChoice(value: 'reply_temperature_gap', label: '返信は来るが温度差がある'),
          FlowChoice(value: 'self_overmessaged', label: 'こちらが送りすぎた感じがある'),
          FlowChoice(value: 'partner_too_intense', label: '相手からの連絡が重く感じる'),
        ],
      ),
      FlowQuestionConfig(
        id: 'contact_gap_pattern',
        title: 'そのズレはどんな出方をしていますか？',
        options: [
          FlowChoice(value: 'sudden_change', label: '急に変わった'),
          FlowChoice(value: 'gradual_pattern', label: '前から少しずつあった'),
          FlowChoice(value: 'after_conflict', label: 'ケンカやすれ違いのあとから'),
          FlowChoice(value: 'possibly_busy', label: '相手が忙しいだけの可能性もある'),
          FlowChoice(value: 'reason_unclear', label: '理由がよく見えない'),
        ],
      ),
    ],
    statusTitle: '連絡の状態は今どれに近いですか？',
    statusSubtitle: '連絡や返信のズレが今どの段階かに近いものを選んでください',
    statusOptions: [
      FlowChoice(value: 'latent', label: 'まだ問題として言葉にしていない'),
      FlowChoice(value: 'signal', label: '少し違和感が出ている'),
      FlowChoice(value: 'ongoing', label: '返信や温度差のズレが続いている'),
      FlowChoice(value: 'conflict', label: '連絡のことで実際にぶつかった'),
      FlowChoice(value: 'frozen', label: '連絡が止まっている / 関係が冷え気味'),
    ],
    goalTitle: '今回はどうしたいですか？',
    goalSubtitle: '今いちばん近い目的を選んでください',
    goalOptions: [
      FlowChoice(value: 'clarify', label: '相手の状況や認識を確認したい'),
      FlowChoice(value: 'express', label: '不安や本音を落ち着いて伝えたい'),
      FlowChoice(value: 'align', label: '連絡頻度や期待値をすり合わせたい'),
      FlowChoice(value: 'pause', label: '今日は送らず少し置きたい'),
      FlowChoice(value: 'repair', label: 'こじれた空気を修復したい'),
      FlowChoice(value: 'boundary', label: '連絡の線引きを決めたい'),
    ],
  ),

  '言い方がきつい': ThemeFlowConfig(
    relationType: 'couple',
    theme: '言い方がきつい',
    detailQuestions: [
      FlowQuestionConfig(
        id: 'tone_conflict_side',
        title: '今回はどちら側に近いですか？',
        options: [
          FlowChoice(value: 'hurt_by_partner_tone', label: '相手の言い方で傷ついた'),
          FlowChoice(value: 'i_spoke_harshly', label: '自分がきつく言ってしまった'),
          FlowChoice(value: 'both_escalated', label: 'お互い強くなってしまった'),
          FlowChoice(value: 'text_misread_harsh', label: '文字だけだと強く見えている'),
        ],
      ),
      FlowQuestionConfig(
        id: 'tone_conflict_core',
        title: 'いちばん引っかかっているのはどこですか？',
        options: [
          FlowChoice(value: 'harsh_wording', label: '言い方そのものがきつかった'),
          FlowChoice(value: 'felt_denied', label: '否定された感じがした'),
          FlowChoice(value: 'felt_looked_down_on', label: '見下された感じがした'),
          FlowChoice(value: 'felt_brushed_off', label: '冗談っぽく流された'),
          FlowChoice(value: 'repeated_pattern', label: 'こういうことが何度もある'),
        ],
      ),
    ],
    statusTitle: '今の空気感はどれに近いですか？',
    statusSubtitle: '言い方による傷つきや気まずさが今どの段階かを選んでください',
    statusOptions: [
      FlowChoice(value: 'latent', label: 'まだ表には出していない'),
      FlowChoice(value: 'signal', label: '言い方が少し引っかかっている'),
      FlowChoice(value: 'ongoing', label: '傷つきや気まずさが続いている'),
      FlowChoice(value: 'conflict', label: '言い返した / 言い合いになった'),
      FlowChoice(value: 'frozen', label: '会話が冷えたり止まり気味'),
    ],
    goalTitle: '今回はどうしたいですか？',
    goalSubtitle: '今いちばん近い目的を選んでください',
    goalOptions: [
      FlowChoice(value: 'repair', label: '謝りたい / 関係を修復したい'),
      FlowChoice(value: 'express', label: '傷ついたことを落ち着いて伝えたい'),
      FlowChoice(value: 'align', label: '言い方や受け取り方をすり合わせたい'),
      FlowChoice(value: 'boundary', label: 'その言い方は嫌だと線を引きたい'),
      FlowChoice(value: 'clarify', label: '本当にどういう意図だったか確認したい'),
      FlowChoice(value: 'pause', label: '今日は深追いせず少し置きたい'),
    ],
  ),

  '約束': ThemeFlowConfig(
    relationType: 'couple',
    theme: '約束',
    detailQuestions: [
      FlowQuestionConfig(
        id: 'promise_topic',
        title: '何についての約束ですか？',
        options: [
          FlowChoice(value: 'time_or_contact', label: '時間や連絡'),
          FlowChoice(value: 'meeting_plan', label: '会う予定'),
          FlowChoice(value: 'money_or_share', label: 'お金や分担'),
          FlowChoice(value: 'future_or_important_talk', label: '将来や大事な話'),
          FlowChoice(value: 'small_promises_stack', label: '小さな約束の積み重ね'),
        ],
      ),
      FlowQuestionConfig(
        id: 'promise_gap_side',
        title: '今回のズレはどちらに近いですか？',
        options: [
          FlowChoice(value: 'partner_broke', label: '相手が守らなかった'),
          FlowChoice(value: 'i_broke', label: '自分が守れなかった'),
          FlowChoice(value: 'recognition_gap', label: 'お互いの認識がズレていた'),
          FlowChoice(value: 'promise_was_vague', label: 'そもそも約束自体が曖昧だった'),
        ],
      ),
      FlowQuestionConfig(
        id: 'promise_weight',
        title: '今回の重さはどのくらいですか？',
        options: [
          FlowChoice(value: 'one_time', label: '単発のこと'),
          FlowChoice(value: 'repeated', label: '何度か続いている'),
          FlowChoice(value: 'trust_level', label: '信頼に関わる感じがある'),
          FlowChoice(value: 'mixed_with_other_issues', label: '他の不満も重なっている'),
        ],
      ),
    ],
    statusTitle: '約束の状態は今どれに近いですか？',
    statusSubtitle: '約束のズレが今どの段階まで進んでいるかを選んでください',
    statusOptions: [
      FlowChoice(value: 'latent', label: 'まだ言葉にはしていない'),
      FlowChoice(value: 'signal', label: '小さく違和感が出ている'),
      FlowChoice(value: 'ongoing', label: '約束への引っかかりが続いている'),
      FlowChoice(value: 'conflict', label: '約束のことで実際にぶつかった'),
      FlowChoice(value: 'frozen', label: 'その話題が止まっている / 信頼が揺れている'),
    ],
    goalTitle: '今回はどうしたいですか？',
    goalSubtitle: '今いちばん近い目的を選んでください',
    goalOptions: [
      FlowChoice(value: 'clarify', label: '何が約束だったのか確認したい'),
      FlowChoice(value: 'align', label: '約束や期待値をすり合わせたい'),
      FlowChoice(value: 'express', label: '失望や引っかかりを伝えたい'),
      FlowChoice(value: 'repair', label: 'こじれた空気を修復したい'),
      FlowChoice(value: 'boundary', label: 'ルールや約束の線を引きたい'),
      FlowChoice(value: 'pause', label: '今日は深追いせず少し置きたい'),
    ],
  ),

  'お金': ThemeFlowConfig(
    relationType: 'couple',
    theme: 'お金',
    detailQuestions: [
      FlowQuestionConfig(
        id: 'money_topic',
        title: 'どのお金の話ですか？',
        options: [
          FlowChoice(value: 'date_or_living_share', label: 'デート代や生活費の負担'),
          FlowChoice(value: 'reimbursement', label: '立替・返金'),
          FlowChoice(value: 'gift_or_celebration', label: 'プレゼントやお祝い'),
          FlowChoice(value: 'future_money_values', label: '将来のお金の感覚'),
          FlowChoice(value: 'other_money_issue', label: 'その他のお金の話'),
        ],
      ),
      FlowQuestionConfig(
        id: 'money_block',
        title: 'いちばん詰まっているのはどこですか？',
        options: [
          FlowChoice(value: 'facts_unclear', label: '金額や事実が曖昧'),
          FlowChoice(value: 'hard_to_request', label: '催促しづらい'),
          FlowChoice(value: 'fairness_pain', label: '不公平感が強い'),
          FlowChoice(value: 'hurt_by_treatment', label: '扱われ方に傷ついている'),
          FlowChoice(value: 'future_anxiety', label: '将来まで不安になる'),
        ],
      ),
    ],
    statusTitle: 'お金まわりの状態は今どれに近いですか？',
    statusSubtitle: 'お金の話が今どの段階かに近いものを選んでください',
    statusOptions: [
      FlowChoice(value: 'latent', label: 'まだ切り出していない'),
      FlowChoice(value: 'signal', label: '少し気になっている'),
      FlowChoice(value: 'ongoing', label: 'もやつきや不公平感が続いている'),
      FlowChoice(value: 'conflict', label: 'お金のことで実際にぶつかった'),
      FlowChoice(value: 'frozen', label: '話が止まっている / 触れにくくなっている'),
    ],
    goalTitle: '今回はどうしたいですか？',
    goalSubtitle: '今いちばん近い目的を選んでください',
    goalOptions: [
      FlowChoice(value: 'clarify', label: '金額や事実を先に整理したい'),
      FlowChoice(value: 'align', label: '負担感や価値観をすり合わせたい'),
      FlowChoice(value: 'express', label: 'モヤモヤや不公平感を伝えたい'),
      FlowChoice(value: 'boundary', label: '負担やルールの線を引きたい'),
      FlowChoice(value: 'repair', label: 'お金で悪くなった空気を修復したい'),
      FlowChoice(value: 'pause', label: '今日は切り出さず少し置きたい'),
    ],
  ),

  '距離感': ThemeFlowConfig(
    relationType: 'couple',
    theme: '距離感',
    detailQuestions: [
      FlowQuestionConfig(
        id: 'distance_gap_type',
        title: 'どちら側のズレに近いですか？',
        options: [
          FlowChoice(value: 'partner_feels_distant', label: '相手が遠く感じる'),
          FlowChoice(value: 'partner_too_close', label: '相手が近すぎる'),
          FlowChoice(value: 'i_need_space', label: '自分が少し距離を置きたい'),
          FlowChoice(value: 'meeting_frequency_gap', label: '会いたい頻度が合わない'),
          FlowChoice(value: 'alone_time_gap', label: '一人時間の感覚が合わない'),
        ],
      ),
      FlowQuestionConfig(
        id: 'distance_gap_pattern',
        title: 'そのズレはどんな形で出ていますか？',
        options: [
          FlowChoice(value: 'sudden_change', label: '急に変わった'),
          FlowChoice(value: 'gradual_pattern', label: '前から少しずつあった'),
          FlowChoice(value: 'after_conflict', label: 'ケンカやすれ違いのあとから'),
          FlowChoice(value: 'no_bad_intent', label: '相手に悪気はなさそう'),
          FlowChoice(
            value: 'my_own_needs_unclear',
            label: '自分でもどこまで求めていいかわからない',
          ),
        ],
      ),
    ],
    statusTitle: '距離感の状態は今どれに近いですか？',
    statusSubtitle: '距離感のズレが今どの段階かに近いものを選んでください',
    statusOptions: [
      FlowChoice(value: 'latent', label: 'まだ表には出していない'),
      FlowChoice(value: 'signal', label: '少し違和感が出ている'),
      FlowChoice(value: 'ongoing', label: '距離のズレや気まずさが続いている'),
      FlowChoice(value: 'conflict', label: '距離感のことで実際にぶつかった'),
      FlowChoice(value: 'frozen', label: '関係が冷えたり、よそよそしくなっている'),
    ],
    goalTitle: '今回はどうしたいですか？',
    goalSubtitle: '今いちばん近い目的を選んでください',
    goalOptions: [
      FlowChoice(value: 'align', label: '距離の取り方をすり合わせたい'),
      FlowChoice(value: 'express', label: '寂しさやしんどさを伝えたい'),
      FlowChoice(value: 'boundary', label: '関わり方の線を引きたい'),
      FlowChoice(value: 'pause', label: '今日は深追いせず少し置きたい'),
      FlowChoice(value: 'repair', label: '冷えた空気を修復したい'),
      FlowChoice(value: 'clarify', label: '相手の温度感や認識を確認したい'),
    ],
  ),
};

ThemeFlowConfig? _coupleCoreConfig(String theme) =>
    _kCoupleThemeFlowConfigs[theme];

List<String> _choiceLabels(List<FlowChoice> choices) =>
    choices.map((choice) => choice.label).toList(growable: false);

List<ThemeQuestion> _flowQuestionsFromConfig(ThemeFlowConfig config) => config
    .detailQuestions
    .map(
      (question) => ThemeQuestion(
        title: question.title,
        options: _choiceLabels(question.options),
      ),
    )
    .toList(growable: false);

String? _coupleCoreStatusTitle(String theme) =>
    _coupleCoreConfig(theme)?.statusTitle;

String? _coupleCoreGoalTitle(String theme) =>
    _coupleCoreConfig(theme)?.goalTitle;

String? _coupleCoreGoalSubtitle(String theme) =>
    _coupleCoreConfig(theme)?.goalSubtitle;

List<String>? _coupleCoreGoalOptions(String theme) {
  final config = _coupleCoreConfig(theme);
  if (config == null) return null;
  return _choiceLabels(config.goalOptions);
}

class ReplyOption {
  const ReplyOption({required this.title, required this.body});

  final String title;
  final String body;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<HomeDashboardData> _loadDashboard() async {
    final profile = await ProfileStorage.loadProfile();
    final profiles = await ProfileStorage.loadProfiles();
    final allItems = await LocalHistoryStorage.loadItems();
    final profileItems = profile == null
        ? <SavedResultItem>[]
        : allItems.where((item) => item.profileId == profile.id).toList();

    return HomeDashboardData(
      profile: profile,
      profiles: profiles,
      profileItems: profileItems,
      allItems: allItems,
    );
  }

  void _reloadDashboard() {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
  }

  Future<String?> _pickProfileIdOrNone({
    required String title,
    required List<RelationshipProfile> profiles,
    required String noneLabel,
    required String noneSubtitle,
  }) async {
    final availableProfiles = _profilesAvailableForCurrentPlan(profiles);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...availableProfiles.map(
                  (profile) => ListTile(
                    title: Text(profile.displayName),
                    subtitle: buildProfileTypeSummaryWidget(profile),
                    onTap: () => Navigator.of(context).pop(profile.id),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: Text(noneLabel),
                  subtitle: Text(noneSubtitle),
                  onTap: () => Navigator.of(context).pop('__without_profile__'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openConsultFlow(RelationshipProfile? activeProfile) async {
    final profiles = await ProfileStorage.loadProfiles();

    if (!mounted) return;

    if (profiles.isEmpty) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RelationTypeScreen()))
          .then((_) => _reloadDashboard());
      return;
    }

    final orderedProfiles = [...profiles];
    if (activeProfile != null) {
      orderedProfiles.sort((a, b) {
        if (a.id == activeProfile.id) return -1;
        if (b.id == activeProfile.id) return 1;
        return 0;
      });
    }

    final choiceId = await _pickProfileIdOrNone(
      title: '相談する相手を選んでください',
      profiles: orderedProfiles,
      noneLabel: 'プロフィールなしで相談する',
      noneSubtitle: '関係性をその場で入力して進みます',
    );

    if (!mounted || choiceId == null) return;

    if (choiceId == '__without_profile__') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RelationTypeScreen()))
          .then((_) => _reloadDashboard());
      return;
    }

    final picked = orderedProfiles.firstWhere(
      (profile) => profile.id == choiceId,
    );

    await ProfileStorage.setActiveProfileId(picked.id);

    if (!mounted) return;

    await Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: ConsultationDraft(
                relationType: picked.relationType,
                relationLabel: picked.relationSummaryLabel,
                relationDetails: List<String>.from(picked.relationDetails),
                selectedProfile: picked,
              ),
            ),
          ),
        )
        .then((_) => _reloadDashboard());
  }

  Future<void> _openPrecheckFlow(RelationshipProfile? activeProfile) async {
    final profiles = await ProfileStorage.loadProfiles();

    if (!mounted) return;

    if (profiles.isEmpty) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PrecheckInputScreen()))
          .then((_) => _reloadDashboard());
      return;
    }

    final orderedProfiles = [...profiles];
    if (activeProfile != null) {
      orderedProfiles.sort((a, b) {
        if (a.id == activeProfile.id) return -1;
        if (b.id == activeProfile.id) return 1;
        return 0;
      });
    }

    final choiceId = await _pickProfileIdOrNone(
      title: 'チェックしたい相手を選んでください',
      profiles: orderedProfiles,
      noneLabel: 'プロフィールなしでチェックする',
      noneSubtitle: '関係性をその場で入力して進みます',
    );

    if (!mounted || choiceId == null) return;

    if (choiceId == '__without_profile__') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PrecheckInputScreen()))
          .then((_) => _reloadDashboard());
      return;
    }

    final picked = orderedProfiles.firstWhere(
      (profile) => profile.id == choiceId,
    );

    await ProfileStorage.setActiveProfileId(picked.id);

    if (!mounted) return;

    await Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(initialProfile: picked),
          ),
        )
        .then((_) => _reloadDashboard());
  }

  void _showProfileDetail(RelationshipProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    profile.displayName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.relationSummaryLabel,
                    style: TextStyle(
                      fontSize: 16,
                      color: goMenMutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ProfileDetailItem(
                    label: '傷つきやすい言い方',
                    value: profile.sensitiveTo,
                  ),
                  _ProfileDetailItem(
                    label: '通りやすい伝え方',
                    value: profile.worksWellWith,
                  ),
                  _ProfileDetailItem(
                    label: '距離感の傾向',
                    value: profile.distancePreference,
                  ),
                  _ProfileDetailItem(
                    label: 'よく揉めるテーマ',
                    value: profile.commonConflicts,
                  ),
                  _ProfileDetailItem(
                    label: '避けたいワード',
                    value: profile.avoidWords,
                  ),
                  _ProfileDetailItem(label: '補足メモ', value: profile.notes),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(this.context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileEditScreen(profile: profile),
                            ),
                          )
                          .then((_) => _reloadDashboard());
                    },
                    child: Text('このプロフィールを編集する'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<HomeDashboardData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final data =
                snapshot.data ??
                const HomeDashboardData(
                  profile: null,
                  profiles: [],
                  profileItems: [],
                  allItems: [],
                );
            final profile = data.profile;
            final profileItems = data.profileItems;
            final allItems = data.allItems;
            final savedCount = allItems.length;
            final saveProgress = savedCount / LocalHistoryStorage.maxItems;
            final currentPlan = GoMenPlanStorage.notifier.value;
            final profileCount = data.profiles.length;
            final maxProfiles = PlanLimits.profilesForPlan(currentPlan);
            final profileProgress = maxProfiles <= 0
                ? 0.0
                : profileCount / maxProfiles;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                const SizedBox(height: 24),
                Text(
                  'Go-men',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '関係を壊さないための、次の一手を整える',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: goMenMutedTextColor(context),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsHubScreen(),
                            ),
                          )
                          .then((_) => _reloadDashboard());
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: Text('設定・ポリシー'),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '保存状況',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '保存件数',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: saveProgress.clamp(0.0, 1.0),
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$savedCount / ${LocalHistoryStorage.maxItems} 件',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'プロフィール件数',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: profileProgress.clamp(0.0, 1.0),
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$profileCount / $maxProfiles 件',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '関係性ごとの履歴を見ながら、やり取りを整理できます。',
                          style: TextStyle(
                            fontSize: 13,
                            color: goMenMutedTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (profile != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '使用中の関係性プロフィール',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            profile.displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...activeProfileTypeLines(profile).map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _showProfileDetail(profile),
                                  child: Text('詳しく見る'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SavedResultsScreen(
                                                  initialOnlyCurrentProfile:
                                                      true,
                                                ),
                                          ),
                                        )
                                        .then((_) => _reloadDashboard());
                                  },
                                  child: Text('この相手の履歴'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'この相手との最近の傾向',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            buildTrendHeadline(profileItems),
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                          if (profileItems.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...buildTrendBullets(profileItems).map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('・$item'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                ElevatedButton(
                  onPressed: () => _openConsultFlow(profile),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    profile != null ? '今すぐ相談する（プロフィール適用）' : '今すぐ相談する',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _openPrecheckFlow(profile),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    profile != null ? '送る前にチェックする（プロフィール適用）' : '送る前にチェックする',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    final selectedProfile = profile;

                    if (selectedProfile == null) {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileManagerScreen(),
                            ),
                          )
                          .then((_) => _reloadDashboard());
                      return;
                    }

                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CompatibilityScreen(profile: selectedProfile),
                          ),
                        )
                        .then((_) => _reloadDashboard());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    profile != null ? '相性を採点する' : 'プロフィールを設定して相性を採点',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const SavedResultsScreen(),
                          ),
                        )
                        .then((_) => _reloadDashboard());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text('保存した結果を見る', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileManagerScreen(),
                          ),
                        )
                        .then((_) => _reloadDashboard());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    '関係性プロフィールを選択・編集する',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '保存やプロフィールの詳細は設定から確認できます',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: goMenMutedTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'MVP v1.1',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 14),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileDetailItem extends StatelessWidget {
  const _ProfileDetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '未設定' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(displayValue, style: const TextStyle(fontSize: 16, height: 1.5)),
        ],
      ),
    );
  }
}

class _RelationDetailGroup {
  const _RelationDetailGroup({required this.title, required this.options});

  final String title;
  final List<String> options;
}

List<_RelationDetailGroup> _profileRelationDetailGroupsFor(
  String? relationType,
) {
  switch (relationType) {
    case 'couple':
      return const [
        _RelationDetailGroup(
          title: 'あなたについて',
          options: ['自分: 男性', '自分: 女性', '自分: 答えない'],
        ),
        _RelationDetailGroup(
          title: '相手について',
          options: ['相手: 男性', '相手: 女性', '相手: 答えない'],
        ),
      ];
    case 'friend':
      return const [
        _RelationDetailGroup(
          title: 'どんな友人ですか？',
          options: [
            '学校の友人',
            '職場の友人',
            '昔からの友人',
            '趣味・コミュニティの友人',
            'オンラインの友人',
            'その他の友人',
          ],
        ),
      ];
    case 'family':
    case 'parent_child':
    case 'family_parent_child':
    case 'family_sibling':
    case 'family_inlaw':
    case 'family_other':
      return const [
        _RelationDetailGroup(
          title: '相手は誰ですか？',
          options: [
            '母',
            '父',
            '娘',
            '息子',
            '姉',
            '兄',
            '妹',
            '弟',
            '義母',
            '義父',
            '義姉',
            '義兄',
            '義妹',
            '義弟',
            '祖母',
            '祖父',
            'その他の家族',
          ],
        ),
      ];
    default:
      return const [];
  }
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.profile});

  final RelationshipProfile? profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _displayNameController;
  late final TextEditingController _relationDetailsController;
  late final TextEditingController _sensitiveToController;
  late final TextEditingController _worksWellWithController;
  late final TextEditingController _distancePreferenceController;
  late final TextEditingController _commonConflictsController;
  late final TextEditingController _avoidWordsController;
  late final TextEditingController _notesController;

  late String _relationType;
  late String _selfStandardTypeId;
  late String _selfLoveTypeId;
  late String _partnerStandardTypeId;
  late Set<String> _selectedRelationDetails;
  late String _partnerLoveTypeId;

  bool get _isCouple => _relationType == 'couple';

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _displayNameController = TextEditingController(
      text: profile?.displayName ?? '',
    );
    _relationDetailsController = TextEditingController(
      text: (profile?.relationDetails ?? const <String>[]).join('\n'),
    );
    _sensitiveToController = TextEditingController(
      text: profile?.sensitiveTo ?? '',
    );
    _worksWellWithController = TextEditingController(
      text: profile?.worksWellWith ?? '',
    );
    _distancePreferenceController = TextEditingController(
      text: profile?.distancePreference ?? '',
    );
    _commonConflictsController = TextEditingController(
      text: profile?.commonConflicts ?? '',
    );
    _avoidWordsController = TextEditingController(
      text: profile?.avoidWords ?? '',
    );
    _notesController = TextEditingController(text: profile?.notes ?? '');

    _relationType = (profile?.relationType ?? 'couple').trim();
    _selfStandardTypeId = (profile?.selfStandardTypeId ?? 'unknown').trim();
    _selfLoveTypeId = (profile?.selfLoveTypeId ?? 'unknown').trim();
    _partnerStandardTypeId = (profile?.partnerStandardTypeId ?? 'unknown')
        .trim();
    _selectedRelationDetails = _parseRelationDetails(
      _relationDetailsController.text,
    ).toSet();
    _partnerLoveTypeId = (profile?.partnerLoveTypeId ?? 'unknown').trim();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _relationDetailsController.dispose();
    _sensitiveToController.dispose();
    _worksWellWithController.dispose();
    _distancePreferenceController.dispose();
    _commonConflictsController.dispose();
    _avoidWordsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<String> _parseRelationDetails(String raw) {
    return raw
        .split(RegExp(r'[\n、,，/／]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _normalizeTypeId(String? value, List<TypeOption> options) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return 'unknown';
    for (final option in options) {
      if (option.key == normalized) {
        return normalized;
      }
    }
    return 'unknown';
  }

  Set<String> _availableRelationDetailOptionSet() {
    return _profileRelationDetailGroupsFor(_relationType)
        .expand((group) => group.options)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  void _syncRelationDetailsControllerPreservingFreeText() {
    final allowed = _availableRelationDetailOptionSet();
    final manual = _parseRelationDetails(
      _relationDetailsController.text,
    ).where((item) => !allowed.contains(item)).toList();
    _relationDetailsController.text = [
      ..._selectedRelationDetails,
      ...manual,
    ].join('\n');
  }

  Widget _buildRelationDetailSelector() {
    final groups = _profileRelationDetailGroupsFor(_relationType);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('関係性の詳細', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...groups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: group.options.map((option) {
                        final selected = _selectedRelationDetails.contains(
                          option,
                        );
                        return FilterChip(
                          label: Text(option),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _selectedRelationDetails.add(option);
                              } else {
                                _selectedRelationDetails.remove(option);
                              }
                              _syncRelationDetailsControllerPreservingFreeText();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeDropdownCard({
    required String title,
    required String currentValue,
    required List<TypeOption> options,
    required ValueChanged<String> onChanged,
    String? subtitle,
  }) {
    final normalizedValue = _normalizeTypeId(currentValue, options);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: goMenMutedTextColor(context),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: normalizedValue,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String>(
                  value: 'unknown',
                  child: Text('不明 / 無回答'),
                ),
                ...options.map(
                  (option) => DropdownMenuItem<String>(
                    value: option.key,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: (value) {
                onChanged(
                  (value ?? 'unknown').trim().isEmpty ? 'unknown' : value!,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = RelationshipProfile(
      id:
          widget.profile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      displayName: _displayNameController.text.trim(),
      relationType: _relationType,
      relationDetails: _parseRelationDetails(_relationDetailsController.text),
      sensitiveTo: _sensitiveToController.text.trim(),
      worksWellWith: _worksWellWithController.text.trim(),
      distancePreference: _distancePreferenceController.text.trim(),
      commonConflicts: _commonConflictsController.text.trim(),
      avoidWords: _avoidWordsController.text.trim(),
      notes: _notesController.text.trim(),
      createdAt: widget.profile?.createdAt ?? DateTime.now().toIso8601String(),
      selfStandardTypeId: _normalizeTypeId(
        _selfStandardTypeId,
        standard16TypeOptions,
      ),
      selfLoveTypeId: _isCouple
          ? _normalizeTypeId(_selfLoveTypeId, love16TypeOptions)
          : 'unknown',
      partnerStandardTypeId: _normalizeTypeId(
        _partnerStandardTypeId,
        standard16TypeOptions,
      ),
      partnerLoveTypeId: _isCouple
          ? _normalizeTypeId(_partnerLoveTypeId, love16TypeOptions)
          : 'unknown',
    );

    await ProfileStorage.saveProfile(profile);
    await ProfileStorage.setActiveProfileId(profile.id);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final relationOptions = const <MapEntry<String, String>>[
      MapEntry('couple', '恋人・パートナー'),
      MapEntry('friend', '友人'),
      MapEntry('family', '家族'),
      MapEntry('other', 'その他'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'プロフィール設定' : 'プロフィール編集'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: '相手の名前や呼び名',
                  hintText: '例: さや / 先輩 / 母 など',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return '相手の名前や呼び名を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _relationType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '関係性',
                  border: OutlineInputBorder(),
                ),
                items: relationOptions
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _relationType = value;
                    if (!_isCouple) {
                      _selfLoveTypeId = 'unknown';
                      _partnerLoveTypeId = 'unknown';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildRelationDetailSelector(),
              const SizedBox(height: 16),
              const Text(
                '相手の傾向メモ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _sensitiveToController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '傷つきやすい言い方',
                  hintText: '例: 強い断定、責める言い方、無視されたと感じる反応',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _worksWellWithController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '通りやすい伝え方',
                  hintText: '例: まず共感してから、結論をやわらかく伝える',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _distancePreferenceController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '距離感の傾向',
                  hintText: '例: こまめな連絡がほしい / 一人時間も大事',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commonConflictsController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'よく揉めるテーマ',
                  hintText: '例: 返信速度 / 言い方 / 約束の優先順位',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _avoidWordsController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '避けたいワード',
                  hintText: '例: どうせ / 普通は / 面倒くさい',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '補足メモ（任意）',
                  hintText: '最近のすれ違い、背景事情、気をつけたいこと',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              _buildTypeDropdownCard(
                title: '自分の通常16タイプ',
                subtitle: 'ふだんの考え方・対人傾向として使います。',
                currentValue: _selfStandardTypeId,
                options: standard16TypeOptions,
                onChanged: (value) {
                  setState(() {
                    _selfStandardTypeId = value;
                  });
                },
              ),
              if (_isCouple)
                _buildTypeDropdownCard(
                  title: '自分の恋愛16タイプ',
                  subtitle: '恋愛関係のときの傾向として使います。',
                  currentValue: _selfLoveTypeId,
                  options: love16TypeOptions,
                  onChanged: (value) {
                    setState(() {
                      _selfLoveTypeId = value;
                    });
                  },
                ),
              _buildTypeDropdownCard(
                title: '相手の通常16タイプ',
                subtitle: '相手のふだんの傾向として使います。',
                currentValue: _partnerStandardTypeId,
                options: standard16TypeOptions,
                onChanged: (value) {
                  setState(() {
                    _partnerStandardTypeId = value;
                  });
                },
              ),
              if (_isCouple)
                _buildTypeDropdownCard(
                  title: '相手の恋愛16タイプ',
                  subtitle: '相手の恋愛場面での傾向として使います。',
                  currentValue: _partnerLoveTypeId,
                  options: love16TypeOptions,
                  onChanged: (value) {
                    setState(() {
                      _partnerLoveTypeId = value;
                    });
                  },
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _save,
                child: Text(widget.profile == null ? 'プロフィールを保存' : '変更を保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RelationTypeScreen extends StatelessWidget {
  const RelationTypeScreen({super.key});

  void _selectRelation(
    BuildContext context,
    String relationType,
    String label,
  ) {
    late final Widget nextScreen;

    switch (relationType) {
      case 'couple':
        nextScreen = CoupleSelfGenderScreen(
          draft: ConsultationDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
          ),
        );
        break;
      case 'friend':
        nextScreen = FriendContextScreen(
          draft: ConsultationDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
          ),
        );
        break;
      case 'family':
        nextScreen = FamilyTypeScreen(
          draft: ConsultationDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
          ),
        );
        break;
      case 'other':
      default:
        nextScreen = ThemeSelectionScreen(
          draft: ConsultationDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
          ),
        );
        break;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    return ConsultationScaffold(
      currentStep: 1,
      title: '相手との関係を教えてください',
      subtitle: '受け取り方や提案の仕方が変わるため、最初に関係性を選んでください',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: () => _selectRelation(context, 'couple', '恋人・パートナー'),
            style: elevatedChoiceStyle,
            child: Text('恋人・パートナー', style: choiceTextStyle),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _selectRelation(context, 'friend', '友人'),
            style: elevatedChoiceStyle,
            child: Text('友人', style: choiceTextStyle),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _selectRelation(context, 'family', '家族'),
            style: elevatedChoiceStyle,
            child: Text('家族', style: choiceTextStyle),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _selectRelation(context, 'other', 'その他'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: Text('その他', style: choiceTextStyle),
          ),
        ],
      ),
    );
  }
}

class RelationSingleChoiceScreen extends StatelessWidget {
  const RelationSingleChoiceScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.question,
    required this.options,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final String question;
  final List<String> options;
  final void Function(BuildContext context, String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return ConsultationScaffold(
      currentStep: 1,
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            question,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...options.expand(
            (option) => [
              ElevatedButton(
                onPressed: () => onSelected(context, option),
                style: elevatedChoiceStyle,
                child: Text(option, style: choiceTextStyle),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ],
      ),
    );
  }
}

class CoupleSelfGenderScreen extends StatelessWidget {
  const CoupleSelfGenderScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'ここが細かいほど、返信候補がより自然になります',
      question: 'あなたは？',
      options: const ['男性', '女性', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CouplePartnerGenderScreen(
              draft: draft.copyWith(relationDetails: ['自分: $value']),
            ),
          ),
        );
      },
    );
  }
}

class CouplePartnerGenderScreen extends StatelessWidget {
  const CouplePartnerGenderScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'ここが細かいほど、返信候補がより自然になります',
      question: '相手は？',
      options: const ['男性', '女性', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FriendContextScreen extends StatelessWidget {
  const FriendContextScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '友人の種類で、自然な距離感がかなり変わります',
      question: 'どこでの友人ですか？',
      options: const ['学校', '職場', '地元', '趣味コミュニティ', 'そのほか'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(relationDetails: ['$valueの友人']),
            ),
          ),
        );
      },
    );
  }
}

class FamilyTypeScreen extends StatelessWidget {
  const FamilyTypeScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '家族の中の関係で、伝わり方がかなり変わります',
      question: '家族の中ではどの関係ですか？',
      options: const ['親子', '兄弟姉妹', '義家族', 'そのほか'],
      onSelected: (context, value) {
        if (value == '親子') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FamilyParentRoleScreen(
                draft: draft.copyWith(
                  relationType: 'family_parent_child',
                  relationLabel: '家族 / 親子',
                  relationDetails: ['親子'],
                ),
              ),
            ),
          );
          return;
        }

        if (value == '兄弟姉妹') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FamilySiblingScreen(
                draft: draft.copyWith(
                  relationType: 'family_sibling',
                  relationLabel: '家族 / 兄弟姉妹',
                  relationDetails: ['兄弟姉妹'],
                ),
              ),
            ),
          );
          return;
        }

        if (value == '義家族') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FamilyInlawScreen(
                draft: draft.copyWith(
                  relationType: 'family_inlaw',
                  relationLabel: '家族 / 義家族',
                  relationDetails: ['義家族'],
                ),
              ),
            ),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(
                relationType: 'family_other',
                relationLabel: '家族 / その他',
                relationDetails: ['家族 / その他'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FamilyParentRoleScreen extends StatelessWidget {
  const FamilyParentRoleScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '親子でも立場で返し方が変わります',
      question: 'あなたはどちらですか？',
      options: const ['親', '子'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FamilyParentGenderScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '自分: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FamilyParentGenderScreen extends StatelessWidget {
  const FamilyParentGenderScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'この違いも会話のトーンに影響します',
      question: '親は？',
      options: const ['母', '父', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '親: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FamilySiblingScreen extends StatelessWidget {
  const FamilySiblingScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '兄姉か弟妹かで距離感が変わります',
      question: '相手は？',
      options: const ['兄', '姉', '弟', '妹', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FamilyInlawScreen extends StatelessWidget {
  const FamilyInlawScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '義家族の中でも関係の近さがかなり違います',
      question: '相手は？',
      options: const ['義母', '義父', '義兄弟姉妹', 'そのほか', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThemeSelectionScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  List<String> get themes {
    switch (draft.relationType) {
      case 'friend':
        return [
          '連絡頻度',
          '言い方がきつい',
          '約束',
          '人間関係・温度差',
          'お金',
          '距離感',
          '価値観の違い',
          'その他',
        ];
      case 'family_parent_child':
      case 'parent_child':
        return [
          '連絡頻度',
          '言い方がきつい',
          '口出し・干渉',
          '信頼されていない感じ',
          'お金',
          '家のこと・役割分担',
          '距離感',
          '価値観の違い',
          'その他',
        ];
      case 'family_sibling':
        return [
          '言い方がきつい',
          '親を挟んだ揉めごと',
          '比較される',
          'お金',
          '家のこと・役割分担',
          '距離感',
          '価値観の違い',
          'その他',
        ];
      case 'family_inlaw':
        return [
          '言い方がきつい',
          '行事・付き合い',
          '生活や子育てへの口出し',
          'パートナー経由の伝わり方',
          'お金',
          '距離感',
          '価値観の違い',
          'その他',
        ];
      case 'family':
      case 'family_other':
        return [
          '連絡頻度',
          '言い方がきつい',
          '干渉・信頼',
          'お金',
          '家のこと',
          '距離感',
          '価値観の違い',
          'その他',
        ];
      case 'other':
        return ['連絡頻度', '言い方がきつい', '約束', '距離感', 'お金', '価値観の違い', 'その他'];
      case 'couple':
      default:
        return [
          '連絡頻度',
          '言い方がきつい',
          '約束',
          '嫉妬',
          'お金',
          '家事',
          '距離感',
          '親の介入',
          '価値観の違い',
          'その他',
        ];
    }
  }

  void _selectTheme(BuildContext context, String theme) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemeDetailScreen(draft: draft.copyWith(theme: theme)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metaText = draft.selectedProfile != null
        ? 'プロフィール: ${draft.selectedProfile!.displayName} / ${draft.selectedProfile!.relationLabel}'
        : '関係性: ${draft.relationLabel}';

    return ConsultationScaffold(
      currentStep: 2,
      title: '今回は何がきっかけですか？',
      subtitle: 'いちばん近いものを1つ選んでください',
      meta: metaText,
      child: Expanded(
        child: ListView.separated(
          itemCount: themes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final theme = themes[index];
            return ElevatedButton(
              onPressed: () => _selectTheme(context, theme),
              style: elevatedChoiceStyle,
              child: Text(theme, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

class ThemeDetailScreen extends StatefulWidget {
  const ThemeDetailScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  State<ThemeDetailScreen> createState() => _ThemeDetailScreenState();
}

class _ThemeDetailScreenState extends State<ThemeDetailScreen> {
  int currentQuestionIndex = 0;
  final List<String> answers = [];
  final List<String> answerKeys = [];

  List<ThemeQuestion> get questions => _buildQuestions(
    relationType: widget.draft.relationType ?? 'couple',
    theme: widget.draft.theme ?? 'その他',
  );

  String _answerKey(int questionIndex, int optionIndex) {
    final relation = (widget.draft.relationType ?? 'unknown').trim();
    final theme = (widget.draft.theme ?? 'その他').trim();
    return '$relation|$theme|q${questionIndex + 1}|o${optionIndex + 1}';
  }

  void _selectAnswer(String answer, int optionIndex) {
    answers.add(answer);
    answerKeys.add(_answerKey(currentQuestionIndex, optionIndex));

    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CurrentStatusScreen(
          draft: widget.draft.copyWith(
            themeAnswers: List<String>.from(answers),
            themeAnswerKeys: List<String>.from(answerKeys),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = questions[currentQuestionIndex];

    return ConsultationScaffold(
      currentStep: 3,
      title: question.title,
      subtitle: '${currentQuestionIndex + 1} / ${questions.length}',
      meta: 'テーマ: ${widget.draft.theme}',
      child: Expanded(
        child: ListView.separated(
          itemCount: question.options.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final option = question.options[index];
            return ElevatedButton(
              onPressed: () => _selectAnswer(option, index),
              style: elevatedChoiceStyle,
              child: Text(option, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

String _draftAnswer(ConsultationDraft draft, int index) {
  if (index < 0 || index >= draft.themeAnswers.length) {
    return '';
  }
  return draft.themeAnswers[index].trim();
}

String _draftAnswerBundle(ConsultationDraft draft) {
  return draft.themeAnswers.where((e) => e.trim().isNotEmpty).join(' / ');
}

String _draftMetaLabel(ConsultationDraft draft, {required String fallback}) {
  final bundle = _draftAnswerBundle(draft);
  if (bundle.isEmpty) {
    return fallback;
  }
  return '$fallback / $bundle';
}

List<String>? _coupleCoreStatusOptions(String theme) {
  final config = _coupleCoreConfig(theme);
  if (config == null) return null;
  return _choiceLabels(config.statusOptions);
}

String? _coupleCoreStatusSubtitle(String theme) {
  return _coupleCoreConfig(theme)?.statusSubtitle;
}

String _statusTitleForDraft(ConsultationDraft draft) {
  final rtStatusTitle = draft.relationType ?? '';
  final thStatusTitle = draft.theme ?? '';
  if (rtStatusTitle == 'couple') {
    final overridden = _coupleCoreStatusTitle(thStatusTitle);
    if (overridden != null) {
      return overridden;
    }
  }
  switch (draft.theme) {
    case '嫉妬':
      return '今どの段階ですか？';
    case '連絡頻度':
      return '連絡まわりは今どんな状態ですか？';
    case '言い方がきつい':
      return '今そのやり取りはどんな空気ですか？';
    case '約束':
      return '約束の件はいまどこまで進んでいますか？';
    case 'お金':
      return 'お金の件はいまどんな状態ですか？';
    case '距離感':
      return '今の距離感はどんな状態ですか？';
    case '価値観の違い':
      return '価値観のズレは今どんな状態ですか？';
    default:
      return '今はどんな状態ですか？';
  }
}

String _statusSubtitleForDraft(ConsultationDraft draft) {
  final rtStatusSubtitle = draft.relationType ?? '';
  final thStatusSubtitle = draft.theme ?? '';
  if (rtStatusSubtitle == 'couple') {
    final overridden = _coupleCoreStatusSubtitle(thStatusSubtitle);
    if (overridden != null) {
      return overridden;
    }
  }
  final rt = draft.relationType ?? '';
  final th = draft.theme ?? '';
  if (rt == 'couple') {
    final subtitleOverride = _coupleCoreStatusSubtitle(th);
    if (subtitleOverride != null) {
      return subtitleOverride;
    }
  }
  switch (draft.theme) {
    case '嫉妬':
      return '不安が心の中だけか、すでに表に出ているかに近いものを選んでください';
    case '連絡頻度':
      return '返信の止まり方や温度感にいちばん近いものを選んでください';
    case '言い方がきつい':
      return '傷つきや気まずさが今どう残っているかで選んでください';
    case '約束':
      return '未消化のままか、話し合いが始まっているかで選んでください';
    case 'お金':
      return '感情のこじれ方にいちばん近いものを選んでください';
    default:
      return 'いちばん近いものを選んでください';
  }
}

String _goalTitleForDraft(ConsultationDraft draft) {
  final rtGoalTitle = draft.relationType ?? '';
  final thGoalTitle = draft.theme ?? '';
  if (rtGoalTitle == 'couple') {
    final overridden = _coupleCoreGoalTitle(thGoalTitle);
    if (overridden != null) {
      return overridden;
    }
  }
  switch (draft.theme) {
    case '嫉妬':
      return '今回はどこを目指したいですか？';
    case '連絡頻度':
      return '連絡のことで今回はどうしたいですか？';
    case '言い方がきつい':
      return 'この件をどう着地させたいですか？';
    case '約束':
      return '約束の件を今回はどうしたいですか？';
    case 'お金':
      return 'お金の件を今回はどう進めたいですか？';
    default:
      return '今回どうしたいですか？';
  }
}

String _goalSubtitleForDraft(ConsultationDraft draft) {
  final rtGoalSubtitle = draft.relationType ?? '';
  final thGoalSubtitle = draft.theme ?? '';
  if (rtGoalSubtitle == 'couple') {
    final overridden = _coupleCoreGoalSubtitle(thGoalSubtitle);
    if (overridden != null) {
      return overridden;
    }
  }
  switch (draft.theme) {
    case '嫉妬':
      return '安心したいのか、伝えたいのか、線引きしたいのかで選んでください';
    case '連絡頻度':
      return '追い連絡、すり合わせ、いったん待つ、のどれに近いかで選んでください';
    case '言い方がきつい':
      return '謝る・伝える・落ち着かせる、のどれを優先したいかで選んでください';
    default:
      return '今いちばん近い目的を選んでください';
  }
}

List<String> _statusOptionsForDraft(ConsultationDraft draft) {
  final rtStatusOptions = draft.relationType ?? '';
  final thStatusOptions = draft.theme ?? '';
  if (rtStatusOptions == 'couple') {
    final overridden = _coupleCoreStatusOptions(thStatusOptions);
    if (overridden != null) {
      return overridden;
    }
  }
  final relationType = draft.relationType ?? '';
  final theme = draft.theme ?? '';
  if (relationType == 'couple') {
    final overridden = _coupleCoreStatusOptions(theme);
    if (overridden != null) {
      return overridden;
    }
  }
  final a1 = _draftAnswer(draft, 0);
  final a2 = _draftAnswer(draft, 1);
  final a3 = _draftAnswer(draft, 2);
  final bundle = '$a1 / $a2 / $a3';

  if (relationType == 'couple' && theme == 'お金') {
    return const [
      'デート代や生活費の負担に不公平感がある',
      '貸し借りや立替の話が止まっている',
      '金額より扱われ方が雑に感じてつらい',
      'お金の話を出すと空気が悪くなりそう',
      '将来のお金の感覚まで不安になっている',
      'まず事実だけ整理したい',
      '感情を乗せすぎず話したい',
      '今日はぶつからない形にしたい',
    ];
  }

  if (relationType == 'couple' && theme == '距離感') {
    return const [
      '会いたい頻度にズレがある',
      '一人時間の取り方でモヤモヤしている',
      '近すぎて息苦しい',
      '遠すぎて不安になっている',
      '重いと思われそうで本音を言えていない',
      '関わり方を相談したい',
      '少し距離を置いて整えたい',
      '今は柔らかく伝えたい',
    ];
  }

  if (relationType == 'friend' && theme == 'お金') {
    return const [
      '立替や割り勘が曖昧なままになっている',
      '催促したいが関係が気まずくなりそう',
      '少額でもモヤモヤが残っている',
      '金額より誠実さの問題に感じる',
      '一度話したが流れてしまった',
      'まず事実だけ確認したい',
      '友情を壊さずに伝えたい',
      '今日は強く出ない方がよさそう',
    ];
  }

  if (relationType == 'friend' && theme == '距離感') {
    return const [
      'こちらばかり誘っている感じがする',
      '急に距離を置かれて不安になっている',
      '近すぎてしんどいが切り出しづらい',
      '相手の優先順位が下がったようで寂しい',
      '期待値のズレが積み重なっている',
      '軽く整えたい',
      '少し引いて様子を見たい',
      '今は本音を柔らかく伝えたい',
    ];
  }

  if (relationType == 'friend' && theme == '価値観の違い') {
    return const [
      'ノリや常識のズレがしんどい',
      '悪気はなさそうだが合わなさを感じる',
      '話すと面倒な人と思われそうで言いにくい',
      '合わせ続けるのがしんどい',
      '関係を切るほどではないが疲れている',
      '違いとして整理したい',
      '今後の距離感を見直したい',
      '今は深掘りしない方がよさそう',
    ];
  }

  if ((relationType == 'family' ||
          relationType == 'family_other' ||
          relationType == 'family_parent_child' ||
          relationType == 'parent_child' ||
          relationType == 'family_sibling') &&
      theme == 'お金') {
    return const [
      '家族内のお金の役割が曖昧になっている',
      '貸し借りや援助の期待が重い',
      '感謝より当然の空気がつらい',
      '断ると冷たいと思われそうで苦しい',
      '昔からの積み重なりがある',
      'まず条件を整理したい',
      '感情的にならず線を引きたい',
      '今日は火を大きくしたくない',
    ];
  }

  if ((relationType == 'family' ||
          relationType == 'family_other' ||
          relationType == 'family_parent_child' ||
          relationType == 'parent_child' ||
          relationType == 'family_sibling') &&
      (theme == '家のこと' || theme == '家のこと・役割分担')) {
    return const [
      '家の負担が片寄っている',
      '言っても当たり前のように流される',
      '自分だけが動いている感じがする',
      '昔からの役割固定がしんどい',
      '感謝されないことにも疲れている',
      '分担を見直したい',
      'まず一部だけでも変えたい',
      '今は穏やかに切り出したい',
    ];
  }

  if (relationType == 'family_inlaw' && theme == 'お金') {
    return const [
      'お祝い・援助・負担の線引きが曖昧',
      '家ごとの金銭感覚の差がしんどい',
      'パートナー経由で話がややこしくなっている',
      'こちらだけ我慢している感じがある',
      '今後も続く話で不安が強い',
      'まずパートナーと整理したい',
      '角を立てず線引きしたい',
      '今回は荒立てたくない',
    ];
  }

  if (relationType == 'family_inlaw' && theme == '行事・付き合い') {
    return const [
      '毎回こちらの負担が大きい',
      '断ると感じが悪いと思われそう',
      '参加前から気が重い',
      'パートナーとの温度差もつらい',
      '相手側に悪気はなさそうで余計言いにくい',
      'まずパートナーに理解してほしい',
      '今後の参加ラインを決めたい',
      '今回は穏便に済ませたい',
    ];
  }

  if (relationType == 'family_inlaw' && theme == 'パートナー経由の伝わり方') {
    return const [
      '自分の意図と違う形で伝わってしまった',
      'パートナーの言い方で角が立った感じがある',
      '誰に何をどう伝えるかが曖昧になっている',
      '直接言うべきか迷っている',
      'まずパートナーと認識をそろえたい',
      '責めずに修正したい',
      '今後の伝え方ルールを決めたい',
      '今日は広げない方がよさそう',
    ];
  }

  if (relationType == 'couple' && theme == '嫉妬') {
    if (bundle.contains('相手') && bundle.contains('嫉妬')) {
      return const [
        '相手が疑ったり不安をぶつけてきている',
        '相手が少しピリついている',
        '何度か確認されて気まずい',
        '一度言い合いになった',
        'まだ大きくは揉めていない',
        '今から安心させる返事をしたい',
        '会う前に整理しておきたい',
        '少し時間をおいてから話したい',
      ];
    }
    return const [
      'まだ言い出せていない',
      '軽く聞いたがモヤモヤが残っている',
      '嫉妬っぽい空気が出てしまっている',
      'すでに言い合いになった',
      '相手が防御的・反発気味',
      '今から落ち着いて伝えたい',
      '会う前に気持ちを整理したい',
      'いったん様子を見たい',
    ];
  }

  if (theme == '連絡頻度') {
    if (bundle.contains('未読')) {
      return const [
        '未読がしばらく続いている',
        '追い連絡したい気持ちが強い',
        '追い連絡すると悪化しそう',
        '他では動いていそうで不安',
        '前にも同じことで揉めた',
        '今は待つべきか迷っている',
        '会う予定の前で気まずい',
        'もう少しで爆発しそう',
      ];
    }
    if (bundle.contains('既読')) {
      return const [
        '既読だが返ってこない',
        '既読後の沈黙がつらい',
        '何を送れば重くならないか迷う',
        'すでに少し責めてしまった',
        '相手の温度が低く感じる',
        '今からもう一通送りたい',
        '返事を待つべきか迷っている',
        'いったん止めた方がよさそう',
      ];
    }
    return const [
      '返信はあるが温度差がつらい',
      '連絡ペースのズレが積み重なっている',
      '自分が求めすぎた気もする',
      '相手が負担に感じていそう',
      '話し合いまではできていない',
      '今から軽く送ってみたい',
      '今日は送らず様子を見たい',
      '会う前に整理したい',
    ];
  }

  if (theme == '言い方がきつい') {
    if (bundle.contains('自分がきつく言ってしまった') ||
        (bundle.contains('自分') && bundle.contains('きつ'))) {
      return const [
        '自分が強く言いすぎて気まずい',
        '相手を傷つけた感じが残っている',
        'すぐ謝りたいが言い方に迷う',
        '相手が距離を取っている',
        'すでに空気が悪くなっている',
        'LINEで一言入れたい',
        '電話や対面で話した方がよさそう',
        '今は少し冷ました方がよさそう',
      ];
    }
    return const [
      '強い言い方がまだ引っかかっている',
      '相手は普通だが自分だけ傷ついている',
      '相手もイライラしていそう',
      'すでに少し言い返してしまった',
      '今すぐ返すと感情的になりそう',
      '落ち着いて伝え直したい',
      'まず距離を置きたい',
      '対面で話した方がよさそう',
    ];
  }

  if (theme == '約束') {
    if (bundle.contains('自分') && !bundle.contains('お互い')) {
      return const [
        '自分が守れず気まずい',
        '言い訳っぽくしたくない',
        '相手が怒っていそう',
        'すぐ謝りたい',
        '埋め合わせも考えたい',
        'まだ連絡できていない',
        '一度謝ったが気まずいまま',
        '今から丁寧に伝えたい',
      ];
    }
    if (bundle.contains('お互い')) {
      return const [
        'どちらも少しずつ不満がある',
        '責任の押し付け合いになりそう',
        '細かい認識ズレが残っている',
        'まだ整理して話せていない',
        '感情より事実確認が必要',
        '今から落ち着いて話したい',
        '一度仕切り直したい',
        '少し時間を置きたい',
      ];
    }
    return const [
      '相手に破られた感じが残っている',
      '軽く扱われたようでつらい',
      'まだちゃんと話せていない',
      '言うと責める形になりそう',
      '一度伝えたが伝わっていない',
      '今から気持ちを伝えたい',
      'まず事実確認したい',
      '今日は触れない方がよさそう',
    ];
  }

  if (theme == 'お金') {
    return const [
      'まだ具体的に話し合えていない',
      '金額や負担感にモヤモヤがある',
      '払う・返す話が止まっている',
      '不公平感が強くなっている',
      '一度揉めて気まずい',
      '感情を抜いて確認したい',
      '今すぐ返す・払う方向で動きたい',
      '今日は話さない方がよさそう',
    ];
  }

  if (theme == '距離感') {
    return const [
      '近すぎてしんどい',
      '遠すぎて不安',
      '自分ばかり合わせている感じがする',
      '相手に重いと思われそうで言えない',
      'すでに少し距離ができている',
      '会う頻度や関わり方を相談したい',
      'いったん一人の時間がほしい',
      '今から柔らかく伝えたい',
    ];
  }

  if (theme == '価値観の違い') {
    return const [
      '考え方のズレがずっと引っかかっている',
      '片方だけが正しい話にしたくない',
      '話すと平行線になりそう',
      'すでに少し諦めが出ている',
      'でも関係は壊したくない',
      '違いとして整理したい',
      '譲れる所と譲れない所を分けたい',
      '今は深掘りしない方がよさそう',
    ];
  }

  if (theme == '家事' || theme == '家のこと' || theme == '家のこと・役割分担') {
    return const [
      '負担の偏りがしんどい',
      '言うと細かい人みたいで言いづらい',
      '相手は気づいていなさそう',
      'すでにイライラが溜まっている',
      '一度言ったが続いていない',
      '分担を見直したい',
      '責めずにお願いしたい',
      '今日は言わない方がよさそう',
    ];
  }

  if (theme == '親の介入') {
    return const [
      '親のことが直接しんどい',
      '相手が間に入ってくれずつらい',
      '親の話題を出すと空気が悪くなる',
      '自分が我慢しすぎている',
      '境界線を引きたい',
      'まず相手だけに伝えたい',
      '会う前に整理したい',
      '今は刺激しない方がよさそう',
    ];
  }

  if (theme == '人間関係・温度差') {
    return const [
      '自分の熱量ばかり高い気がする',
      '相手の優先順位が低く感じる',
      '友人関係の温度差がしんどい',
      '言うと重くなりそうで迷う',
      '少し距離ができている',
      '期待値を合わせたい',
      '関係を軽く整えたい',
      '今は一歩引きたい',
    ];
  }

  if (theme == '行事・付き合い') {
    return const [
      '参加や頻度に温度差がある',
      '断り方や伝わり方がしんどい',
      '毎回こちらが気を遣っている',
      '相手や家族に悪気はなさそう',
      'でも負担は大きい',
      'まずパートナーに伝えたい',
      '今後の線引きを決めたい',
      '今回は穏便にやり過ごしたい',
    ];
  }

  if (theme == '生活や子育てへの口出し') {
    return const [
      '相手側の口出しがしんどい',
      '自分たちのやり方を守りたい',
      'パートナーが間に入ってくれない',
      '言い返すと大ごとになりそう',
      '我慢が積み重なっている',
      'まずパートナーと足並みをそろえたい',
      '柔らかく境界線を伝えたい',
      '今は波風を立てたくない',
    ];
  }

  if (theme == 'パートナー経由の伝わり方') {
    return const [
      '自分の意図と違って伝わった感じがする',
      'パートナーの伝え方にモヤモヤがある',
      '間接的な伝わり方でこじれている',
      '直接言うか迷っている',
      'まずパートナーと整理したい',
      '相手を責めずに修正したい',
      '今後の伝え方を決めたい',
      '今日は広げない方がよさそう',
    ];
  }

  if (theme == '口出し・干渉' || theme == '干渉・信頼' || theme == '信頼されていない感じ') {
    return const [
      '口を出されてしんどい',
      '信頼されていない感じが続いている',
      '反発したいが角が立ちそう',
      'すでに少し空気が悪い',
      '境界線を引きたい',
      'まず気持ちだけ伝えたい',
      '距離を少し取りたい',
      '今は落ち着かせたい',
    ];
  }

  if (theme == '比較される') {
    return const [
      '比べられて傷ついている',
      '昔からの積み重なりがある',
      '一回の話では済まない',
      '言い返すと大きくなりそう',
      'でも我慢し続けたくない',
      '比較がつらいことを伝えたい',
      '今後の距離を考えたい',
      '今は深入りしない方がよさそう',
    ];
  }

  if (theme == '親を挟んだ揉めごと') {
    return const [
      '親を挟んで話がややこしくなっている',
      '直接の相手だけの問題ではなくなっている',
      '事実と感情が混ざっている',
      '誰に何を言うべきか迷う',
      'まず順番を整理したい',
      '直接ぶつからず整えたい',
      '第三者を入れたい気持ちもある',
      '今は感情的になりやすい',
    ];
  }

  return const [
    '相手が怒っている',
    '自分が怒っている',
    'お互い感情的',
    '既読無視されている',
    '未読のまま',
    '会話が止まっている',
    'さっき電話で揉めた',
    '今から返信したい',
  ];
}

List<String> _goalOptionsForDraft(ConsultationDraft draft) {
  final rtGoalOptions = draft.relationType ?? '';
  final thGoalOptions = draft.theme ?? '';
  if (rtGoalOptions == 'couple') {
    final overridden = _coupleCoreGoalOptions(thGoalOptions);
    if (overridden != null) {
      return overridden;
    }
  }
  final theme = draft.theme ?? '';
  final relationType = draft.relationType ?? '';
  final bundle = _draftAnswerBundle(draft);

  if (relationType == 'couple' && theme == 'お金') {
    return const [
      'お金の話を避けずに整えたい',
      '不公平感を責めすぎず伝えたい',
      '立替・返金・負担割合をはっきりさせたい',
      '将来のお金の感覚をすり合わせたい',
      'まず空気を悪くしないよう伝えたい',
      '今日は結論を急がず整理したい',
    ];
  }

  if (relationType == 'couple' && theme == '距離感') {
    return const [
      '会う頻度や一人時間をすり合わせたい',
      '重くならずに寂しさを伝えたい',
      '少し距離を置いて整えたい',
      '不安にさせず自分の時間も守りたい',
      '期待値を合わせたい',
      '関係を壊さず整えたい',
    ];
  }

  if (relationType == 'friend' && theme == 'お金') {
    return const [
      '友情を壊さずに事実確認したい',
      '立替や返金の話をはっきりさせたい',
      '誠実さの問題として穏やかに伝えたい',
      '今後お金を混ぜない線引きをしたい',
      '重くしすぎず整えたい',
      '今日は深追いしないでおきたい',
    ];
  }

  if (relationType == 'friend' && theme == '距離感') {
    return const [
      '期待値を合わせたい',
      '寂しさや違和感を軽く伝えたい',
      '少し距離を置きたい',
      '一方通行感を整えたい',
      '今後の関わり方を見直したい',
      'まず自分の気持ちを整理したい',
    ];
  }

  if (relationType == 'friend' && theme == '価値観の違い') {
    return const [
      '違いとして整理したい',
      '合わない所を穏やかに伝えたい',
      '無理に合わせすぎない形にしたい',
      '距離感を見直したい',
      '関係を切らずに軽く整えたい',
      '今回は深追いしないでおきたい',
    ];
  }

  if ((relationType == 'family' ||
          relationType == 'family_other' ||
          relationType == 'family_parent_child' ||
          relationType == 'parent_child' ||
          relationType == 'family_sibling') &&
      theme == 'お金') {
    return const [
      '家族内のお金の線引きをはっきりさせたい',
      '感情的にならず条件を整理したい',
      '当然のように扱われるしんどさを伝えたい',
      '無理な負担は断れる形にしたい',
      '今後も揉めにくいルールを決めたい',
      '今日は火を広げたくない',
    ];
  }

  if ((relationType == 'family' ||
          relationType == 'family_other' ||
          relationType == 'family_parent_child' ||
          relationType == 'parent_child' ||
          relationType == 'family_sibling') &&
      (theme == '家のこと' || theme == '家のこと・役割分担')) {
    return const [
      '負担の偏りを伝えたい',
      '責めすぎず役割を見直したい',
      'まず一部だけでも変えたい',
      '当たり前扱いがつらいことを伝えたい',
      '続けられる分担にしたい',
      '今日は穏やかに触れるだけにしたい',
    ];
  }

  if (relationType == 'family_inlaw' && theme == 'お金') {
    return const [
      'まずパートナーと足並みをそろえたい',
      '家ごとの金銭感覚の差を整理したい',
      '無理な負担には線を引きたい',
      '角を立てすぎず伝えたい',
      '今後の負担ルールを決めたい',
      '今回は荒立てず整えたい',
    ];
  }

  if (relationType == 'family_inlaw' && theme == '行事・付き合い') {
    return const [
      '無理のない参加ラインを決めたい',
      'まずパートナーに理解してほしい',
      '負担感を責めずに伝えたい',
      '今回は穏便に済ませたい',
      '今後の線引きを明確にしたい',
      '自分ばかり我慢しない形にしたい',
    ];
  }

  if (relationType == 'family_inlaw' && theme == 'パートナー経由の伝わり方') {
    return const [
      'まずパートナーと認識を合わせたい',
      '自分の意図を正しく伝え直したい',
      '責めずに伝え方を見直したい',
      '間接伝達を減らしたい',
      '今回は火消しを優先したい',
      '今後の伝え方ルールを決めたい',
    ];
  }

  if (theme == '嫉妬') {
    if (bundle.contains('相手') && bundle.contains('嫉妬')) {
      return const [
        '相手を安心させたい',
        '疑われてしんどいことを伝えたい',
        '誤解を解きたい',
        '今後の線引きを決めたい',
        'まず落ち着かせたい',
        '刺激せず様子を見たい',
      ];
    }
    return const [
      '責めずに不安を伝えたい',
      '安心できる説明がほしい',
      '自分の言い方を整えたい',
      '今後の線引きを決めたい',
      'まず謝りたい',
      '今は落ち着きたい',
    ];
  }

  if (theme == '連絡頻度') {
    return const [
      '連絡ペースをすり合わせたい',
      '追い連絡しすぎず気持ちを伝えたい',
      '不安を重くしすぎず伝えたい',
      '責めすぎたなら謝りたい',
      '今日は送らず様子を見たい',
      '仲直りしたい',
    ];
  }

  if (theme == '言い方がきつい') {
    if (bundle.contains('自分がきつく言ってしまった') ||
        (bundle.contains('自分') && bundle.contains('きつ'))) {
      return const [
        'まず謝りたい',
        '言い方は悪かったが本音も伝えたい',
        '相手を落ち着かせたい',
        '言い直したい',
        '少し時間を置きたい',
        '関係を修復したい',
      ];
    }
    return const [
      '傷ついたことを穏やかに伝えたい',
      'これ以上悪化させたくない',
      '言い返したことも整えたい',
      'まず距離を置きたい',
      '謝ってほしい気持ちを整理したい',
      '仲直りしたい',
    ];
  }

  if (theme == '約束') {
    if (bundle.contains('自分') && !bundle.contains('お互い')) {
      return const [
        'まず誠実に謝りたい',
        '事情を言い訳っぽくせず伝えたい',
        '埋め合わせを提案したい',
        '相手を落ち着かせたい',
        '信頼を戻したい',
        '今は短く連絡したい',
      ];
    }
    return const [
      '約束を軽く扱われた気持ちを伝えたい',
      'まず事実確認したい',
      '再発しない形を決めたい',
      '責めすぎず話したい',
      '一度仕切り直したい',
      '仲直りしたい',
    ];
  }

  if (theme == 'お金') {
    return const [
      '金額や事実を冷静に確認したい',
      '不公平感を穏やかに伝えたい',
      '返金・支払いの話を進めたい',
      '価値観の違いとして整理したい',
      '関係を悪化させず線引きしたい',
      '今日は送らず整えたい',
    ];
  }

  if (theme == '距離感') {
    return const [
      'ちょうどいい距離を相談したい',
      '重くならずに本音を伝えたい',
      '少し距離を置きたい',
      '不安にさせず一人の時間がほしい',
      '期待値を合わせたい',
      '関係を壊さず整えたい',
    ];
  }

  if (theme == '価値観の違い') {
    return const [
      '勝ち負けにせず話したい',
      '違いとして整理したい',
      '譲れる所と譲れない所を分けたい',
      '理解は難しくても尊重してほしい',
      '深追いせず落ち着かせたい',
      '関係を続ける前提で整えたい',
    ];
  }

  if (theme == '家事' || theme == '家のこと' || theme == '家のこと・役割分担') {
    return const [
      '負担の偏りを伝えたい',
      '責めずに分担を見直したい',
      'お願いベースで話したい',
      'ルールを決めたい',
      '感情的にならず整えたい',
      '今日は軽く触れるだけにしたい',
    ];
  }

  if (theme == '親の介入') {
    return const [
      'まずパートナーに味方になってほしい',
      '境界線を引きたい',
      '親の話題で揉めずに伝えたい',
      '自分のしんどさをわかってほしい',
      '今後の対応方針を決めたい',
      '今回は刺激せず流したい',
    ];
  }

  if (theme == '人間関係・温度差') {
    return const [
      '期待値を合わせたい',
      '温度差に傷ついたことを伝えたい',
      '重くならず関係を整えたい',
      '少し距離を置きたい',
      '今後の関わり方を見直したい',
      'まず自分の気持ちを整理したい',
    ];
  }

  if (theme == '行事・付き合い') {
    return const [
      '無理のない参加ラインを決めたい',
      'パートナーに間に入ってほしい',
      '負担感を柔らかく伝えたい',
      '今回は穏便に済ませたい',
      '今後の線引きを決めたい',
      '自分ばかり我慢しない形にしたい',
    ];
  }

  if (theme == '生活や子育てへの口出し') {
    return const [
      'まずパートナーと足並みをそろえたい',
      '口出しがしんどいことを伝えたい',
      '自分たちの方針を守りたい',
      '角を立てず境界線を引きたい',
      '今回は穏便に済ませたい',
      '今後の対応を決めたい',
    ];
  }

  if (theme == 'パートナー経由の伝わり方') {
    return const [
      'まずパートナーと認識を合わせたい',
      '自分の意図を正しく伝え直したい',
      '責めずに伝え方を見直したい',
      '間接伝達を減らしたい',
      '今回は火消しを優先したい',
      '今後の伝え方ルールを決めたい',
    ];
  }

  if (theme == '口出し・干渉' || theme == '干渉・信頼' || theme == '信頼されていない感じ') {
    return const [
      '境界線を穏やかに伝えたい',
      '信頼されていないしんどさを伝えたい',
      'これ以上干渉されたくない',
      'まず気持ちだけ共有したい',
      '少し距離を置きたい',
      '波風を立てず整えたい',
    ];
  }

  if (theme == '比較される') {
    return const [
      '比較がつらいことを伝えたい',
      '自分を一人の人として見てほしい',
      '今後その話し方をやめてほしい',
      '感情的にならず線を引きたい',
      '少し距離を置きたい',
      '今回は深追いしないでおきたい',
    ];
  }

  if (theme == '親を挟んだ揉めごと') {
    return const [
      '誰と何を話すか順番を整理したい',
      '直接ぶつからず整えたい',
      '事実関係をまず確認したい',
      '感情のエスカレートを止めたい',
      '自分の立場を守りたい',
      '今日は火を広げたくない',
    ];
  }

  return const [
    '謝りたい',
    '誤解を解きたい',
    '落ち着かせたい',
    '仲直りしたい',
    '距離を置きたい',
    '相手の気持ちを知りたい',
  ];
}

class CurrentStatusScreen extends StatelessWidget {
  const CurrentStatusScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  String _statusKey(int optionIndex) {
    final relation = (draft.relationType ?? 'unknown').trim();
    final theme = (draft.theme ?? 'その他').trim();
    return '$relation|$theme|status|o${optionIndex + 1}';
  }

  void _selectStatus(BuildContext context, String status, int optionIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmotionLevelScreen(
          draft: draft.copyWith(
            currentStatus: status,
            currentStatusKey: _statusKey(optionIndex),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statusOptionsForDraft(draft);

    return ConsultationScaffold(
      currentStep: 4,
      title: _statusTitleForDraft(draft),
      subtitle: _statusSubtitleForDraft(draft),
      meta: _draftMetaLabel(draft, fallback: 'テーマ: ${draft.theme}'),
      child: Expanded(
        child: ListView.separated(
          itemCount: statuses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final status = statuses[index];
            return ElevatedButton(
              onPressed: () => _selectStatus(context, status, index),
              style: elevatedChoiceStyle,
              child: Text(status, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

String _emotionTitleForDraft(ConsultationDraft draft) {
  switch (draft.theme) {
    case '嫉妬':
      return '今の感情はどれに近いですか？';
    case '連絡頻度':
      return '連絡の件で今の心の状態は？';
    case '言い方がきつい':
      return '今の傷つきやイライラはどれくらいですか？';
    case '約束':
      return '約束の件で今の感情はどれに近いですか？';
    case 'お金':
      return 'お金の件で今どれくらい感情が動いていますか？';
    case '距離感':
      return '距離感の件で今の気持ちはどれに近いですか？';
    case '価値観の違い':
      return '価値観のズレに対して今の気持ちは？';
    default:
      return '今の感情の強さはどれくらいですか？';
  }
}

String _emotionSubtitleForDraft(ConsultationDraft draft) {
  switch (draft.theme) {
    case '嫉妬':
      return '不安なのか、怒りなのか、今送ると荒れそうなのかで選んでください';
    case '連絡頻度':
      return 'まだ待てるか、かなり不安か、今送ると重くなりそうかで選んでください';
    case '言い方がきつい':
      return '冷静さが残っているか、かなり刺さっているかで選んでください';
    case '約束':
      return '悲しさ・怒り・申し訳なさの強さに近いものを選んでください';
    case 'お金':
      return '事実確認モードか、感情が強くなっているかで選んでください';
    default:
      return '今の自分にいちばん近いものを選んでください';
  }
}

List<String> _emotionOptionsForDraft(ConsultationDraft draft) {
  final theme = draft.theme ?? '';
  final bundle = draft.themeAnswers.join(' / ');

  if (theme == '嫉妬') {
    if (bundle.contains('相手') && bundle.contains('嫉妬')) {
      return const [
        'まだ冷静に安心させる言い方を考えられる',
        '少ししんどいが落ち着いて返せそう',
        '相手に疑われてかなりしんどい',
        '今返すと反発してしまいそう',
      ];
    }
    return const [
      'まだ落ち着いて不安を整理できる',
      '少し不安が強くなっている',
      'かなりモヤモヤして感情が動いている',
      '今送ると責める言い方になりそう',
    ];
  }

  if (theme == '連絡頻度') {
    if (bundle.contains('未読')) {
      return const ['まだ少し待てそう', '気になって落ち着かない', 'かなり不安でつらい', '今送ると追い連絡が重くなりそう'];
    }
    if (bundle.contains('既読')) {
      return const [
        'まだ冷静に様子を見られる',
        '既読後の沈黙が少しつらい',
        'かなりしんどくて考えすぎてしまう',
        '今送ると圧のある文になりそう',
      ];
    }
    return const ['まだ落ち着いて考えられる', '少し寂しさや不安がある', 'かなり温度差がつらい', '今送ると重くなりそう'];
  }

  if (theme == '言い方がきつい') {
    if (bundle.contains('自分がきつく言ってしまった') ||
        (bundle.contains('自分') && bundle.contains('きつ'))) {
      return const [
        'すぐ謝れるくらいには落ち着いている',
        '少し気まずくて焦っている',
        'かなり自己嫌悪や不安が強い',
        '今送ると弁解が多くなりそう',
      ];
    }
    return const [
      '冷静に言い直しを考えられる',
      '傷つきがまだ残っている',
      'かなりイライラ・悲しさが強い',
      '今返すと刺々しくなりそう',
    ];
  }

  if (theme == '約束') {
    if (bundle.contains('自分') && !bundle.contains('お互い')) {
      return const [
        '落ち着いて謝れそう',
        '少し焦りや申し訳なさがある',
        'かなり気まずくてしんどい',
        '今送ると弁解っぽくなりそう',
      ];
    }
    return const ['まだ冷静に話せそう', '少し悲しい・モヤモヤする', 'かなり怒りや失望が強い', '今送ると責めすぎそう'];
  }

  if (theme == 'お金') {
    return const [
      '事実確認を冷静にできそう',
      '少し不公平感が気になっている',
      'かなりモヤモヤや怒りが強い',
      '今送るときつくなりそう',
    ];
  }

  if (theme == '距離感') {
    return const [
      '落ち着いて距離の話ができそう',
      '少し息苦しさ・寂しさがある',
      'かなりしんどくて余裕がない',
      '今送ると重い・突き放す感じになりそう',
    ];
  }

  if (theme == '価値観の違い') {
    return const [
      '違いとして冷静に見られる',
      '少し引っかかりが残っている',
      'かなりしんどくて受け流せない',
      '今話すと平行線で荒れそう',
    ];
  }

  if (theme == '家事' || theme == '家のこと' || theme == '家のこと・役割分担') {
    return const ['冷静に相談できそう', '少しイライラが溜まっている', 'かなり不満が爆発しそう', '今言うと責め口調になりそう'];
  }

  if (theme == '親の介入') {
    return const [
      '落ち着いて線引きの話ができそう',
      '少ししんどいがまだ整えられる',
      'かなりストレスが強い',
      '今話すと一気に荒れそう',
    ];
  }

  if (theme == '人間関係・温度差') {
    return const ['落ち着いて受け止められる', '少し寂しさがある', 'かなり温度差がつらい', '今送ると重くなりそう'];
  }

  if (theme == '行事・付き合い') {
    return const ['穏やかに相談できそう', '少し負担感がある', 'かなりうんざりしている', '今言うと角が立ちそう'];
  }

  if (theme == '生活や子育てへの口出し') {
    return const ['まだ冷静に話せそう', '少ししんどさが溜まっている', 'かなり限界に近い', '今返すときつくなりそう'];
  }

  if (theme == 'パートナー経由の伝わり方') {
    return const ['落ち着いて整理できそう', '少しモヤモヤしている', 'かなり納得いかない', '今言うと責める感じになりそう'];
  }

  if (theme == '口出し・干渉' || theme == '干渉・信頼' || theme == '信頼されていない感じ') {
    return const ['まだ穏やかに伝えられそう', '少ししんどさがある', 'かなり窮屈でつらい', '今言うと反発が強く出そう'];
  }

  if (theme == '比較される') {
    return const ['冷静に受け止め直せる', '少し傷ついている', 'かなり刺さってつらい', '今返すと感情的になりそう'];
  }

  if (theme == '親を挟んだ揉めごと') {
    return const [
      'まだ順番を整理して考えられる',
      '少し混乱している',
      'かなりしんどくて余裕がない',
      '今動くとさらにこじれそう',
    ];
  }

  return const ['落ち着いている', '少ししんどい', 'かなり感情的', '今送ると悪化しそう'];
}

class EmotionLevelScreen extends StatelessWidget {
  const EmotionLevelScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  void _selectEmotion(BuildContext context, String emotionLevel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GoalScreen(draft: draft.copyWith(emotionLevel: emotionLevel)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emotionLevels = _emotionOptionsForDraft(draft);

    return ConsultationScaffold(
      currentStep: 5,
      title: _emotionTitleForDraft(draft),
      subtitle: _emotionSubtitleForDraft(draft),
      meta: '状態: ${draft.currentStatus}',
      child: Expanded(
        child: ListView.separated(
          itemCount: emotionLevels.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final level = emotionLevels[index];
            return ElevatedButton(
              onPressed: () => _selectEmotion(context, level),
              style: elevatedChoiceStyle,
              child: Text(level, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  String _goalKey(int optionIndex) {
    final relation = (draft.relationType ?? 'unknown').trim();
    final theme = (draft.theme ?? 'その他').trim();
    return '$relation|$theme|goal|o${optionIndex + 1}';
  }

  void _selectGoal(BuildContext context, String goal, int optionIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvidenceInputScreen(
          draft: draft.copyWith(goal: goal, goalKey: _goalKey(optionIndex)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goalOptionsForDraft(draft);

    return ConsultationScaffold(
      currentStep: 6,
      title: _goalTitleForDraft(draft),
      subtitle: _goalSubtitleForDraft(draft),
      meta: _draftMetaLabel(draft, fallback: '感情: ${draft.emotionLevel}'),
      child: Expanded(
        child: ListView.separated(
          itemCount: goals.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final goal = goals[index];
            return ElevatedButton(
              onPressed: () => _selectGoal(context, goal, index),
              style: elevatedChoiceStyle,
              child: Text(goal, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

class _PickedScreenshot {
  const _PickedScreenshot({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

List<String> _latentSignalsForChoiceKey(String key) {
  final parts = key.split('|');
  if (parts.length < 4) return const [];

  final relation = parts[0];
  final theme = parts[1];
  final slot = parts[2];
  final option = parts[3];

  if (relation != 'couple') return const [];

  if (slot == 'status') {
    switch (option) {
      case 'o1':
        return const ['issue_unspoken', 'conflict_visibility_low'];
      case 'o2':
        return const ['early_signal', 'tension_emerging'];
      case 'o3':
        return const ['ongoing_strain', 'issue_persisting'];
      case 'o4':
        return const ['active_conflict', 'emotional_activation_high'];
      case 'o5':
        return const ['relational_freeze', 'distance_increasing'];
    }
  }

  switch (theme) {
    case '連絡頻度':
      if (slot == 'q1') {
        switch (option) {
          case 'o1':
            return const [
              'response_absence',
              'contact_anxiety',
              'uncertainty_high',
            ];
          case 'o2':
            return const ['seen_no_reply', 'rejection_pain', 'contact_anxiety'];
          case 'o3':
            return const ['emotional_temperature_gap', 'reciprocity_gap'];
          case 'o4':
            return const ['overpursuit_risk', 'self_awareness_present'];
          case 'o5':
            return const ['engulfment_pressure', 'boundary_tension'];
        }
      }
      if (slot == 'q2') {
        switch (option) {
          case 'o1':
            return const ['abrupt_change', 'uncertainty_high'];
          case 'o2':
            return const ['chronic_pattern', 'issue_accumulation'];
          case 'o3':
            return const ['post_conflict_aftereffect', 'repair_need'];
          case 'o4':
            return const ['busyness_possible', 'malice_uncertain'];
          case 'o5':
            return const ['uncertainty_high', 'meaning_not_clear'];
        }
      }
      if (slot == 'goal') {
        switch (option) {
          case 'o1':
            return const ['clarify_intent'];
          case 'o2':
            return const ['express_intent'];
          case 'o3':
            return const ['align_intent'];
          case 'o4':
            return const ['pause_intent'];
          case 'o5':
            return const ['repair_intent'];
          case 'o6':
            return const ['boundary_intent'];
        }
      }
      break;

    case '言い方がきつい':
      if (slot == 'q1') {
        switch (option) {
          case 'o1':
            return const ['hurt_by_partner_tone', 'emotional_pain'];
          case 'o2':
            return const ['speaker_regret', 'repair_need'];
          case 'o3':
            return const ['mutual_escalation', 'conflict_reciprocal'];
          case 'o4':
            return const ['text_misread_risk', 'tone_ambiguity'];
        }
      }
      if (slot == 'q2') {
        switch (option) {
          case 'o1':
            return const ['harsh_wording', 'tone_sensitivity'];
          case 'o2':
            return const ['rejection_pain', 'validation_need'];
          case 'o3':
            return const ['condescension_pain', 'respect_need'];
          case 'o4':
            return const ['dismissed_feeling', 'seriousness_gap'];
          case 'o5':
            return const ['repeated_pattern', 'pattern_fatigue'];
        }
      }
      if (slot == 'goal') {
        switch (option) {
          case 'o1':
            return const ['repair_intent'];
          case 'o2':
            return const ['express_intent'];
          case 'o3':
            return const ['align_intent'];
          case 'o4':
            return const ['boundary_intent'];
          case 'o5':
            return const ['clarify_intent'];
          case 'o6':
            return const ['pause_intent'];
        }
      }
      break;

    case '約束':
      if (slot == 'q1') {
        switch (option) {
          case 'o1':
            return const ['promise_time_contact_issue'];
          case 'o2':
            return const ['promise_meeting_issue'];
          case 'o3':
            return const ['promise_money_issue'];
          case 'o4':
            return const ['promise_future_issue'];
          case 'o5':
            return const ['small_promises_accumulated'];
        }
      }
      if (slot == 'q2') {
        switch (option) {
          case 'o1':
            return const ['partner_broke_promise', 'trust_damage'];
          case 'o2':
            return const ['self_broke_promise', 'repair_need'];
          case 'o3':
            return const ['recognition_gap', 'ambiguity_high'];
          case 'o4':
            return const ['promise_ambiguity', 'expectation_misalignment'];
        }
      }
      if (slot == 'q3') {
        switch (option) {
          case 'o1':
            return const ['single_incident'];
          case 'o2':
            return const ['repeated_pattern', 'issue_accumulation'];
          case 'o3':
            return const ['trust_damage', 'security_threatened'];
          case 'o4':
            return const ['stacked_grievances', 'issue_overlap'];
        }
      }
      if (slot == 'goal') {
        switch (option) {
          case 'o1':
            return const ['clarify_intent'];
          case 'o2':
            return const ['align_intent'];
          case 'o3':
            return const ['express_intent'];
          case 'o4':
            return const ['repair_intent'];
          case 'o5':
            return const ['boundary_intent'];
          case 'o6':
            return const ['pause_intent'];
        }
      }
      break;

    case 'お金':
      if (slot == 'q1') {
        switch (option) {
          case 'o1':
            return const ['money_share_issue', 'fairness_concern'];
          case 'o2':
            return const ['reimbursement_issue', 'request_difficulty'];
          case 'o3':
            return const [
              'gift_expectation_issue',
              'symbolic_value_sensitivity',
            ];
          case 'o4':
            return const ['future_finance_anxiety', 'values_alignment_need'];
          case 'o5':
            return const ['money_issue_other'];
        }
      }
      if (slot == 'q2') {
        switch (option) {
          case 'o1':
            return const ['facts_unclear', 'clarity_needed'];
          case 'o2':
            return const ['request_difficulty', 'avoidance_pressure'];
          case 'o3':
            return const ['fairness_pain', 'resentment_risk'];
          case 'o4':
            return const ['treatment_hurt', 'respect_need'];
          case 'o5':
            return const ['future_finance_anxiety', 'security_concern'];
        }
      }
      if (slot == 'goal') {
        switch (option) {
          case 'o1':
            return const ['clarify_intent'];
          case 'o2':
            return const ['align_intent'];
          case 'o3':
            return const ['express_intent'];
          case 'o4':
            return const ['boundary_intent'];
          case 'o5':
            return const ['repair_intent'];
          case 'o6':
            return const ['pause_intent'];
        }
      }
      break;

    case '距離感':
      if (slot == 'q1') {
        switch (option) {
          case 'o1':
            return const ['partner_feels_distant', 'attachment_anxiety'];
          case 'o2':
            return const ['closeness_pressure', 'boundary_tension'];
          case 'o3':
            return const ['need_space', 'self_regulation_need'];
          case 'o4':
            return const ['meeting_frequency_gap', 'closeness_misalignment'];
          case 'o5':
            return const ['alone_time_gap', 'autonomy_misalignment'];
        }
      }
      if (slot == 'q2') {
        switch (option) {
          case 'o1':
            return const ['abrupt_change', 'uncertainty_high'];
          case 'o2':
            return const ['chronic_pattern', 'issue_accumulation'];
          case 'o3':
            return const ['post_conflict_aftereffect', 'repair_need'];
          case 'o4':
            return const ['no_bad_intent_possible', 'malice_uncertain'];
          case 'o5':
            return const ['self_needs_unclear', 'internal_conflict'];
        }
      }
      if (slot == 'goal') {
        switch (option) {
          case 'o1':
            return const ['align_intent'];
          case 'o2':
            return const ['express_intent'];
          case 'o3':
            return const ['boundary_intent'];
          case 'o4':
            return const ['pause_intent'];
          case 'o5':
            return const ['repair_intent'];
          case 'o6':
            return const ['clarify_intent'];
        }
      }
      break;
  }

  return const [];
}

List<String> _buildLatentSignals(ConsultationDraft draft) {
  final keys = <String>[
    ...draft.themeAnswerKeys,
    if (draft.currentStatusKey != null && draft.currentStatusKey!.isNotEmpty)
      draft.currentStatusKey!,
    if (draft.goalKey != null && draft.goalKey!.isNotEmpty) draft.goalKey!,
  ];

  final seen = <String>{};
  final result = <String>[];

  for (final key in keys) {
    final signals = _latentSignalsForChoiceKey(key);
    for (final signal in signals) {
      if (seen.add(signal)) {
        result.add(signal);
      }
    }
  }

  return result;
}

class EvidenceInputScreen extends StatefulWidget {
  const EvidenceInputScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  State<EvidenceInputScreen> createState() => _EvidenceInputScreenState();
}

class _EvidenceInputScreenState extends State<EvidenceInputScreen> {
  late final TextEditingController _chatController;
  final ImagePicker _picker = ImagePicker();
  final List<_PickedScreenshot> _pickedScreenshots = [];
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _chatController = TextEditingController(text: widget.draft.chatText ?? '');

    for (final shot in widget.draft.screenshots) {
      try {
        _pickedScreenshots.add(
          _PickedScreenshot(
            name: shot.name,
            bytes: base64Decode(shot.bytesBase64),
          ),
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final maxCount = GoMenPlanStorage.isProSync ? 10 : 2;
    final remaining = maxCount - _pickedScreenshots.length;

    if (remaining <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('スクショは最大$maxCount枚までです')));
      return;
    }

    setState(() {
      _isPicking = true;
    });

    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (files.isEmpty) return;

      final existingKeys = _pickedScreenshots
          .map((e) => '${e.name}_${e.bytes.length}')
          .toSet();

      final additions = <_PickedScreenshot>[];
      for (final file in files) {
        if (additions.length >= remaining) break;

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final name = file.name.trim().isEmpty
            ? 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png'
            : file.name.trim();
        final key = '${name}_${bytes.length}';
        if (existingKeys.contains(key)) continue;

        existingKeys.add(key);
        additions.add(_PickedScreenshot(name: name, bytes: bytes));
      }

      if (!mounted || additions.isEmpty) return;

      setState(() {
        _pickedScreenshots.addAll(additions);
      });

      if (files.length > additions.length) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('最大$maxCount枚まで追加できます')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _removeScreenshotAt(int index) {
    setState(() {
      _pickedScreenshots.removeAt(index);
    });
  }

  void _goNext() {
    final chatText = _chatController.text.trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteScreen(
          draft: widget.draft.copyWith(
            chatText: chatText.isEmpty ? null : chatText,
            screenshotNames: _pickedScreenshots.map((e) => e.name).toList(),
            screenshots: _pickedScreenshots
                .map(
                  (e) => DraftScreenshot(
                    name: e.name,
                    bytesBase64: base64Encode(e.bytes),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void _skipEvidence() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteScreen(
          draft: widget.draft.copyWith(
            chatText: null,
            screenshotNames: const [],
            screenshots: const [],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(_PickedScreenshot shot, int index) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6DEE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 0.72,
              child: Image.memory(
                shot.bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            shot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => _removeScreenshotAt(index),
            icon: const Icon(Icons.close, size: 16),
            label: Text('削除'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size.fromHeight(36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasInput =
        _chatController.text.trim().isNotEmpty || _pickedScreenshots.isNotEmpty;

    return ConsultationScaffold(
      currentStep: 7,
      title: 'やり取りがあれば追加してください',
      subtitle: '任意です。なくても相談できます',
      meta: 'Q4: ${widget.draft.goal}',
      child: Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _isPicking ? null : _pickScreenshot,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_isPicking ? '読み込み中...' : 'スクリーンショットを追加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'スクリーンショットを1枚ずつ追加できます。',
                style: TextStyle(
                  fontSize: 13,
                  color: goMenMutedTextColor(context),
                ),
              ),
              const SizedBox(height: 16),
              if (_pickedScreenshots.isNotEmpty) ...[
                Text(
                  '追加したスクリーンショット',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < _pickedScreenshots.length; i++)
                      _buildPreviewCard(_pickedScreenshots[i], i),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              TextField(
                controller: _chatController,
                maxLength: 400,
                inputFormatters: [LengthLimitingTextInputFormatter(400)],
                maxLines: 10,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'テキストで入力する',
                  hintText:
                      '例\n私：昨日なんで返事くれなかったの？\n相手：仕事だったって言ってるじゃん\n私：いつもそうだよね\n相手：もういい',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '個人情報が含まれる場合があります。必要に応じて隠してから追加してください。',
                style: TextStyle(
                  fontSize: 13,
                  color: goMenMutedTextColor(context),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _skipEvidence,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: Text('やり取りなしで進む', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _goNext,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: Text(
                  hasInput ? 'この内容で進む' : '入力して進む',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.draft.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyzeScreen(
          draft: widget.draft.copyWith(
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEvidence =
        (widget.draft.chatText != null && widget.draft.chatText!.isNotEmpty) ||
        widget.draft.screenshotNames.isNotEmpty;

    return ConsultationScaffold(
      currentStep: 8,
      title: '補足があれば教えてください',
      subtitle: '任意です。空欄のままでもそのまま相談できます',
      meta: 'やり取り入力: ${hasEvidence ? 'あり' : 'なし'}',
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _noteController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '補足',
                hintText:
                    '例\n・本当は責めたいわけではない\n・相手は最近かなり疲れている\n・別れたいわけではない\n・前にも同じことで揉めた',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '補足はなくても大丈夫です。',
              style: TextStyle(
                fontSize: 13,
                color: goMenMutedTextColor(context),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('この内容で相談する', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

String _canonicalRelationType(String value) {
  final relation = value.trim();

  if (relation == 'family_inlaw') {
    return 'inlaw';
  }

  if (relation == 'family_parent_child' ||
      relation == 'parent_child' ||
      relation == 'family_other') {
    return 'family';
  }

  return relation;
}

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  String? errorText;

  @override
  void initState() {
    super.initState();
    _sendConsultation();
  }

  Future<void> _sendConsultation() async {
    final canUseAi = await DailyUsageStorage.canUseAi();
    if (!canUseAi) {
      if (!mounted) return;
      setState(() {
        errorText = '無料版のAI相談は1日3回までです。明日になるとまた使えます。';
      });
      return;
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:8000/consult/sessions');
      final profile = widget.draft.selectedProfile;
      final recentPatternSummary = profile == null
          ? null
          : await LocalHistoryStorage.buildRecentPatternSummary(profile.id);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'relation_type': _canonicalRelationType(widget.draft.relationType ?? ''),
          'relation_detail_labels': widget.draft.relationDetails,
          'theme': widget.draft.theme,
          'theme_details': widget.draft.themeAnswers,
          'theme_detail_keys': widget.draft.themeAnswerKeys,
          'current_status': widget.draft.currentStatus,
          'current_status_key': widget.draft.currentStatusKey,
          'emotion_level': widget.draft.emotionLevel,
          'goal': widget.draft.goal,
          'goal_key': widget.draft.goalKey,
          'latent_signals': _buildLatentSignals(widget.draft),
          'chat_text': widget.draft.chatText,
          'note': widget.draft.note,
          'profile_context': profile?.toProfileContext(),
          'recent_pattern_summary': recentPatternSummary,
          'screenshots_base64': widget.draft.screenshots
              .map((e) => e.bytesBase64)
              .toList(),
          'upload_ids': <String>[],
        }),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          errorText = 'APIエラー: ${response.statusCode}\n${response.body}';
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = ConsultationResult.fromJson(decoded);

      final bestText = result.replyOptions.isNotEmpty
          ? result.replyOptions.first.body
          : '';

      await DailyUsageStorage.recordSuccess();
      await LocalHistoryStorage.saveItem(
        SavedResultItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: 'consult',
          title: '相談 / ${widget.draft.theme ?? 'その他'}',
          subtitle: result.sendTimingLabel,
          bestText: bestText,
          createdAt: DateTime.now().toIso8601String(),
          profileId: profile?.id,
          profileName: profile?.displayName,
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(draft: widget.draft, result: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorText = '接続エラー: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorText != null) {
      return ErrorScreen(
        title: '相談結果',
        errorText: errorText!,
        onRetry: _sendConsultation,
      );
    }

    return const LoadingScreen(
      title: 'Go-men が整理しています',
      lines: ['相手の受け取り方と、今の動き方を整理しています', '悪化しにくい返し方を考えています'],
    );
  }
}

class PrecheckCoupleSelfGenderScreen extends StatelessWidget {
  const PrecheckCoupleSelfGenderScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'ここが細かいほど、文の整え方が自然になります',
      question: 'あなたは？',
      options: const ['男性', '女性', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckCouplePartnerGenderScreen(
              draft: draft.copyWith(relationDetails: ['自分: $value']),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckCouplePartnerGenderScreen extends StatelessWidget {
  const PrecheckCouplePartnerGenderScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'ここが細かいほど、文の整え方が自然になります',
      question: '相手は？',
      options: const ['男性', '女性', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFriendContextScreen extends StatelessWidget {
  const PrecheckFriendContextScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '友人の種類で、言い方の自然さが変わります',
      question: 'どこでの友人ですか？',
      options: const ['学校', '職場', '地元', '趣味コミュニティ', 'そのほか'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(relationDetails: ['$valueの友人']),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFamilyTypeScreen extends StatelessWidget {
  const PrecheckFamilyTypeScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '家族の中の関係で、整えるべきトーンが変わります',
      question: '家族の中ではどの関係ですか？',
      options: const ['親子', '兄弟姉妹', '義家族', 'そのほか'],
      onSelected: (context, value) {
        if (value == '親子') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrecheckFamilyParentRoleScreen(
                draft: draft.copyWith(
                  relationType: 'family_parent_child',
                  relationLabel: '家族 / 親子',
                  relationDetails: ['親子'],
                ),
              ),
            ),
          );
          return;
        }

        if (value == '兄弟姉妹') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrecheckFamilySiblingScreen(
                draft: draft.copyWith(
                  relationType: 'family_sibling',
                  relationLabel: '家族 / 兄弟姉妹',
                  relationDetails: ['兄弟姉妹'],
                ),
              ),
            ),
          );
          return;
        }

        if (value == '義家族') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrecheckFamilyInlawScreen(
                draft: draft.copyWith(
                  relationType: 'family_inlaw',
                  relationLabel: '家族 / 義家族',
                  relationDetails: ['義家族'],
                ),
              ),
            ),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(
                relationType: 'family_other',
                relationLabel: '家族 / その他',
                relationDetails: ['家族 / その他'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFamilyParentRoleScreen extends StatelessWidget {
  const PrecheckFamilyParentRoleScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '親子でも立場で整え方が変わります',
      question: 'あなたはどちらですか？',
      options: const ['親', '子'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckFamilyParentGenderScreen(
              draft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '自分: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFamilyParentGenderScreen extends StatelessWidget {
  const PrecheckFamilyParentGenderScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: 'ここも言葉選びに影響します',
      question: '親は？',
      options: const ['母', '父', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '親: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFamilySiblingScreen extends StatelessWidget {
  const PrecheckFamilySiblingScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '兄姉か弟妹かでも距離感が変わります',
      question: '相手は？',
      options: const ['兄', '姉', '弟', '妹', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckFamilyInlawScreen extends StatelessWidget {
  const PrecheckFamilyInlawScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  Widget build(BuildContext context) {
    return RelationSingleChoiceScreen(
      title: 'もう少し関係を教えてください',
      subtitle: '義家族の中でも相手との距離感が変わります',
      question: '相手は？',
      options: const ['義母', '義父', '義兄弟姉妹', 'そのほか', '答えない'],
      onSelected: (context, value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrecheckInputScreen(
              initialDraft: draft.copyWith(
                relationDetails: [...draft.relationDetails, '相手: $value'],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecheckInputScreen extends StatefulWidget {
  const PrecheckInputScreen({
    super.key,
    this.initialProfile,
    this.initialDraft,
  });

  final RelationshipProfile? initialProfile;
  final PrecheckDraft? initialDraft;

  @override
  State<PrecheckInputScreen> createState() => _PrecheckInputScreenState();
}

class _PrecheckInputScreenState extends State<PrecheckInputScreen> {
  String? _relationType;
  String? _relationLabel;
  List<String> _relationDetails = [];
  late final TextEditingController _draftController;
  late final TextEditingController _contextController;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController(
      text: widget.initialDraft?.draftMessage ?? '',
    );
    _contextController = TextEditingController(
      text: widget.initialDraft?.optionalContextText ?? '',
    );
    _relationType =
        widget.initialDraft?.relationType ??
        widget.initialProfile?.relationType;
    _relationLabel =
        widget.initialDraft?.relationLabel ??
        widget.initialProfile?.relationLabel;
    _relationDetails = List<String>.from(
      (widget.initialDraft?.relationDetails.isNotEmpty ?? false)
          ? widget.initialDraft!.relationDetails
          : (widget.initialProfile?.relationDetails ?? const <String>[]),
    );
  }

  @override
  void dispose() {
    _draftController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  void _selectRelation(String relationType, String label) {
    late final Widget nextScreen;

    switch (relationType) {
      case 'couple':
        nextScreen = PrecheckCoupleSelfGenderScreen(
          draft: PrecheckDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
            selectedProfile: widget.initialProfile,
          ),
        );
        break;
      case 'friend':
        nextScreen = PrecheckFriendContextScreen(
          draft: PrecheckDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
            selectedProfile: widget.initialProfile,
          ),
        );
        break;
      case 'family':
        nextScreen = PrecheckFamilyTypeScreen(
          draft: PrecheckDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
            selectedProfile: widget.initialProfile,
          ),
        );
        break;
      case 'other':
      default:
        nextScreen = PrecheckInputScreen(
          initialDraft: PrecheckDraft(
            relationType: relationType,
            relationLabel: label,
            relationDetails: const [],
            selectedProfile: widget.initialProfile,
          ),
        );
        break;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => nextScreen));
  }

  void _submit() {
    final draftMessage = _draftController.text.trim();
    final contextText = _contextController.text.trim();
    final profile =
        widget.initialDraft?.selectedProfile ?? widget.initialProfile;

    if (_relationType == null || _relationLabel == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('相手との関係を選んでください')));
      return;
    }

    if (draftMessage.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('チェックしたい文を入力してください')));
      return;
    }

    final draft = PrecheckDraft(
      relationType: _relationType,
      relationLabel: _relationLabel,
      relationDetails: _relationDetails,
      draftMessage: draftMessage,
      optionalContextText: contextText.isEmpty ? null : contextText,
      selectedProfile: profile,
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PrecheckAnalyzeScreen(draft: draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        widget.initialDraft?.selectedProfile ?? widget.initialProfile;

    if (_relationType == null || _relationLabel == null) {
      return ConsultationScaffold(
        currentStep: 1,
        title: '相手との関係を教えてください',
        subtitle: '送る前チェックでも、関係性で言い換え方が変わります',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => _selectRelation('couple', '恋人・パートナー'),
              style: elevatedChoiceStyle,
              child: Text('恋人・パートナー', style: choiceTextStyle),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _selectRelation('friend', '友人'),
              style: elevatedChoiceStyle,
              child: Text('友人', style: choiceTextStyle),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _selectRelation('family', '家族'),
              style: elevatedChoiceStyle,
              child: Text('家族', style: choiceTextStyle),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _selectRelation('other', 'その他'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('その他', style: choiceTextStyle),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('送る前にチェックする')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            if (profile != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '適用中のプロフィール',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      buildProfileTypeSummaryWidget(profile),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '読み取った関係性',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relationLabel ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_relationDetails.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ..._relationDetails.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('・$item'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '送ろうとしている文',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _draftController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '下書き',
                hintText: '例\nなんで昨日返事くれなかったの？こっちはずっと待ってたんだけど。',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '補足（任意）',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contextController,
              maxLength: 400,
              inputFormatters: [LengthLimitingTextInputFormatter(400)],
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '補足',
                hintText: '例\n責めたいわけではないけど、不安で強い言い方になってしまった。',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '相手にどう聞こえるか、今送ってよいか、ベストな修正文を出します。',
              style: TextStyle(
                fontSize: 13,
                color: goMenMutedTextColor(context),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('この文をチェックする', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class PrecheckAnalyzeScreen extends StatefulWidget {
  const PrecheckAnalyzeScreen({super.key, required this.draft});

  final PrecheckDraft draft;

  @override
  State<PrecheckAnalyzeScreen> createState() => _PrecheckAnalyzeScreenState();
}

class _PrecheckAnalyzeScreenState extends State<PrecheckAnalyzeScreen> {
  String? errorText;

  @override
  void initState() {
    super.initState();
    _sendPrecheck();
  }

  Future<void> _sendPrecheck() async {
    final canUseAi = await DailyUsageStorage.canUseAi();
    if (!canUseAi) {
      if (!mounted) return;
      setState(() {
        errorText = '無料版のAIチェックは1日3回までです。明日になるとまた使えます。';
      });
      return;
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:8000/precheck');
      final profile = widget.draft.selectedProfile;
      final recentPatternSummary = profile == null
          ? null
          : await LocalHistoryStorage.buildRecentPatternSummary(profile.id);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'relation_type': _canonicalRelationType(widget.draft.relationType ?? ''),
          'relation_detail_labels': widget.draft.relationDetails,
          'draft_message': widget.draft.draftMessage,
          'optional_context_text': widget.draft.optionalContextText,
          'profile_context': profile?.toProfileContext(),
          'recent_pattern_summary': recentPatternSummary,
          'optional_context_upload_ids': <String>[],
        }),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          errorText = 'APIエラー: ${response.statusCode}\n${response.body}';
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = PrecheckResult.fromJson(decoded);

      await DailyUsageStorage.recordSuccess();
      await LocalHistoryStorage.saveItem(
        SavedResultItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: 'precheck',
          title: '送信前チェック / ${widget.draft.relationLabel ?? '未設定'}',
          subtitle: result.label,
          bestText: result.softenedMessage,
          createdAt: DateTime.now().toIso8601String(),
          profileId: profile?.id,
          profileName: profile?.displayName,
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              PrecheckResultScreen(draft: widget.draft, result: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorText = '接続エラー: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorText != null) {
      return ErrorScreen(
        title: '送信前チェック',
        errorText: errorText!,
        onRetry: _sendPrecheck,
      );
    }

    return const LoadingScreen(
      title: '送る前に整えています',
      lines: ['相手にどう聞こえるかを見ています', '今送ってよいかと、ベストな修正文を考えています'],
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.draft, required this.result});

  final ConsultationDraft draft;
  final ConsultationResult result;

  @override
  Widget build(BuildContext context) {
    final bestReply = result.replyOptions.isNotEmpty
        ? result.replyOptions.first
        : null;
    final otherReplies = result.replyOptions.length > 1
        ? result.replyOptions.sublist(1)
        : <ReplyOption>[];

    return Scaffold(
      appBar: AppBar(title: Text('相談結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            if (draft.selectedProfile != null)
              _ResultCard(
                title: '適用したプロフィール',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${draft.selectedProfile!.displayName} / ${draft.selectedProfile!.relationLabel}',
                    ),
                    const SizedBox(height: 12),
                    buildProfileTypeSummaryWidget(draft.selectedProfile!),
                  ],
                ),
              ),
            if (draft.relationLabel != null || draft.relationDetails.isNotEmpty)
              _ResultCard(
                title: '読み取った関係性',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (draft.relationLabel != null)
                      Text(
                        draft.relationLabel!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (draft.relationDetails.isNotEmpty) ...[
                      if (draft.relationLabel != null)
                        const SizedBox(height: 10),
                      ...draft.relationDetails.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('・$item'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            _DecisionSummaryCard(
              eyebrow: '今のおすすめ',
              headline: result.sendTimingLabel,
              body: result.sendTimingReason,
            ),
            if (bestReply != null)
              _HeroReplyCard(
                title: bestReply.title,
                body: bestReply.body,
                buttonLabel: 'この返信をコピー',
                helperText: 'そのまま送れる形で、まず一番通りやすい案です。',
              ),
            if (otherReplies.isNotEmpty)
              _ResultCard(
                title: 'その他には',
                child: Column(
                  children: otherReplies
                      .map((option) => _ReplyOptionCard(option: option))
                      .toList(),
                ),
              ),
            _ResultCard(
              title: '相手にどう聞こえたか',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.heardAsInterpretations
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('・$item'),
                      ),
                    )
                    .toList(),
              ),
            ),
            _ResultCard(
              title: '相手の気持ちの見立て',
              child: Text(result.partnerFeelingEstimate),
            ),
            _ResultCard(
              title: '今は避けたい言い方',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.avoidPhrases
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('・$item'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PrecheckInputScreen(
                      initialProfile: draft.selectedProfile,
                      initialDraft: PrecheckDraft(
                        relationType: draft.relationType,
                        relationLabel: draft.relationLabel,
                        relationDetails: draft.relationDetails,
                        selectedProfile: draft.selectedProfile,
                      ),
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('自分の文をチェックする', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('ホームに戻る', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

class PrecheckResultScreen extends StatelessWidget {
  const PrecheckResultScreen({
    super.key,
    required this.draft,
    required this.result,
  });

  final PrecheckDraft draft;
  final PrecheckResult result;

  @override
  Widget build(BuildContext context) {
    final alternatives = result.revisedMessageOptions.length > 1
        ? result.revisedMessageOptions.sublist(1)
        : <String>[];

    return Scaffold(
      appBar: AppBar(title: Text('送信前チェック結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            if (draft.selectedProfile != null)
              _ResultCard(
                title: '適用したプロフィール',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${draft.selectedProfile!.displayName} / ${draft.selectedProfile!.relationLabel}',
                    ),
                    const SizedBox(height: 12),
                    buildProfileTypeSummaryWidget(draft.selectedProfile!),
                  ],
                ),
              ),
            if (draft.relationLabel != null || draft.relationDetails.isNotEmpty)
              _ResultCard(
                title: '読み取った関係性',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (draft.relationLabel != null)
                      Text(
                        draft.relationLabel!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (draft.relationDetails.isNotEmpty) ...[
                      if (draft.relationLabel != null)
                        const SizedBox(height: 10),
                      ...draft.relationDetails.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('・$item'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            _DecisionSummaryCard(
              eyebrow: '今送ってよいか',
              headline: result.label,
              body: result.reason,
            ),
            _HeroReplyCard(
              title: 'まずこれがベスト',
              body: result.softenedMessage,
              buttonLabel: 'この文をコピー',
              helperText: '送るならまずこの形。やわらかさと伝わりやすさのバランスを優先しています。',
            ),
            if (alternatives.isNotEmpty)
              _ResultCard(
                title: 'その他には',
                child: Column(
                  children: alternatives
                      .map((text) => _SimpleReplyCard(text: text))
                      .toList(),
                ),
              ),
            _ResultCard(
              title: '今のままだと誤解されやすい点',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.riskPoints
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('・$item'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            _ResultCard(
              title: '相手にどう聞こえるか',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.heardAsInterpretations
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('・$item'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            _ResultCard(
              title: '今は避けたい言い方',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.avoidPhrases
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('・$item'),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThemeSelectionScreen(
                      draft: ConsultationDraft(
                        relationType: draft.relationType,
                        relationLabel: draft.relationLabel,
                        selectedProfile: draft.selectedProfile,
                      ),
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('相談モードでも見る', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('ホームに戻る', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> setDebugPlanAndNormalizeTheme(
  BuildContext context,
  GoMenPlan plan,
) async {
  await GoMenPlanStorage.setPlan(plan);

  final currentTheme = GoMenThemeStorage.notifier.value;
  final currentSpec = goMenThemeSpecFor(currentTheme);

  if (plan == GoMenPlan.free && currentSpec.isPremium) {
    await GoMenThemeStorage.setTheme(GoMenThemeMode.ivory);
  } else {
    await GoMenThemeStorage.setTheme(currentTheme);
  }

  if (!context.mounted) return;

  final label = plan == GoMenPlan.pro ? 'Go-men Pro' : '無料版';
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('プランを $label に切り替えました')));
}

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  Future<void> _handleThemeTap(
    BuildContext context,
    GoMenThemeMode mode,
  ) async {
    final spec = goMenThemeSpecFor(mode);

    if (!GoMenThemeStorage.canUse(mode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${spec.label} テーマは Go-men Pro で利用できます')),
      );
      return;
    }

    await GoMenThemeStorage.setTheme(mode);

    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${spec.label} テーマに変更しました')));
  }

  @override
  Widget build(BuildContext context) {
    final themes = [
      goMenThemeSpecFor(GoMenThemeMode.ivory),
      goMenThemeSpecFor(GoMenThemeMode.gold),
      goMenThemeSpecFor(GoMenThemeMode.pink),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<GoMenThemeMode>(
                  valueListenable: GoMenThemeStorage.notifier,
                  builder: (context, currentMode, _) {
                    final currentSpec = goMenThemeSpecFor(currentMode);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'テーマ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ivory は通常版、Gold / Pink は Go-men Pro で利用できます',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                currentSpec.backgroundTop,
                                currentSpec.backgroundBottom,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: currentSpec.accentColor.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  currentSpec.label.substring(0, 1),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: currentSpec.previewTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '現在のテーマ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      currentSpec.label,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: currentSpec.previewTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...themes.map(
                          (theme) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ThemeChoiceCard(
                              spec: theme,
                              isSelected: currentMode == theme.mode,
                              isLocked:
                                  theme.isPremium &&
                                  !GoMenPlanStorage.isProSync,
                              onTap: () => _handleThemeTap(context, theme.mode),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SettingsNavCard(
              icon: Icons.privacy_tip_outlined,
              title: 'プライバシーポリシー',
              subtitle: 'アプリ内で確認する',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _SettingsNavCard(
              icon: Icons.description_outlined,
              title: '利用規約',
              subtitle: '免責事項を含む',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TermsAndDisclaimerScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _SettingsNavCard(
              icon: Icons.workspace_premium_outlined,
              title: 'Go-men Pro',
              subtitle: '無料版 / 有料版の違い',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProPlanScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _SettingsNavCard(
              icon: Icons.mail_outline,
              title: 'お問い合わせ',
              subtitle: '連絡先を確認する',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ContactScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<GoMenPlan>(
                  valueListenable: GoMenPlanStorage.notifier,
                  builder: (context, currentPlan, _) {
                    final isPro = currentPlan == GoMenPlan.pro;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPro ? '現在のプラン: Go-men Pro' : '現在のプラン: 無料版',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isPro
                              ? '・プロフィール保存: 制限なし'
                              : '・プロフィール保存: ${PlanLimits.freeProfiles}件まで',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isPro
                              ? '・相談結果の保存: 制限なし'
                              : '・相談結果の保存: 直近${PlanLimits.freeSavedResults}件まで',
                        ),
                        const SizedBox(height: 6),
                        Text('・相談 / 送信前チェックは利用可能'),
                        const SizedBox(height: 6),
                        Text(
                          isPro
                              ? '・テーマ: Ivory / Gold / Pink を利用可能'
                              : '・テーマ: Ivory を利用可能',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isPro
                              ? '・今後の相性診断など Pro 機能を解放予定'
                              : '・Gold / Pink や相性診断は Go-men Pro で解放',
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Text(
                          '開発用プラン切り替え',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'App Store 課金導入前の確認用です',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isPro
                                    ? () => setDebugPlanAndNormalizeTheme(
                                        context,
                                        GoMenPlan.free,
                                      )
                                    : null,
                                child: Text('無料版にする'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isPro
                                    ? null
                                    : () => setDebugPlanAndNormalizeTheme(
                                        context,
                                        GoMenPlan.pro,
                                      ),
                                child: Text('Pro にする'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavCard extends StatelessWidget {
  const _SettingsNavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ThemeChoiceCard extends StatelessWidget {
  const _ThemeChoiceCard({
    required this.spec,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  final GoMenThemeSpec spec;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [spec.backgroundTop, spec.backgroundBottom],
                  ),
                  border: Border.all(
                    color: spec.accentColor.withValues(alpha: 0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Go',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: spec.previewTextColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          spec.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (spec.isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: spec.accentColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: spec.accentColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spec.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.green)
              else if (isLocked)
                Icon(Icons.lock_outline, color: spec.accentColor)
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      title: 'プライバシーポリシー',
      children: const [
        _LegalSection(
          title: '1. 取得する情報',
          body:
              'Go-men は、相談内容、送信前チェックの文章、関係性プロフィール、保存した結果など、ユーザーが入力した情報を取り扱います。',
        ),
        _LegalSection(
          title: '2. 利用目的',
          body: '取得した情報は、返信候補の生成、送信前チェック、プロフィールに応じた提案、履歴表示などの機能提供のために使用します。',
        ),
        _LegalSection(
          title: '3. 外部サービスへの送信',
          body:
              'AIによる分析を行うため、入力内容の一部がサーバー経由で外部AIサービスに送信される場合があります。個人情報や極めて機微な情報は、必要最小限にとどめてください。',
        ),
        _LegalSection(
          title: '4. 保存について',
          body:
              '保存機能をオンにした場合、相談結果や送信前チェック結果は端末内または提供環境内に保持されることがあります。共有端末では取り扱いに注意してください。',
        ),
        _LegalSection(
          title: '5. お問い合わせ',
          body: '本ポリシーに関するお問い合わせは、設定内のお問い合わせ先をご確認ください。',
        ),
      ],
    );
  }
}

class TermsAndDisclaimerScreen extends StatelessWidget {
  const TermsAndDisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      title: '利用規約',
      children: const [
        _LegalSection(
          title: '1. 本サービスについて',
          body:
              'Go-men は、コミュニケーションの整理や返信候補の提案を補助するアプリです。診断、医療、法律、緊急対応などを目的としたものではありません。',
        ),
        _LegalSection(
          title: '2. 保証について',
          body:
              '本サービスは、返信内容の正確性、完全性、相手との関係改善、トラブル回避を保証するものではありません。最終判断はユーザー自身の責任で行ってください。',
        ),
        _LegalSection(
          title: '3. 禁止事項',
          body: '違法行為、嫌がらせ、脅迫、なりすまし、第三者の権利侵害、公序良俗に反する目的での利用を禁止します。',
        ),
        _LegalSection(
          title: '4. 免責',
          body: '本サービスの利用により生じた直接的または間接的な損害について、運営者は責任を負いません。',
        ),
        _LegalSection(
          title: '5. 変更',
          body: '本規約は、必要に応じて予告なく変更されることがあります。最新版はアプリ内表示を優先します。',
        ),
      ],
    );
  }
}

Widget buildProfileTypeSummaryWidget(RelationshipProfile profile) {
  final lines = activeProfileTypeLines(profile);
  if (lines.isEmpty) {
    return Text(
      profile.relationSummaryLabel,
      style: const TextStyle(height: 1.4),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        profile.relationSummaryLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      ...lines.map(
        (line) =>
            Text(line, style: const TextStyle(fontSize: 12, height: 1.35)),
      ),
    ],
  );
}

class CompatibilityScoreResult {
  const CompatibilityScoreResult({
    required this.score,
    required this.label,
    required this.summary,
    required this.positivePoints,
    required this.riskPoints,
    required this.nextActions,
  });

  final int score;
  final String label;
  final String summary;
  final List<String> positivePoints;
  final List<String> riskPoints;
  final List<String> nextActions;

  factory CompatibilityScoreResult.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    List<String> readList(String key) {
      final raw = data[key];
      if (raw is! List) return <String>[];
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return CompatibilityScoreResult(
      score: ((data['score'] ?? 78) as num).round(),
      label: (data['label'] ?? '相性は悪くない').toString(),
      summary: (data['summary'] ?? '関係の土台はあるので、すれ違いやすい点を先に意識すると安定しやすいです。')
          .toString(),
      positivePoints: readList('positive_points'),
      riskPoints: readList('risk_points'),
      nextActions: readList('next_actions'),
    );
  }
}

class CompatibilityScreen extends StatefulWidget {
  const CompatibilityScreen({super.key, required this.profile});

  final RelationshipProfile profile;

  @override
  State<CompatibilityScreen> createState() => _CompatibilityScreenState();
}

class _CompatibilityScreenState extends State<CompatibilityScreen> {
  Widget buildProfileTypeSummaryWidget(RelationshipProfile profile) {
    final lines = activeProfileTypeLines(profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildProfileTypeSummaryWidget(profile),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  final TextEditingController _noteController = TextEditingController();

  bool _isLoading = false;
  String? _errorText;
  CompatibilityScoreResult? _result;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _runCompatibilityScore() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final recentPatternSummary =
          await LocalHistoryStorage.buildRecentPatternSummary(
            widget.profile.id,
          );

      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/compatibility/score'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'relation_type': widget.profile.relationType,
          'relation_detail_labels': widget.profile.relationDetails,
          'profile_context': widget.profile.toProfileContext(),
          'recent_pattern_summary': recentPatternSummary,
          'optional_note': _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = '相性採点の取得に失敗しました';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
            detail = decoded['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('レスポンス形式が不正です');
      }

      final result = CompatibilityScoreResult.fromJson(decoded);

      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '相性採点に失敗しました。\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildBulletList(List<String> items, IconData icon) {
    if (items.isEmpty) {
      return Text(
        'まだ結果がありません',
        style: TextStyle(color: goMenMutedTextColor(context)),
      );
    }

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _buildBulletList(items, icon),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('相性採点')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!GoMenPlanStorage.isProSync) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '相性採点は Go-men Pro 限定です。\n'
                        'Pro にすると、プロフィールと保存履歴を反映した相性スコアを利用できます。',
                        style: TextStyle(
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProPlanScreen(),
                            ),
                          );
                        },
                        child: const Text('Proプランを見る'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '対象プロフィール',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: goMenMutedTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.profile.displayName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.relationSummaryLabel,
                      style: TextStyle(color: goMenMutedTextColor(context)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '任意メモ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最近の雰囲気や気になることを補足すると、採点の精度が少し上がります。',
                      style: TextStyle(
                        fontSize: 13,
                        color: goMenMutedTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '最近のすれ違い、気になっていること、うまくいっていない点など',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (!GoMenPlanStorage.isProSync || _isLoading)
                            ? null
                            : _runCompatibilityScore,
                        child: Text(
                          _isLoading
                              ? '採点中...'
                              : (result == null
                                    ? '相性を採点する（Pro限定）'
                                    : 'もう一度採点する'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        '相性スコア',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: goMenMutedTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${result.score}点',
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.summary,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.55,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section(
                context,
                'うまくいきやすい点',
                result.positivePoints,
                Icons.favorite_border,
              ),
              const SizedBox(height: 12),
              _section(
                context,
                'すれ違いやすい点',
                result.riskPoints,
                Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 12),
              _section(
                context,
                '次に意識すること',
                result.nextActions,
                Icons.flag_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileManagerScreen extends StatefulWidget {
  const ProfileManagerScreen({super.key});

  @override
  State<ProfileManagerScreen> createState() => _ProfileManagerScreenState();
}

class _ProfileManagerScreenState extends State<ProfileManagerScreen> {
  bool _loading = true;
  List<RelationshipProfile> _profiles = const [];
  String? _activeProfileId;
  GoMenPlan _plan = GoMenPlan.free;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final profiles = await ProfileStorage.loadProfiles();
    final activeProfileId = await ProfileStorage.loadActiveProfileId();
    final plan = await GoMenPlanStorage.loadPlan();

    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _activeProfileId = activeProfileId;
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _setActive(RelationshipProfile profile) async {
    await ProfileStorage.setActiveProfileId(profile.id);
    await _reload();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${profile.displayName} を使用中にしました')));
  }

  Future<void> _openEditor([RelationshipProfile? profile]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: profile)),
    );
    await _reload();
  }

  Future<void> _delete(RelationshipProfile profile) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('プロフィールを削除しますか？'),
              content: Text('${profile.displayName} のプロフィールを削除します。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('削除する'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;

    await ProfileStorage.deleteProfile(profile.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final maxProfiles = PlanLimits.profilesForPlan(_plan);
    final canAddMore = _profiles.length < maxProfiles;

    return Scaffold(
      appBar: AppBar(title: const Text('関係性プロフィール')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _plan == GoMenPlan.pro ? 'Go-men Pro' : '無料版',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('プロフィール数: ${_profiles.length} / $maxProfiles'),
                          const SizedBox(height: 6),
                          Text(
                            _plan == GoMenPlan.pro
                                ? '複数プロフィールを保存でき、相談前に相手を選べます。'
                                : '無料版では1件までです。Go-men Pro で複数プロフィールを使えます。',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_profiles.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('まだプロフィールはありません。まず1件作成してください。'),
                      ),
                    ),
                  ..._profiles.map(
                    (profile) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      profile.displayName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (profile.id == _activeProfileId)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '使用中',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              buildProfileTypeSummaryWidget(profile),
                              if (profile.notes.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  profile.notes.trim(),
                                  style: TextStyle(
                                    color: goMenMutedTextColor(context),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: () => _setActive(profile),
                                    child: const Text('この相手を使う'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _openEditor(profile),
                                    child: const Text('編集'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _delete(profile),
                                    child: const Text('削除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: canAddMore
                        ? () => _openEditor()
                        : () {
                            final message = _plan == GoMenPlan.pro
                                ? 'これ以上プロフィールを増やせません。不要なプロフィールを整理してください。'
                                : '無料版ではプロフィールは1件までです。Go-men Pro で複数プロフィールを使えます。';
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: Text(canAddMore ? 'プロフィールを追加する' : 'プロフィール上限に達しています'),
                  ),
                ],
              ),
      ),
    );
  }
}

class ProPlanScreen extends StatefulWidget {
  const ProPlanScreen({super.key});

  @override
  State<ProPlanScreen> createState() => _ProPlanScreenState();
}

class _ProPlanScreenState extends State<ProPlanScreen> {
  late final GoMenBillingService _billing;

  @override
  void initState() {
    super.initState();
    _billing = GoMenBillingService(
      onEntitlementChanged: (isPro) async {
        await GoMenPlanStorage.setPlan(isPro ? GoMenPlan.pro : GoMenPlan.free);
        if (!mounted) return;
        setState(() {});
      },
    );
    _billing.init();
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Go-men Pro')),
      body: SafeArea(
        child: ValueListenableBuilder<GoMenPlan>(
          valueListenable: GoMenPlanStorage.notifier,
          builder: (context, plan, _) {
            final isPro = plan == GoMenPlan.pro;

            return AnimatedBuilder(
              animation: _billing,
              builder: (context, _) {
                final product = _billing.product;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              isPro
                                  ? '現在 Go-men Pro を利用中です'
                                  : 'Go-men Pro にアップグレード',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isPro
                                  ? '購入状態はアプリ内で反映済みです。復元や再取得もこの画面から実行できます。'
                                  : '本物の App Store 購入導線をここから使います。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: goMenMutedTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Go-men Pro でできること',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _featureRow('相性採点（100点満点）'),
                            _featureRow('複数プロフィール'),
                            _featureRow('保存件数の拡張 / 実質無制限'),
                            _featureRow('相手ごとの履歴整理'),
                            _featureRow('いつものすれ違いパターン分析'),
                            _featureRow('深い文脈反映'),
                            _featureRow('Gold / Pink テーマ'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '現在のプラン: ${PlanLimits.labelForPlan(plan)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (product != null) ...[
                              Text(
                                '商品: ${product.title}',
                                style: const TextStyle(fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '価格: ${product.price}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: goMenMutedTextColor(context),
                                ),
                              ),
                            ] else ...[
                              Text(
                                '商品情報を読み込み中です。',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: goMenMutedTextColor(context),
                                ),
                              ),
                            ],
                            if (_billing.errorText != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _billing.errorText!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.red,
                                  height: 1.5,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            ElevatedButton(
                              onPressed:
                                  (isPro ||
                                      _billing.isPurchasePending ||
                                      product == null)
                                  ? null
                                  : () {
                                      _billing.buyPro();
                                    },
                              child: Text(
                                isPro
                                    ? 'Pro有効化済み'
                                    : _billing.isPurchasePending
                                    ? '購入処理中...'
                                    : 'App StoreでProを購入',
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: _billing.isPurchasePending
                                  ? null
                                  : () {
                                      _billing.restore();
                                    },
                              child: const Text('購入を復元'),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _billing.isPurchasePending
                                  ? null
                                  : () {
                                      _billing.reload();
                                    },
                              child: const Text('商品情報を再取得'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '※ 現段階では購入成功時にアプリ内の Pro 状態を反映します。次の段階で server 側の購入検証をつなぎます。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: goMenMutedTextColor(context),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const contactEmail = 'gomen.mendly@gmail.com';

    return Scaffold(
      appBar: AppBar(title: Text('お問い合わせ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'お問い合わせ先',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(contactEmail, style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          copyText(context, contactEmail, label: '連絡先をコピーしました'),
                      child: Text('連絡先をコピー'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'お問い合わせが必要な場合は、上記メールアドレスまでご連絡ください。',
                  style: TextStyle(height: 1.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: children),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(height: 1.6, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class SavedResultsScreen extends StatefulWidget {
  const SavedResultsScreen({super.key, this.initialOnlyCurrentProfile = false});

  final bool initialOnlyCurrentProfile;

  @override
  State<SavedResultsScreen> createState() => _SavedResultsScreenState();
}

class _SavedResultsScreenState extends State<SavedResultsScreen> {
  late Future<SavedResultsViewData> _viewFuture;
  late bool _onlyCurrentProfile;
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _onlyCurrentProfile = widget.initialOnlyCurrentProfile;
    _viewFuture = _loadViewData();
  }

  Future<SavedResultsViewData> _loadViewData() async {
    final profile = await ProfileStorage.loadProfile();
    final items = await LocalHistoryStorage.loadItems();
    return SavedResultsViewData(activeProfile: profile, items: items);
  }

  void _reload() {
    setState(() {
      _viewFuture = _loadViewData();
    });
  }

  Future<void> _clearAll() async {
    await LocalHistoryStorage.clear();
    _reload();
  }

  List<SavedResultItem> _applyFilters(
    List<SavedResultItem> items,
    RelationshipProfile? profile,
  ) {
    var result = items;

    if (_onlyCurrentProfile && profile != null) {
      result = result.where((item) => item.profileId == profile.id).toList();
    }

    if (_typeFilter == 'consult') {
      result = result.where((item) => item.type == 'consult').toList();
    } else if (_typeFilter == 'precheck') {
      result = result.where((item) => item.type == 'precheck').toList();
    }

    return result;
  }

  Widget _filterChip({required String value, required String label}) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _typeFilter = value;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('保存した結果'),
        actions: [
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
            tooltip: '全部消す',
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<SavedResultsViewData>(
          future: _viewFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final profile = data.activeProfile;
            final allItems = data.items;
            final filteredItems = _applyFilters(allItems, profile);
            final usageProgress =
                allItems.length / LocalHistoryStorage.maxItems;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '保存 ${allItems.length} / ${LocalHistoryStorage.maxItems}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: usageProgress.clamp(0.0, 1.0),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '無料版では直近${PlanLimits.freeSavedResults}件まで保存されます。',
                            style: TextStyle(color: Colors.black54),
                          ),
                          if (allItems.length >=
                              LocalHistoryStorage.maxItems) ...[
                            const SizedBox(height: 8),
                            Text(
                              '次の保存で古い結果から入れ替わります。',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _filterChip(value: 'all', label: 'すべて'),
                              _filterChip(value: 'consult', label: '相談'),
                              _filterChip(value: 'precheck', label: '送信前チェック'),
                            ],
                          ),
                          if (profile != null) ...[
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${profile.displayName} との結果だけ表示'),
                              subtitle: Text('アクティブなプロフィールに紐づく保存結果だけ見ます'),
                              value: _onlyCurrentProfile,
                              onChanged: (value) {
                                setState(() {
                                  _onlyCurrentProfile = value;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filteredItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _onlyCurrentProfile && profile != null
                                  ? 'まだ ${profile.displayName} に紐づく保存結果はありません。'
                                  : 'この条件に合う保存結果はまだありません。',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredItems.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final typeLabel = item.type == 'precheck'
                                ? '送信前チェック'
                                : '相談';

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      typeLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.blueGrey.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (item.profileName != null &&
                                        item.profileName!
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '相手: ${item.profileName}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      item.subtitle,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formatDateTime(item.createdAt),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      item.bestText,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(height: 1.5),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () {
                                              Navigator.of(context)
                                                  .push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          SavedResultDetailScreen(
                                                            item: item,
                                                          ),
                                                    ),
                                                  )
                                                  .then((_) => _reload());
                                            },
                                            child: Text('詳細を見る'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () => copyText(
                                              context,
                                              item.bestText,
                                            ),
                                            child: Text('コピー'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SavedResultDetailScreen extends StatelessWidget {
  const SavedResultDetailScreen({super.key, required this.item});

  final SavedResultItem item;

  @override
  Widget build(BuildContext context) {
    final typeLabel = item.type == 'precheck' ? '送信前チェック' : '相談';

    return Scaffold(
      appBar: AppBar(title: Text('保存した結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              typeLabel,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            if (item.profileName != null &&
                item.profileName!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '相手: ${item.profileName}',
                style: TextStyle(
                  fontSize: 16,
                  color: goMenMutedTextColor(context),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              item.subtitle,
              style: TextStyle(
                fontSize: 16,
                color: goMenMutedTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatDateTime(item.createdAt),
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            const SizedBox(height: 20),
            _HeroReplyCard(
              title: '保存されたベスト案',
              body: item.bestText,
              buttonLabel: 'この文をコピー',
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                for (final line in lines) ...[
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: goMenMutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    super.key,
    required this.title,
    required this.errorText,
    required this.onRetry,
  });

  final String title;
  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '接続に失敗しました',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(errorText),
              const Spacer(),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: Text('もう一度試す', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsultationScaffold extends StatelessWidget {
  const ConsultationScaffold({
    super.key,
    required this.currentStep,
    required this.title,
    required this.subtitle,
    required this.child,
    this.meta,
  });

  final int currentStep;
  final String title;
  final String subtitle;
  final Widget child;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('相談する')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$currentStep / 8',
                style: TextStyle(
                  color: goMenMutedTextColor(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: currentStep / 8,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 24),
              if (meta != null) ...[
                Text(
                  meta!,
                  style: TextStyle(
                    fontSize: 16,
                    color: goMenMutedTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 16,
                  color: goMenMutedTextColor(context),
                ),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionSummaryCard extends StatelessWidget {
  const _DecisionSummaryCard({
    required this.eyebrow,
    required this.headline,
    required this.body,
  });

  final String eyebrow;
  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 0,
      color: const Color(0xFFF7FAFD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFDDE7EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF496172),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              headline,
              style: const TextStyle(
                fontSize: 26,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: Color(0xFF16202A),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              body,
              style: const TextStyle(
                fontSize: 16,
                height: 1.7,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroReplyCard extends StatelessWidget {
  const _HeroReplyCard({
    required this.title,
    required this.body,
    required this.buttonLabel,
    this.helperText,
  });

  final String title;
  final String body;
  final String buttonLabel;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 0,
      color: const Color(0xFFF8FBFE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFD9E6EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF496172),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD7E5EE)),
              ),
              child: Text(
                body,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.75,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF17212B),
                ),
              ),
            ),
            if (helperText != null && helperText!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                helperText!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFF607080),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => copyText(context, body),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: const Color(0xFFF9FBFD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE2EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: Color(0xFF16202A),
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReplyOptionCard extends StatelessWidget {
  const _ReplyOptionCard({required this.option});

  final ReplyOption option;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: const Color(0xFFF3F7FA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE0E8EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              option.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF243443),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              option.body,
              style: const TextStyle(
                fontSize: 16,
                height: 1.65,
                color: Color(0xFF243443),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => copyText(context, option.body),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'コピー',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleReplyCard extends StatelessWidget {
  const _SimpleReplyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: const Color(0xFFF3F7FA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE0E8EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.65,
                color: Color(0xFF243443),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => copyText(context, text),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'コピー',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final ButtonStyle elevatedChoiceStyle = ElevatedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 18),
);

const TextStyle choiceTextStyle = TextStyle(fontSize: 18);

List<ThemeQuestion>? _buildCoupleCoreQuestions(String theme) {
  final config = _coupleCoreConfig(theme);
  if (config == null) return null;
  return _flowQuestionsFromConfig(config);
}

List<ThemeQuestion> _buildQuestions({
  required String relationType,
  required String theme,
}) {
  if (relationType == 'couple') {
    final overridden = _buildCoupleCoreQuestions(theme);
    if (overridden != null) {
      return overridden;
    }
  }

  if (relationType == 'couple') {
    switch (theme) {
      case '連絡頻度':
        return const [
          ThemeQuestion(
            title: '連絡でいちばん引っかかっているのは？',
            options: [
              '返信が遅くて不安になる',
              '既読なのに返事が来ない',
              '未読が長く続く',
              '会っていない時の連絡が少なすぎる',
              '相手から連絡頻度を求められてしんどい',
              '自分が返せず気まずくなっている',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'ズレを強く感じているのはどちらですか？',
            options: [
              '自分がもっと返してほしい',
              '相手がもっと返してほしい',
              'お互いに期待がズレている',
              'まだよくわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回いちばんしたいことは？',
            options: [
              '不安を責めずに伝えたい',
              '連絡ペースをすり合わせたい',
              '自分の非を謝って立て直したい',
              '少し時間を置きたい',
            ],
          ),
        ];

      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな伝わり方がいちばんつらかったですか？',
            options: [
              '責める口調だった',
              '冷たく突き放された',
              '正論で詰められた',
              '皮肉や嫌味っぽく感じた',
              '自分が強く言いすぎた',
              'お互いヒートアップした',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'そのやり取りは主にどこで起きましたか？',
            options: ['LINE', '電話', '対面', '複数'],
          ),
          ThemeQuestion(
            title: '今いちばん近い希望は？',
            options: [
              'まず謝りたい',
              '傷ついたことを穏やかに伝えたい',
              'これ以上悪化させたくない',
              '少し落ち着く時間がほしい',
            ],
          ),
        ];

      case '約束':
        return const [
          ThemeQuestion(
            title: 'どんな約束でもめましたか？',
            options: [
              '会う約束',
              '連絡の約束',
              '時間・遅刻の約束',
              'お金の約束',
              '手伝いの約束',
              '将来についての約束',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '約束を守れなかったのは主に誰ですか？',
            options: ['自分', '相手', 'お互い', '事情があって曖昧'],
          ),
          ThemeQuestion(
            title: '今の気持ちにいちばん近いのは？',
            options: ['軽く扱われた感じ', '裏切られた感じ', '申し訳なさ', '怒り', '悲しさ', '呆れ'],
          ),
        ];

      case '嫉妬':
        return const [
          ThemeQuestion(
            title: '嫉妬のきっかけに近いものは？',
            options: [
              '異性の友人・知人',
              '元恋人',
              '職場や学校の特定の人',
              'SNS上の相手',
              '趣味や仕事が優先されること',
              '自分でもうまく言えない',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '主に嫉妬しているのは誰ですか？',
            options: ['自分が嫉妬している', '相手が嫉妬している', 'お互いにある', 'まだ読めない'],
          ),
          ThemeQuestion(
            title: '今回いちばん近い望みは？',
            options: [
              '安心できる説明がほしい',
              '束縛っぽくならず気持ちを伝えたい',
              '疑われてしんどいと伝えたい',
              '二人のルールを決めたい',
            ],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のことで何が引っかかっていますか？',
            options: [
              'デート代の偏り',
              'プレゼントやお返し',
              '同棲・生活費',
              '貸し借り',
              '節約感覚の違い',
              '収入差へのモヤモヤ',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'どこにいちばんモヤモヤしますか？',
            options: [
              '自分ばかり負担している感じ',
              '相手ばかり負担している感じ',
              '金額より態度や言い方がつらい',
              '何が公平かわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回はどう着地したいですか？',
            options: ['感情的にならず話したい', '具体的な分担を決めたい', 'まず謝りたい', '今回は軽めに問題提起したい'],
          ),
        ];

      case '家事':
        return const [
          ThemeQuestion(
            title: '家事のどこが特につらいですか？',
            options: ['片付け', '洗い物', '洗濯', '掃除', 'ゴミ出し', '名もない家事', 'その他'],
          ),
          ThemeQuestion(
            title: 'もめ方として近いのは？',
            options: [
              '自分ばかりやっている感じ',
              '相手に言われてしんどい',
              'やり方の違いでぶつかる',
              'やる基準そのものが違う',
            ],
          ),
          ThemeQuestion(
            title: '今回いちばんしたいことは？',
            options: ['役割分担を決めたい', '感謝不足を伝えたい', '責めずに改善したい', '一度ルール化したい'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がズレていると感じますか？',
            options: [
              '会う頻度が多すぎる',
              '会う頻度が少なすぎる',
              '一人の時間がほしい',
              '踏み込みが深すぎる',
              '将来の話の温度差がある',
              '別れ話っぽく受け取られそうで怖い',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '距離を調整したい気持ちが強いのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: 'いちばん守りたい伝わり方は？',
            options: [
              '嫌いになったわけではないと伝えたい',
              '境界線をやさしく伝えたい',
              '不安にさせすぎず調整したい',
              '別れたいわけではないことを明確にしたい',
            ],
          ),
        ];

      case '親の介入':
        return const [
          ThemeQuestion(
            title: '親の介入で何がいちばん気になりますか？',
            options: [
              '親に言われたことがつらい',
              '親経由で話が来る',
              '親を優先されて寂しい',
              '結婚観や将来に口を出される',
              '金銭面で親が絡む',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '主に誰の親が関わっていますか？',
            options: ['自分の親', '相手の親', '両方', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今回はパートナーに何を一番求めますか？',
            options: [
              'まず味方でいてほしい',
              '親との線引きを決めたい',
              '強く言いすぎず伝えたい',
              '今は波風を立てず整えたい',
            ],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観のズレが大きいですか？',
            options: [
              '時間の使い方',
              '仕事や将来観',
              'お金の使い方',
              '清潔感や生活習慣',
              '友人付き合い',
              '結婚・子ども観',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲れない', 'どちらも正しい気がする', '小さいズレが積もっている'],
          ),
          ThemeQuestion(
            title: '今回の相談でいちばん知りたいのは？',
            options: [
              '違いを整理して話す方法',
              '折衷案の作り方',
              '今は受け止め方を知りたい',
              '別れるほどのズレか見極めたい',
            ],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みにいちばん近いジャンルは？',
            options: [
              '連絡や返信',
              '会う頻度や距離感',
              '言い方や態度',
              'お金',
              '家事や生活',
              '異性関係',
              '将来や価値観',
            ],
          ),
          ThemeQuestion(
            title: '主にしんどさを感じているのは誰ですか？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今回いちばん近い望みは？',
            options: ['謝りたい', '誤解を解きたい', '安心させたい・されたい', '距離感を調整したい'],
          ),
        ];
    }
  }

  if (relationType == 'friend') {
    switch (theme) {
      case '連絡頻度':
        return const [
          ThemeQuestion(
            title: '連絡でどんなズレを感じていますか？',
            options: [
              '返信が遅くて気になる',
              '既読・未読が長く続く',
              '前より明らかに連絡が減った',
              '自分ばかり連絡している感じ',
              '相手から連絡頻度を求められてしんどい',
              '自分が返せず気まずくなっている',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今いちばんモヤモヤしているのは？',
            options: [
              '嫌われたのか不安',
              '雑に扱われている感じ',
              '距離を置かれている感じ',
              '自分も返せておらず後ろめたい',
            ],
          ),
          ThemeQuestion(
            title: '今回いちばんしたいことは？',
            options: ['重くならずに聞きたい', '不満をやわらかく伝えたい', '自分の非を謝りたい', '今は少し様子を見たい'],
          ),
        ];

      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言われ方がつらかったですか？',
            options: [
              '強く責められた',
              '冷たく突き放された',
              '見下された感じがした',
              'みんなの前で言われた',
              '自分がきつく言ってしまった',
              'お互いヒートアップした',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'その場面に近いのは？',
            options: ['1対1のLINE', 'グループLINE', '対面', '電話'],
          ),
          ThemeQuestion(
            title: '今いちばん近い望みは？',
            options: ['まず謝りたい', '傷ついたことを伝えたい', '関係を悪化させたくない', '少し距離を置きたい'],
          ),
        ];

      case '約束':
        return const [
          ThemeQuestion(
            title: 'どんな約束でもめましたか？',
            options: ['会う約束', '時間・遅刻', '連絡の約束', '手伝いの約束', 'グループ内の役割', 'その他'],
          ),
          ThemeQuestion(
            title: '主に約束を守れなかったのは？',
            options: ['自分', '相手', 'お互い', '事情があって何とも言えない'],
          ),
          ThemeQuestion(
            title: '今の気持ちに近いものは？',
            options: ['軽く見られた感じ', '裏切られた感じ', '申し訳なさ', '怒り', '悲しさ', '呆れ'],
          ),
        ];

      case '人間関係・温度差':
        return const [
          ThemeQuestion(
            title: 'どんな温度差が気になりますか？',
            options: [
              '自分だけ仲が良いと思っていた感じ',
              'グループ内で扱いに差を感じる',
              '相手の優先順位が変わった感じ',
              '自分の熱量が重かった気がする',
              '周囲を挟むと関係がぎくしゃくする',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '特に気になる相手の動きは？',
            options: [
              '他の友人には反応が早い',
              '自分への態度だけ少し違う',
              '誘いをよく断られる',
              '表面上は普通で本音が読めない',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: [
              '重くならず関係を確かめたい',
              '距離感を整えたい',
              '自分の期待を整理したい',
              '無理に追わず落ち着きたい',
            ],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点でもやもやしていますか？',
            options: [
              '立て替え・未払い',
              '割り勘の偏り',
              'プレゼントやお返し',
              '旅行・イベント費用',
              '金額より態度が気になる',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん引っかかるのは？',
            options: [
              '自分ばかり負担している感じ',
              '細かく言いづらいこと',
              '相手の言い方や当然感',
              '何が公平かわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回はどんな話し方をしたいですか？',
            options: ['事務的に整理したい', '関係を壊さず伝えたい', 'まず自分の非を認めたい', '今はまだ切り出したくない'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がズレていると感じますか？',
            options: [
              '誘う頻度が合わない',
              '踏み込みが深すぎる',
              '前より壁を感じる',
              '一人の時間を尊重してほしい',
              'こちらが距離を取りすぎたかも',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '調整したい気持ちが強いのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: 'いちばん守りたい伝わり方は？',
            options: [
              '嫌いになったわけではない',
              '無理のない距離にしたい',
              '相手を責めずに伝えたい',
              '今は静かに整えたい',
            ],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: [
              '時間感覚',
              'お金の感覚',
              '礼儀や言葉づかい',
              '友人付き合いの優先順位',
              '恋愛や異性との距離感',
              '将来観・働き方',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '小さなズレが積もっている'],
          ),
          ThemeQuestion(
            title: '今回ほしいのは？',
            options: ['話し合い方の整理', '自分の受け止め方の整理', '距離を保つコツ', '関係を続けるか見極めたい'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みに近いのはどれですか？',
            options: [
              '連絡や返信',
              '言い方や態度',
              '約束',
              'グループ内の立ち位置',
              'お金',
              '距離感',
              '価値観',
            ],
          ),
          ThemeQuestion(
            title: 'しんどさを感じているのは誰ですか？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今回いちばん近い望みは？',
            options: ['謝りたい', '誤解を解きたい', '関係を整えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (relationType == 'family_parent_child' || relationType == 'parent_child') {
    switch (theme) {
      case '連絡頻度':
        return const [
          ThemeQuestion(
            title: '連絡でどんな負担や不満がありますか？',
            options: [
              '連絡が多すぎてしんどい',
              '連絡が少なすぎて気になる',
              '返信を急かされる',
              '返さないと責められる感じがある',
              '自分が返せず気まずい',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '特に近い構図はどれですか？',
            options: [
              '親から子への連絡が多い',
              '子から親への不満が強い',
              'お互いに頻度が合わない',
              '連絡内容の重さが合わない',
            ],
          ),
          ThemeQuestion(
            title: '今回はどう整えたいですか？',
            options: [
              '角が立たない線引きをしたい',
              '心配はわかると伝えたい',
              '自分の非も認めたい',
              '今は少し距離を置きたい',
            ],
          ),
        ];

      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言い方がつらかったですか？',
            options: [
              '命令口調だった',
              '否定された感じがした',
              '見下された感じがした',
              '昔のことまで持ち出された',
              '自分が強く言ってしまった',
              'お互い感情的になった',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '主にどちらから強く出ましたか？',
            options: ['親から子へ', '子から親へ', 'お互い', 'はっきりしない'],
          ),
          ThemeQuestion(
            title: '今いちばん近い望みは？',
            options: ['まず謝りたい', '傷ついたことを伝えたい', 'これ以上こじらせたくない', '少し冷却期間を置きたい'],
          ),
        ];

      case '口出し・干渉':
        return const [
          ThemeQuestion(
            title: 'どんな口出し・干渉が気になりますか？',
            options: [
              '進路や仕事への口出し',
              '恋愛や結婚への口出し',
              '生活習慣への口出し',
              '育児や家庭への口出し',
              '行動を細かく管理される感じ',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'あなたの受け止めに近いのは？',
            options: [
              '心配なのはわかるが苦しい',
              '信用されていない感じがする',
              '自分の領域に入られている感じ',
              '自分も言い返しすぎた',
            ],
          ),
          ThemeQuestion(
            title: '今回はどこを目指しますか？',
            options: ['線引きを伝えたい', 'やんわり断りたい', '衝突せず距離を取りたい', 'まず自分の気持ちを整理したい'],
          ),
        ];

      case '信頼されていない感じ':
        return const [
          ThemeQuestion(
            title: 'どんな場面で信頼されていないと感じますか？',
            options: [
              '決定を任せてもらえない',
              '何度も確認・監視される',
              'すぐ疑われる',
              '失敗前提で話される',
              '自分の話を信じてもらえない',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の本音に近いのは？',
            options: ['悲しい', '腹が立つ', '情けない', 'もう説明したくない'],
          ),
          ThemeQuestion(
            title: '今回いちばんしたいことは？',
            options: [
              '信頼してほしいと伝えたい',
              'まず落ち着いて話したい',
              '少し距離を取りたい',
              '期待しすぎない形に整えたい',
            ],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点でもやもやしていますか？',
            options: [
              '援助や仕送り',
              '貸し借り',
              '家計負担',
              '金額より言い方や態度',
              '使い道への口出し',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '特に引っかかるのは？',
            options: [
              '当然のように求められること',
              '感謝や説明がないこと',
              'こちらの事情が理解されないこと',
              '自分もはっきり言えていないこと',
            ],
          ),
          ThemeQuestion(
            title: '今回はどう話したいですか？',
            options: [
              '事実ベースで整理したい',
              '関係を壊さず伝えたい',
              'まず謝るところは謝りたい',
              '今はまだ切り出したくない',
            ],
          ),
        ];

      case '家のこと・役割分担':
        return const [
          ThemeQuestion(
            title: 'どんな役割の偏りが気になりますか？',
            options: [
              '家事負担',
              '介護や付き添い',
              '連絡・手続き役',
              '感情面のフォロー役',
              '頼まれごとが一人に偏る',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん近い不満は？',
            options: [
              '自分ばかり背負っている感じ',
              '感謝がない感じ',
              '勝手に役割を決められる感じ',
              '自分も断れず溜めてしまった',
            ],
          ),
          ThemeQuestion(
            title: '今回ほしいのは？',
            options: ['分担を見直したい', 'まずしんどさを伝えたい', '柔らかく断りたい', '今は距離を取って整えたい'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がしんどいですか？',
            options: [
              '近すぎて息苦しい',
              '冷たく遠い感じがする',
              '会う頻度が負担',
              '関わらなさすぎて気まずい',
              'こちらの境界線が守られない',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の気持ちに近いのは？',
            options: [
              '嫌いではないがしんどい',
              'もっと尊重してほしい',
              '自分も避けすぎた',
              'どう関わるのが正解かわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: [
              'ちょうどいい距離にしたい',
              '会い方や頻度を調整したい',
              '波風立てず距離を取りたい',
              'まず関係修復を優先したい',
            ],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: ['働き方・進路', 'お金の使い方', '結婚・子育て観', '礼儀や常識', '家族との距離感', 'その他'],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '違いより伝え方でこじれている'],
          ),
          ThemeQuestion(
            title: '今回いちばんほしいのは？',
            options: ['わかり合える話し方', '無理に合わせない線引き', '自分の整理', '衝突を減らす距離感'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みにいちばん近いのは？',
            options: ['連絡', '言い方', '干渉や信頼', 'お金', '家のこと', '距離感', '価値観'],
          ),
          ThemeQuestion(
            title: 'しんどさを強く感じているのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: 'いまいちばんしたいことは？',
            options: ['謝りたい', '落ち着いて話したい', '境界線を整えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (relationType == 'family_sibling') {
    switch (theme) {
      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言われ方が特につらかったですか？',
            options: [
              '上から言われた',
              '雑に扱われた感じがした',
              '昔のことを持ち出された',
              '親の前で強く言われた',
              '自分がきつく返してしまった',
              'お互い感情的になった',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'その場面に近いのは？',
            options: ['2人だけの場面', '親を含む場面', 'LINE・電話', '親族の集まり'],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['まず謝りたい', '傷ついたことを伝えたい', '親を挟まず整えたい', '少し距離を置きたい'],
          ),
        ];

      case '親を挟んだ揉めごと':
        return const [
          ThemeQuestion(
            title: '親を挟んでどんなことでもめていますか？',
            options: [
              '親への対応の差',
              '親の世話や負担',
              '親からの伝言・伝わり方',
              '相続やお金',
              '親の評価や扱い',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばんつらいのは？',
            options: [
              '自分だけ負担が大きい感じ',
              '悪者にされる感じ',
              '本音が親経由でねじれること',
              '昔からの役割が固定されていること',
            ],
          ),
          ThemeQuestion(
            title: '今回いちばん目指したいことは？',
            options: [
              '直接話して整理したい',
              '親を挟まない形にしたい',
              '自分の負担を伝えたい',
              '今は無理に動かず整えたい',
            ],
          ),
        ];

      case '比較される':
        return const [
          ThemeQuestion(
            title: 'どんな比較が特につらいですか？',
            options: ['仕事や収入', '結婚や家庭', '親への貢献', '性格や出来の良さ', '昔からの役割', 'その他'],
          ),
          ThemeQuestion(
            title: '比べられている感覚は誰からですか？',
            options: ['兄弟姉妹本人から', '親から', '両方から', 'はっきりしない'],
          ),
          ThemeQuestion(
            title: '今いちばん近い望みは？',
            options: [
              '比較をやめてほしい',
              '自分のしんどさを伝えたい',
              '気にしすぎない整理をしたい',
              '少し距離を置きたい',
            ],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点で揉めていますか？',
            options: [
              '立て替え・未払い',
              '親の費用負担',
              '相続や財産',
              '贈与や援助の差',
              '金額より態度が引っかかる',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん引っかかるのは？',
            options: [
              '公平でない感じ',
              '説明が足りないこと',
              '当然のように期待されること',
              '自分も言いづらく溜めていること',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: [
              '数字ベースで整理したい',
              '感情をぶつけず伝えたい',
              'まず自分の非は認めたい',
              '今は深掘りしたくない',
            ],
          ),
        ];

      case '家のこと・役割分担':
        return const [
          ThemeQuestion(
            title: 'どんな役割の偏りがありますか？',
            options: ['親の世話', '手続きや連絡', '家事や片付け', '実家対応', '感情面のフォロー', 'その他'],
          ),
          ThemeQuestion(
            title: 'いちばん近い不満は？',
            options: [
              '自分ばかり負担している',
              'やっても当然扱いされる',
              '役割が曖昧で押しつけ合いになる',
              '自分も断れず抱え込んだ',
            ],
          ),
          ThemeQuestion(
            title: '今回ほしいのは？',
            options: ['分担の見直し', 'しんどさの共有', '断り方の整理', '距離を取る判断'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がズレていますか？',
            options: [
              '干渉が多い',
              '冷たく遠い',
              '会う頻度が負担',
              '必要な時に頼れない',
              '昔の関係のままで扱われる',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の本音に近いのは？',
            options: [
              '嫌いではないがしんどい',
              'もっと尊重してほしい',
              '自分も避けてきた',
              'どう関わればいいかわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: [
              'ちょうどいい距離にしたい',
              '必要最低限に整えたい',
              '本音を落ち着いて伝えたい',
              '今は静かに距離を置きたい',
            ],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: ['親との関わり方', 'お金の感覚', '働き方', '結婚や子育て', '礼儀や常識', 'その他'],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '違いより言い方で悪化している'],
          ),
          ThemeQuestion(
            title: '今回いちばんほしいのは？',
            options: ['話し方の整理', '線引きの言語化', '自分の受け止め方の整理', '距離を置く判断'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みに近いのはどれですか？',
            options: ['言い方', '親を挟んだ問題', '比較', 'お金', '役割分担', '距離感', '価値観'],
          ),
          ThemeQuestion(
            title: 'しんどさを強く感じているのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['謝りたい', '誤解をほどきたい', '負担を伝えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (relationType == 'family_inlaw') {
    switch (theme) {
      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言い方が特につらかったですか？',
            options: [
              '嫌味っぽかった',
              '遠回しに否定された',
              '常識がないように言われた',
              '配偶者と比べられた',
              '自分が強く返してしまった',
              'お互い気まずくなった',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '主に誰との間で起きましたか？',
            options: ['義母', '義父', '義兄弟姉妹', '複数'],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: ['角を立てず整えたい', '傷ついたことは伝えたい', '配偶者にも理解してほしい', '少し距離を置きたい'],
          ),
        ];

      case '行事・付き合い':
        return const [
          ThemeQuestion(
            title: 'どんな付き合いが負担ですか？',
            options: [
              '帰省の頻度',
              '食事や集まりへの参加',
              '行事の優先順位',
              '手伝いの期待',
              '断りづらい空気',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばんしんどいのは？',
            options: [
              '自分の都合が尊重されないこと',
              '配偶者が間に入ってくれないこと',
              '断ると悪者になる感じ',
              '自分も我慢しすぎていること',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['参加頻度を調整したい', '断り方を整えたい', '配偶者と足並みを揃えたい', '今は距離を置きたい'],
          ),
        ];

      case '生活や子育てへの口出し':
        return const [
          ThemeQuestion(
            title: 'どんな口出しが気になりますか？',
            options: [
              '家事や生活習慣',
              '育児方針',
              '子どもへの接し方',
              '仕事と家庭の両立',
              'お金の使い方',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん近い気持ちは？',
            options: [
              '善意でもしんどい',
              '自分たちの領域に入られている感じ',
              '否定されている感じ',
              '自分も言い返せず溜めている',
            ],
          ),
          ThemeQuestion(
            title: '今回目指したいのは？',
            options: ['線引きを作りたい', 'やんわり受け流したい', '配偶者から伝えてほしい', '今は直接ぶつかりたくない'],
          ),
        ];

      case 'パートナー経由の伝わり方':
        return const [
          ThemeQuestion(
            title: 'どんな伝わり方が問題ですか？',
            options: [
              '自分の意図と違って伝わる',
              '配偶者がうまく守ってくれない',
              '義家族の言葉が配偶者経由で強く伝わる',
              '自分の不満が配偶者にしか言えない',
              '板挟みで全員がしんどい',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん困っているのは？',
            options: [
              '誰にどう言えばいいかわからない',
              '配偶者との温度差',
              '義家族に直接言いづらいこと',
              '誤解が膨らみやすいこと',
            ],
          ),
          ThemeQuestion(
            title: '今回はどこを整えたいですか？',
            options: [
              'まず夫婦間で認識を揃えたい',
              '伝え方を整理したい',
              '義家族との距離を調整したい',
              '今は火を大きくしたくない',
            ],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点が引っかかりますか？',
            options: [
              '贈り物・お返し',
              '帰省や行事の費用',
              '援助や仕送り',
              '家計への口出し',
              '金額より態度や当然感',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん引っかかるのは？',
            options: [
              '自分たちの事情が尊重されないこと',
              '配偶者と温度差があること',
              '断りにくい空気',
              '自分もはっきり言えていないこと',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['夫婦内で基準を揃えたい', '角を立てず伝えたい', '事実ベースで整理したい', '今はまだ触れたくない'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がしんどいですか？',
            options: [
              '近すぎて息苦しい',
              '急に冷たく感じる',
              '会う頻度が多い',
              '子どもを通じた関与が多い',
              'こちらの境界線が守られない',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の本音に近いのは？',
            options: [
              '嫌いではないが負担',
              'もっと尊重してほしい',
              '配偶者にわかってほしい',
              'どう整えるのが平和かわからない',
            ],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: [
              'ちょうどいい距離にしたい',
              '会い方や頻度を調整したい',
              'まず夫婦で足並みを揃えたい',
              '少し距離を置きたい',
            ],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: ['家族優先の度合い', '子育て観', 'お金の感覚', '礼儀や常識', '夫婦の役割観', 'その他'],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: [
              '自分が譲れない',
              '相手側が譲らない',
              'どちらも悪くないが合わない',
              '配偶者を挟むことで悪化している',
            ],
          ),
          ThemeQuestion(
            title: '今回いちばんほしいのは？',
            options: ['夫婦での整理', '言い方の整理', '線引きの明確化', '距離を置く判断'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みに近いのはどれですか？',
            options: ['言い方', '行事・付き合い', '口出し', '伝わり方', 'お金', '距離感', '価値観'],
          ),
          ThemeQuestion(
            title: '特にしんどいのはどこですか？',
            options: ['自分', '配偶者', '義家族', '全体がややこしい'],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['角を立てず整えたい', '配偶者とまず話したい', '負担を伝えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (relationType == 'family' || relationType == 'family_other') {
    switch (theme) {
      case '連絡頻度':
        return const [
          ThemeQuestion(
            title: '連絡でどんなズレがありますか？',
            options: [
              '頻度が多すぎる',
              '必要な連絡が来ない',
              '返信を急かされる',
              'こちらばかり連絡している',
              '返せず気まずい',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん近い気持ちは？',
            options: ['負担が大きい', '大事にされていない感じ', '距離を置かれている感じ', '自分も返せておらず後ろめたい'],
          ),
          ThemeQuestion(
            title: '今回はどう整えたいですか？',
            options: ['頻度の線引きをしたい', '気持ちをやわらかく伝えたい', 'まず謝りたい', '今は様子を見たい'],
          ),
        ];

      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言われ方がつらかったですか？',
            options: [
              '強く責められた',
              '冷たく言われた',
              '見下された感じがした',
              '昔のことを持ち出された',
              '自分がきつく返した',
              'お互い感情的になった',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'その場面に近いのは？',
            options: ['LINE・電話', '対面', '家族の集まり', '複数人の前'],
          ),
          ThemeQuestion(
            title: '今いちばん近い望みは？',
            options: ['謝りたい', '傷ついたことを伝えたい', '悪化させたくない', '少し離れたい'],
          ),
        ];

      case '干渉・信頼':
        return const [
          ThemeQuestion(
            title: 'どんな干渉や不信感が気になりますか？',
            options: [
              '行動への口出し',
              '決定を尊重されない',
              '疑われる・確認されすぎる',
              'プライベートに踏み込まれる',
              '善意だが苦しい',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん近い受け止めは？',
            options: ['信用されていない感じ', '距離が近すぎる感じ', '自分の領域が守られない感じ', '自分も説明不足だった'],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: ['線引きを伝えたい', '角を立てず断りたい', '少し距離を置きたい', '自分の整理をしたい'],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点で引っかかりますか？',
            options: [
              '貸し借り',
              '負担の偏り',
              '援助や仕送り',
              '使い方への口出し',
              '金額より態度が気になる',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん困っているのは？',
            options: [
              '当然のように期待されること',
              '説明や感謝が足りないこと',
              '何が公平かわからないこと',
              '自分も言いづらく溜めていること',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['事実ベースで整理したい', '関係を壊さず伝えたい', 'まず自分の非は認めたい', '今は切り出したくない'],
          ),
        ];

      case '家のこと':
        return const [
          ThemeQuestion(
            title: '家のことで何が負担ですか？',
            options: ['家事', '手続きや連絡', '世話や付き添い', '実家対応', '頼まれごとの偏り', 'その他'],
          ),
          ThemeQuestion(
            title: 'いちばん近い不満は？',
            options: ['自分ばかり背負っている', '感謝されない', '勝手に役割を決められる', '自分も断れず抱え込んだ'],
          ),
          ThemeQuestion(
            title: '今回は何がほしいですか？',
            options: ['分担の見直し', 'しんどさの共有', 'やわらかい断り方', '少し距離を置く判断'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がズレていますか？',
            options: [
              '近すぎてしんどい',
              '遠すぎて冷たい',
              '会う頻度が合わない',
              '境界線が守られない',
              'こちらが避けすぎた',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '今の本音に近いのは？',
            options: ['嫌いではないが負担', 'もっと尊重してほしい', '自分も見直したい', 'どう整えるのがよいかわからない'],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['ちょうどいい距離にしたい', '会い方や頻度を整えたい', '関係修復を優先したい', '今は距離を置きたい'],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: ['お金の感覚', '働き方', '家族との関わり方', '礼儀や常識', '将来観', 'その他'],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '違いより伝え方で悪化している'],
          ),
          ThemeQuestion(
            title: '今回いちばんほしいのは？',
            options: ['話し合い方の整理', '線引きの明確化', '自分の受け止め方の整理', '距離を置く判断'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みにいちばん近いのは？',
            options: ['連絡', '言い方', '干渉や信頼', 'お金', '家のこと', '距離感', '価値観'],
          ),
          ThemeQuestion(
            title: 'しんどさを強く感じているのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今いちばんしたいことは？',
            options: ['謝りたい', '誤解をほどきたい', '関係を整えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (relationType == 'other') {
    switch (theme) {
      case '連絡頻度':
        return const [
          ThemeQuestion(
            title: '連絡のどこでズレを感じていますか？',
            options: [
              '返信が遅い',
              '必要な連絡が来ない',
              '連絡が多すぎて負担',
              'そっけなく感じる',
              '自分が返せず気まずい',
              '温度差がある',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: '関係として近いのはどれですか？',
            options: ['仕事・学校の関係', '先輩後輩', '知人・あまり親しくない相手', '立場差はない'],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['誤解なく進めたい', 'やわらかく不満を伝えたい', 'まず謝りたい', '必要最低限の距離にしたい'],
          ),
        ];

      case '言い方がきつい':
        return const [
          ThemeQuestion(
            title: 'どんな言われ方が問題でしたか？',
            options: [
              '強く責められた',
              '冷たくあしらわれた',
              '見下された感じがした',
              '正論で詰められた',
              '自分がきつく言ってしまった',
              'お互い感情的になった',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'その場面に近いのは？',
            options: ['LINE・チャット', '電話', '対面', '人前・グループ内'],
          ),
          ThemeQuestion(
            title: '今いちばん近い望みは？',
            options: ['まず謝りたい', '傷ついたことを伝えたい', '今後の関わり方を整えたい', '少し距離を置きたい'],
          ),
        ];

      case '約束':
        return const [
          ThemeQuestion(
            title: 'どんな約束・段取りの話ですか？',
            options: ['会う約束', '時間や締切', '連絡の約束', '手伝い・役割', '提出物や仕事', 'その他'],
          ),
          ThemeQuestion(
            title: 'どちらの問題が大きいですか？',
            options: ['自分が守れなかった', '相手が守らなかった', 'お互いに認識がズレていた', 'まだよくわからない'],
          ),
          ThemeQuestion(
            title: '今回はどう着地させたいですか？',
            options: ['まず謝って整えたい', '認識のズレを解きたい', '今後のルールを作りたい', '今回は深追いせず収めたい'],
          ),
        ];

      case '距離感':
        return const [
          ThemeQuestion(
            title: '距離感の何がしんどいですか？',
            options: [
              '近すぎて負担',
              '冷たく遠い',
              '必要以上に踏み込まれる',
              '必要な時だけ近い',
              'こちらが避けすぎた',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん近い気持ちは？',
            options: ['尊重してほしい', 'もう少し自然に接したい', '自分も反省がある', 'どう整えるのが正解かわからない'],
          ),
          ThemeQuestion(
            title: '今回は何を目指したいですか？',
            options: ['ちょうどいい距離にしたい', '関係を悪化させたくない', '本音を少し伝えたい', '必要最低限にしたい'],
          ),
        ];

      case 'お金':
        return const [
          ThemeQuestion(
            title: 'お金のどんな点が引っかかりますか？',
            options: [
              '立て替え・未払い',
              '割り勘や負担の差',
              '請求の仕方や言い方',
              '金額より態度が気になる',
              '自分が言い出しにくい',
              'その他',
            ],
          ),
          ThemeQuestion(
            title: 'いちばん困っているのは？',
            options: [
              '当然のように扱われること',
              '説明や配慮が足りないこと',
              '細かく言うと関係が悪くなりそうなこと',
              '自分も曖昧にしてしまったこと',
            ],
          ),
          ThemeQuestion(
            title: '今回はどうしたいですか？',
            options: ['事実ベースで整理したい', '角を立てず伝えたい', 'まず自分の非は認めたい', '今はまだ触れたくない'],
          ),
        ];

      case '価値観の違い':
        return const [
          ThemeQuestion(
            title: 'どんな価値観の違いが大きいですか？',
            options: ['仕事や優先順位', '時間感覚', 'お金の使い方', '礼儀や常識', '人との距離感', 'その他'],
          ),
          ThemeQuestion(
            title: '今の状態に近いのは？',
            options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '違いより伝え方で悪化している'],
          ),
          ThemeQuestion(
            title: '今回ほしいのは？',
            options: ['話し方の整理', '線引きの明確化', '自分の受け止め方の整理', '少し距離を置く判断'],
          ),
        ];

      case 'その他':
        return const [
          ThemeQuestion(
            title: '今回の悩みに近いのはどれですか？',
            options: ['連絡', '言い方', '約束', '距離感', 'お金', '価値観', 'まだ言語化しにくい'],
          ),
          ThemeQuestion(
            title: 'しんどさを強く感じているのは？',
            options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
          ),
          ThemeQuestion(
            title: '今いちばんしたいことは？',
            options: ['謝りたい', '誤解を解きたい', '関係を整えたい', '少し距離を置きたい'],
          ),
        ];
    }
  }

  if (theme == '言い方がきつい') {
    return const [
      ThemeQuestion(
        title: 'どんな伝わり方が問題でしたか？',
        options: [
          '強く責められた',
          '冷たく返された',
          '馬鹿にされた感じがした',
          '正論で詰められた',
          '自分がきつく言ってしまった',
          'その他',
        ],
      ),
      ThemeQuestion(
        title: 'そのやり取りはどこで起きましたか？',
        options: ['LINE', '電話', '対面', '複数'],
      ),
      ThemeQuestion(
        title: '今いちばん近い希望はどれですか？',
        options: ['まず謝りたい', 'きつかったことを伝えたい', 'これ以上悪化させたくない', '少し距離を置きたい'],
      ),
    ];
  }

  if (theme == '約束') {
    return const [
      ThemeQuestion(
        title: 'どんな約束でしたか？',
        options: ['会う約束', '連絡の約束', '時間の約束', 'お金の約束', '手伝いの約束', 'その他'],
      ),
      ThemeQuestion(
        title: '約束が守られなかったのは誰ですか？',
        options: ['自分', '相手', 'お互い', 'はっきりしない'],
      ),
      ThemeQuestion(
        title: '今の気持ちに近いものはどれですか？',
        options: ['裏切られた感じ', '軽く扱われた感じ', '申し訳なさ', '怒り', '悲しさ'],
      ),
    ];
  }

  if (theme == '連絡頻度') {
    return const [
      ThemeQuestion(
        title: '連絡でいちばん引っかかるのはどれですか？',
        options: [
          '返信が遅い',
          '必要な連絡が来ない',
          '連絡が多すぎる',
          'そっけなく感じる',
          '自分が返せず気まずい',
          'その他',
        ],
      ),
      ThemeQuestion(
        title: 'いちばん近い気持ちは？',
        options: ['不安', '怒り', '寂しさ', '申し訳なさ', '混乱'],
      ),
      ThemeQuestion(
        title: '今回はどうしたいですか？',
        options: ['誤解を解きたい', 'やわらかく伝えたい', 'まず謝りたい', '少し距離を置きたい'],
      ),
    ];
  }

  if (theme == 'お金') {
    return const [
      ThemeQuestion(
        title: 'お金のどんな点が問題ですか？',
        options: ['貸し借り', '立て替え', '負担の差', '請求や言い方', '金額より態度が気になる', 'その他'],
      ),
      ThemeQuestion(
        title: 'いちばん困っているのは？',
        options: ['公平でない感じ', '言い出しにくいこと', '説明が足りないこと', '自分も曖昧にしたこと'],
      ),
      ThemeQuestion(
        title: '今回はどうしたいですか？',
        options: ['事実ベースで整理したい', '関係を壊さず伝えたい', 'まず謝りたい', '今はまだ触れたくない'],
      ),
    ];
  }

  if (theme == '距離感') {
    return const [
      ThemeQuestion(
        title: '距離感の何がしんどいですか？',
        options: ['近すぎる', '遠すぎる', '踏み込まれすぎる', '必要な時だけ近い', '自分も避けすぎた', 'その他'],
      ),
      ThemeQuestion(
        title: '今の本音に近いのは？',
        options: ['尊重してほしい', '関係を少し整えたい', '自分も反省がある', '正解がわからない'],
      ),
      ThemeQuestion(
        title: '今回は何を目指したいですか？',
        options: ['ちょうどいい距離にしたい', '本音を少し伝えたい', '必要最低限にしたい', '少し距離を置きたい'],
      ),
    ];
  }

  if (theme == '価値観の違い') {
    return const [
      ThemeQuestion(
        title: 'どんな価値観の違いが大きいですか？',
        options: ['時間感覚', 'お金の感覚', '礼儀や常識', '優先順位', '人との距離感', 'その他'],
      ),
      ThemeQuestion(
        title: '今の状態に近いのは？',
        options: ['自分が譲れない', '相手が譲らない', 'どちらも悪くないが合わない', '違いより伝え方で悪化している'],
      ),
      ThemeQuestion(
        title: '今回ほしいのは？',
        options: ['話し方の整理', '線引きの明確化', '自分の整理', '距離を置く判断'],
      ),
    ];
  }

  if (theme == 'その他') {
    return const [
      ThemeQuestion(
        title: '今回の悩みに近いのはどれですか？',
        options: ['連絡', '言い方', '約束', 'お金', '距離感', '価値観', 'まだ言語化しにくい'],
      ),
      ThemeQuestion(
        title: 'しんどさを強く感じているのは？',
        options: ['自分', '相手', 'お互い', 'まだ整理できていない'],
      ),
      ThemeQuestion(
        title: '今どうしたいですか？',
        options: ['謝りたい', '誤解を解きたい', '関係を整えたい', '少し距離を置きたい'],
      ),
    ];
  }

  return const [
    ThemeQuestion(
      title: 'どんなことがきっかけでしたか？',
      options: ['言い方', '連絡', '約束', 'お金', '距離感', '価値観', 'その他'],
    ),
    ThemeQuestion(
      title: '主に不満を感じているのは誰ですか？',
      options: ['自分', '相手', 'お互い', 'わからない'],
    ),
    ThemeQuestion(
      title: '今どうしたいですか？',
      options: ['謝りたい', '誤解を解きたい', '落ち着かせたい', '距離を置きたい'],
    ),
  ];
}
