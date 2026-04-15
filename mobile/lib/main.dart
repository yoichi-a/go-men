import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoMenPlanStorage.ensureLoaded();
  await GoMenThemeStorage.ensureLoaded();
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
        backgroundTop: Color(0xFF161311),
        backgroundBottom: Color(0xFF26201B),
        cardColor: Color(0xFF221C17),
        accentColor: Color(0xFFD6A84A),
        previewTextColor: Colors.white,
        description: '落ち着いた高級感のあるプレミアムテーマ',
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
  }
}

ThemeData buildGoMenTheme(GoMenThemeSpec spec) {
  final isDark = spec.mode == GoMenThemeMode.gold;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: spec.accentColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
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
      backgroundColor: spec.cardColor.withValues(alpha: isDark ? 0.90 : 0.78),
      foregroundColor: isDark ? Colors.white : Colors.black87,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF2E2925) : Colors.black87,
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
    final safeMode = canUse(mode) ? mode : GoMenThemeMode.ivory;
    notifier.value = safeMode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, safeMode.name);
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
    final isDark = spec.mode == GoMenThemeMode.gold;

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
  });

  final String id;
  final String displayName;
  final String relationType;
  final String sensitiveTo;
  final String worksWellWith;
  final String distancePreference;
  final String commonConflicts;
  final String avoidWords;
  final String notes;
  final String createdAt;
  final List<String> relationDetails;

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
    return '''
相手の名前・呼び名: $displayName
関係性: $relationSummaryLabel
傷つきやすい言い方: ${sensitiveTo.isEmpty ? '未設定' : sensitiveTo}
通りやすい伝え方: ${worksWellWith.isEmpty ? '未設定' : worksWellWith}
距離感の傾向: ${distancePreference.isEmpty ? '未設定' : distancePreference}
よく揉めるテーマ: ${commonConflicts.isEmpty ? '未設定' : commonConflicts}
避けたいワード: ${avoidWords.isEmpty ? '未設定' : avoidWords}
補足メモ: ${notes.isEmpty ? '未設定' : notes}
'''
        .trim();
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
    };
  }

  factory RelationshipProfile.fromMap(Map<String, dynamic> map) {
    return RelationshipProfile(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      relationType: map['relationType'] as String,
      relationDetails:
          (map['relationDetails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sensitiveTo: map['sensitiveTo'] as String? ?? '',
      worksWellWith: map['worksWellWith'] as String? ?? '',
      distancePreference: map['distancePreference'] as String? ?? '',
      commonConflicts: map['commonConflicts'] as String? ?? '',
      avoidWords: map['avoidWords'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      createdAt: map['createdAt'] as String,
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
    this.currentStatus,
    this.emotionLevel,
    this.goal,
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
  final String? currentStatus;
  final String? emotionLevel;
  final String? goal;
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
    String? currentStatus,
    String? emotionLevel,
    String? goal,
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
      currentStatus: currentStatus ?? this.currentStatus,
      emotionLevel: emotionLevel ?? this.emotionLevel,
      goal: goal ?? this.goal,
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
          (data['heard_as_interpretations'] as List<dynamic>).cast<String>(),
      avoidPhrases: (data['avoid_phrases'] as List<dynamic>).cast<String>(),
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
    required this.softenedMessage,
    required this.revisedMessageOptions,
    required this.suggestConsultMode,
  });

  final String label;
  final String reason;
  final List<String> riskPoints;
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

class HomeDashboardData {
  const HomeDashboardData({
    required this.profile,
    required this.profileItems,
    required this.allItems,
  });

  final RelationshipProfile? profile;
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

  static const dailyLimit = PlanLimits.freeDailyUses;

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
  static const _key = 'go_men_relationship_profile';

  static Future<RelationshipProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return RelationshipProfile.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfile(RelationshipProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toMap()));
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
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
    final allItems = await LocalHistoryStorage.loadItems();
    final profileItems = profile == null
        ? <SavedResultItem>[]
        : allItems.where((item) => item.profileId == profile.id).toList();

    return HomeDashboardData(
      profile: profile,
      profileItems: profileItems,
      allItems: allItems,
    );
  }

  void _reloadDashboard() {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
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
                  profileItems: [],
                  allItems: [],
                );
            final profile = data.profile;
            final profileItems = data.profileItems;
            final allItems = data.allItems;
            final savedCount = allItems.length;
            final saveProgress = savedCount / LocalHistoryStorage.maxItems;
            final profileProgress = profile == null ? 0.0 : 1.0;

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
                          value: profileProgress,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${profile == null ? 0 : 1} / ${PlanLimits.freeProfiles} 件',
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
                          const SizedBox(height: 6),
                          Text(profile.relationSummaryLabel),
                          const SizedBox(height: 10),
                          Text(
                            '傷つきやすい: ${profile.sensitiveTo.isEmpty ? '未設定' : profile.sensitiveTo}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '通りやすい: ${profile.worksWellWith.isEmpty ? '未設定' : profile.worksWellWith}',
                            style: const TextStyle(color: Colors.black54),
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
                  onPressed: () {
                    if (profile != null) {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => ThemeSelectionScreen(
                                draft: ConsultationDraft(
                                  relationType: profile.relationType,
                                  relationLabel: profile.relationSummaryLabel,
                                  selectedProfile: profile,
                                ),
                              ),
                            ),
                          )
                          .then((_) => _reloadDashboard());
                    } else {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const RelationTypeScreen(),
                            ),
                          )
                          .then((_) => _reloadDashboard());
                    }
                  },
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
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PrecheckInputScreen(initialProfile: profile),
                          ),
                        )
                        .then((_) => _reloadDashboard());
                  },
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
                            builder: (_) => ProfileEditScreen(profile: profile),
                          ),
                        )
                        .then((_) => _reloadDashboard());
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    profile != null ? '関係性プロフィールを編集する' : '関係性プロフィールを設定する',
                    style: const TextStyle(fontSize: 18),
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
  late final TextEditingController _nameController;
  late final TextEditingController _sensitiveToController;
  late final TextEditingController _worksWellWithController;
  late final TextEditingController _distanceController;
  late final TextEditingController _commonConflictsController;
  late final TextEditingController _avoidWordsController;
  late final TextEditingController _notesController;

  String? _relationType;
  List<String> _relationDetails = <String>[];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile?.displayName ?? '',
    );
    _sensitiveToController = TextEditingController(
      text: widget.profile?.sensitiveTo ?? '',
    );
    _worksWellWithController = TextEditingController(
      text: widget.profile?.worksWellWith ?? '',
    );
    _distanceController = TextEditingController(
      text: widget.profile?.distancePreference ?? '',
    );
    _commonConflictsController = TextEditingController(
      text: widget.profile?.commonConflicts ?? '',
    );
    _avoidWordsController = TextEditingController(
      text: widget.profile?.avoidWords ?? '',
    );
    _notesController = TextEditingController(text: widget.profile?.notes ?? '');
    _relationType = widget.profile?.relationType;
    _relationDetails = List<String>.from(
      widget.profile?.relationDetails ?? const [],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sensitiveToController.dispose();
    _worksWellWithController.dispose();
    _distanceController.dispose();
    _commonConflictsController.dispose();
    _avoidWordsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('相手の名前や呼び名を入れてください')));
      return;
    }

    if (_relationType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('関係性を選んでください')));
      return;
    }

    if (widget.profile == null) {
      final existingProfile = await ProfileStorage.loadProfile();
      if (existingProfile != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無料版ではプロフィールは1件までです。既存プロフィールを編集してください')),
        );
        return;
      }
    }

    final profile = RelationshipProfile(
      id:
          widget.profile?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      displayName: _nameController.text.trim(),
      relationType: _relationType!,
      relationDetails: List<String>.from(_relationDetails),
      sensitiveTo: _sensitiveToController.text.trim(),
      worksWellWith: _worksWellWithController.text.trim(),
      distancePreference: _distanceController.text.trim(),
      commonConflicts: _commonConflictsController.text.trim(),
      avoidWords: _avoidWordsController.text.trim(),
      notes: _notesController.text.trim(),
      createdAt: widget.profile?.createdAt ?? DateTime.now().toIso8601String(),
    );

    await ProfileStorage.saveProfile(profile);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteProfile() async {
    await ProfileStorage.clearProfile();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  List<_RelationDetailGroup> get _relationDetailGroups {
    return _profileRelationDetailGroupsFor(_relationType);
  }

  void _selectRelationDetail(_RelationDetailGroup group, String option) {
    setState(() {
      _relationDetails.removeWhere((item) => group.options.contains(item));
      _relationDetails.add(option);
    });
  }

  Widget _relationButton(String value, String label) {
    final selected = _relationType == value;

    if (selected) {
      return ElevatedButton(
        onPressed: () {
          setState(() {
            _relationType = value;
            _relationDetails = <String>[];
          });
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(label),
      );
    }

    return OutlinedButton(
      onPressed: () {
        setState(() {
          _relationType = value;
        });
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '関係性プロフィールを編集' : '関係性プロフィールを作成'),
        actions: [
          if (isEditing)
            IconButton(
              onPressed: _deleteProfile,
              icon: const Icon(Icons.delete_outline),
              tooltip: '削除',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            Text(
              '相手の名前・呼び名',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '例: みほ、彼、母',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '関係性',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _relationButton('couple', '恋人・パートナー'),
            const SizedBox(height: 10),
            _relationButton('friend', '友人'),
            const SizedBox(height: 10),
            _relationButton('family', '家族'),
            const SizedBox(height: 10),
            _relationButton('other', 'その他'),
            if (_relationDetailGroups.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'もう少し詳しく',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'ここを入れておくと、相談時の言い換えがより相手に合いやすくなります',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              for (final group in _relationDetailGroups) ...[
                Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in group.options)
                      ChoiceChip(
                        label: Text(option),
                        selected: _relationDetails.contains(option),
                        onSelected: (_) => _selectRelationDetail(group, option),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
            ],
            const SizedBox(height: 24),
            Text(
              '傷つきやすい言い方',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sensitiveToController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '例: 冷たい言い方、返事の催促、強い決めつけ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '通りやすい伝え方',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _worksWellWithController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '例: まず受け止める、短くやさしく伝える',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '距離感の傾向',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _distanceController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '例: 一度引かれると追われるのが苦手',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'よく揉めるテーマ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commonConflictsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '例: 連絡頻度、予定変更、言い方',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '避けたいワード',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avoidWordsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '例: なんで、いつも、普通は',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '補足メモ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '例: 疲れている時は返信が遅くなる',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text('このプロフィールを保存する', style: TextStyle(fontSize: 18)),
            ),
          ],
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

  List<ThemeQuestion> get questions => _buildQuestions(
    relationType: widget.draft.relationType ?? 'couple',
    theme: widget.draft.theme ?? 'その他',
  );

  void _selectAnswer(String answer) {
    answers.add(answer);

    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex += 1;
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CurrentStatusScreen(
          draft: widget.draft.copyWith(
            themeAnswers: List<String>.from(answers),
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
              onPressed: () => _selectAnswer(option),
              style: elevatedChoiceStyle,
              child: Text(option, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
}

class CurrentStatusScreen extends StatelessWidget {
  const CurrentStatusScreen({super.key, required this.draft});

  final ConsultationDraft draft;

  void _selectStatus(BuildContext context, String status) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EmotionLevelScreen(draft: draft.copyWith(currentStatus: status)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const statuses = [
      '相手が怒っている',
      '自分が怒っている',
      'お互い感情的',
      '既読無視されている',
      '未読のまま',
      '会話が止まっている',
      'さっき電話で揉めた',
      '今から返信したい',
    ];

    return ConsultationScaffold(
      currentStep: 4,
      title: '今はどんな状態ですか？',
      subtitle: 'いちばん近いものを選んでください',
      meta: 'テーマ: ${draft.theme}',
      child: Expanded(
        child: ListView.separated(
          itemCount: statuses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final status = statuses[index];
            return ElevatedButton(
              onPressed: () => _selectStatus(context, status),
              style: elevatedChoiceStyle,
              child: Text(status, style: choiceTextStyle),
            );
          },
        ),
      ),
    );
  }
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
    const emotionLevels = ['落ち着いている', '少ししんどい', 'かなり感情的', '今送ると悪化しそう'];

    return ConsultationScaffold(
      currentStep: 5,
      title: '今の感情の強さはどれくらいですか？',
      subtitle: '今の自分にいちばん近いものを選んでください',
      meta: 'Q3: ${draft.currentStatus}',
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

  void _selectGoal(BuildContext context, String goal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvidenceInputScreen(draft: draft.copyWith(goal: goal)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const goals = [
      '謝りたい',
      '誤解を解きたい',
      '落ち着かせたい',
      '仲直りしたい',
      '距離を置きたい',
      '相手の気持ちを知りたい',
    ];

    return ConsultationScaffold(
      currentStep: 6,
      title: '今回どうしたいですか？',
      subtitle: '今いちばん近い目的を選んでください',
      meta: 'Q3.5: ${draft.emotionLevel}',
      child: Expanded(
        child: ListView.separated(
          itemCount: goals.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final goal = goals[index];
            return ElevatedButton(
              onPressed: () => _selectGoal(context, goal),
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
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
    });

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1440,
      );

      if (file == null) {
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像を読み込めませんでした')));
        return;
      }

      final fileName = file.name.trim().isEmpty
          ? 'screenshot_\${DateTime.now().millisecondsSinceEpoch}.png'
          : file.name.trim();

      if (!mounted) return;

      setState(() {
        _pickedScreenshots.add(_PickedScreenshot(name: fileName, bytes: bytes));
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('スクリーンショットを追加しました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('スクリーンショットを追加できませんでした: $e')));
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
      final uri = Uri.parse('https://go-men.onrender.com/consult/sessions');
      final profile = widget.draft.selectedProfile;
      final recentPatternSummary = profile == null
          ? null
          : await LocalHistoryStorage.buildRecentPatternSummary(profile.id);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'relation_type': widget.draft.relationType,
          'relation_detail_labels': widget.draft.relationDetails,
          'theme': widget.draft.theme,
          'theme_details': widget.draft.themeAnswers,
          'current_status': widget.draft.currentStatus,
          'emotion_level': widget.draft.emotionLevel,
          'goal': widget.draft.goal,
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
      widget.initialDraft?.relationDetails ?? const <String>[],
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
                      Text(profile.relationSummaryLabel),
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
      final uri = Uri.parse('https://go-men.onrender.com/precheck');
      final profile = widget.draft.selectedProfile;
      final recentPatternSummary = profile == null
          ? null
          : await LocalHistoryStorage.buildRecentPatternSummary(profile.id);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'relation_type': widget.draft.relationType,
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
                child: Text(
                  '${draft.selectedProfile!.displayName} / ${draft.selectedProfile!.relationLabel}',
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
                child: Text(
                  '${draft.selectedProfile!.displayName} / ${draft.selectedProfile!.relationLabel}',
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
              title: 'こう聞こえるかも',
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
  late final Future<CompatibilityScoreResult> _future = _fetch();

  Future<CompatibilityScoreResult> _fetch() async {
    final recentPatternSummary =
        await LocalHistoryStorage.buildRecentPatternSummary(widget.profile.id);

    final response = await http.post(
      Uri.parse('https://go-men.onrender.com/compatibility/score'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'relation_type': widget.profile.relationType,
        'relation_detail_labels': widget.profile.relationDetails,
        'profile_context': widget.profile.toProfileContext(),
        'recent_pattern_summary':
            await LocalHistoryStorage.buildRecentPatternSummary(
              widget.profile.id,
            ),
        'recent_pattern_summary': recentPatternSummary,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('APIエラー: ${response.statusCode}\n${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return CompatibilityScoreResult.fromJson(decoded);
  }

  Widget _section(BuildContext context, String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '・$item',
                  style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('相性採点')),
      body: FutureBuilder<CompatibilityScoreResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '相性採点の取得に失敗しました。\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final result = snapshot.data!;
          final scoreColor = result.score >= 80
              ? Colors.green.shade700
              : result.score >= 60
              ? Colors.orange.shade700
              : Theme.of(context).colorScheme.error;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          widget.profile.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            color: goMenMutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 118,
                          height: 118,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: scoreColor, width: 3),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${result.score}',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: scoreColor,
                                ),
                              ),
                              Text(
                                ' / 100',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: goMenMutedTextColor(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          result.label,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          result.summary,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, 'うまくいきやすい点', result.positivePoints),
                const SizedBox(height: 12),
                _section(context, 'すれ違いやすい点', result.riskPoints),
                const SizedBox(height: 12),
                _section(context, '次に意識すること', result.nextActions),
                const SizedBox(height: 16),
                Text(
                  'このスコアは関係を断定するものではなく、コミュニケーション調整の参考用です。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: goMenMutedTextColor(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProPlanScreen extends StatelessWidget {
  const ProPlanScreen({super.key});

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
        ],
      ),
    );
  }

  Widget _planCard({
    required String title,
    required String subtitle,
    required List<String> items,
    bool highlighted = false,
  }) {
    return Card(
      child: Container(
        decoration: highlighted
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(width: 1.4),
              )
            : null,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(height: 1.55)),
            const SizedBox(height: 14),
            for (final item in items) _featureRow(item),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = GoMenPlanStorage.notifier.value;
    final isPro = plan == GoMenPlan.pro;

    return Scaffold(
      appBar: AppBar(title: const Text('Go-men Pro')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPro ? '現在のプラン: Go-men Pro' : '現在のプラン: 無料版',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isPro
                          ? 'Go-men Pro では、保存件数・プロフィール件数・テーマの自由度を広げ、今後の相性診断や深い関係性分析にもつなげていきます。'
                          : 'まずは無料版で価値を体験し、もっと深く使いたい人向けに Go-men Pro を用意する設計です。',
                      style: const TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _planCard(
              title: '無料版',
              subtitle: 'まずは基本機能をシンプルに使うプランです。',
              items: [
                '相談 / 送信前チェック: 1日3回まで',
                'プロフィール保存: ${PlanLimits.freeProfiles}件まで',
                '保存結果: 直近${PlanLimits.freeSavedResults}件まで',
                'テーマ: Ivory',
              ],
            ),
            const SizedBox(height: 16),
            _planCard(
              title: 'Go-men Pro',
              subtitle: '履歴・関係性・見た目まで、より深く使い込みたい人向けです。',
              highlighted: true,
              items: const [
                '相談 / 送信前チェック: 回数制限なし想定',
                'プロフィール保存: 制限なし',
                '保存結果: 制限なし',
                'テーマ: Ivory / Gold / Pink',
                '相性診断（今後の会話履歴活用）',
                '過去の傾向を踏まえた深い提案',
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'これから接続するもの',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text('・App Store サブスク課金'),
                    SizedBox(height: 6),
                    Text('・相性診断の本実装'),
                    SizedBox(height: 6),
                    Text('・テーマ切り替えの演出強化'),
                    SizedBox(height: 6),
                    Text('・音声仲介モード'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  '※ 現在のプラン切り替えは開発確認用です。実際の課金購入はまだ未接続です。',
                  style: TextStyle(height: 1.6),
                ),
              ),
            ),
          ],
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

List<ThemeQuestion> _buildQuestions({
  required String relationType,
  required String theme,
}) {
  if (relationType == 'couple' && theme == '連絡頻度') {
    return const [
      ThemeQuestion(
        title: 'どんなことで気まずくなりましたか？',
        options: [
          '返信が遅い',
          '既読無視',
          '未読が続く',
          '返信がそっけない',
          '連絡の回数が少ない',
          'こちらが責めてしまった',
          'その他',
        ],
      ),
      ThemeQuestion(
        title: '主に不満を感じているのは誰ですか？',
        options: ['自分', '相手', 'お互い', 'わからない'],
      ),
      ThemeQuestion(
        title: '今の気持ちに近いものはどれですか？',
        options: ['不安', '怒り', '寂しさ', '呆れ', '罪悪感', '混乱'],
      ),
    ];
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
