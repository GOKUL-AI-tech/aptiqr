import 'test_category.dart';

enum DailyTestStatus { draft, scheduled, open, closed, published }

DailyTestStatus testStatusFromString(String value) {
  return DailyTestStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DailyTestStatus.draft,
  );
}

class DailyTest {
  final String id;
  final DateTime testDate;
  /// Which of the 3 parallel tracks (Aptitude/Technical/Communication)
  /// this test/QR belongs to — a single calendar date can have up to 3
  /// DailyTest rows, one per category.
  final TestCategory category;
  final int questionCount;
  final int durationMinutes;
  final DateTime openTime;
  final DateTime closeTime;
  final DateTime resultsTime;
  final String selectionMode; // auto | manual
  final DailyTestStatus status;
  final String? qrPayload;
  /// True when the QR code changes every 30 s (see upgrade_v2.sql). The
  /// static [qrPayload] is then NOT what students scan — the faculty/admin
  /// screens fetch the live token via the `current_qr_token` RPC.
  final bool qrRotating;
  final bool autoPublish;
  final double? geoLat;
  final double? geoLng;
  final int? geoRadiusM;

  bool get hasGeofence => geoLat != null && geoLng != null && geoRadiusM != null;

  const DailyTest({
    required this.id,
    required this.testDate,
    required this.category,
    required this.questionCount,
    required this.durationMinutes,
    required this.openTime,
    required this.closeTime,
    required this.resultsTime,
    required this.selectionMode,
    required this.status,
    this.qrPayload,
    this.qrRotating = false,
    this.autoPublish = true,
    this.geoLat,
    this.geoLng,
    this.geoRadiusM,
  });

  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(openTime) && now.isBefore(closeTime);
  }

  bool get resultsPublished => status == DailyTestStatus.published;

  factory DailyTest.fromJson(Map<String, dynamic> json) {
    return DailyTest(
      id: json['id'] as String,
      testDate: DateTime.parse(json['test_date'] as String),
      category: TestCategoryX.fromString(json['category'] as String? ?? 'aptitude'),
      questionCount: json['question_count'] as int,
      durationMinutes: json['duration_minutes'] as int,
      openTime: DateTime.parse(json['open_time'] as String).toLocal(),
      closeTime: DateTime.parse(json['close_time'] as String).toLocal(),
      resultsTime: DateTime.parse(json['results_time'] as String).toLocal(),
      selectionMode: json['selection_mode'] as String,
      status: testStatusFromString(json['status'] as String),
      qrPayload: json['qr_payload'] as String?,
      qrRotating: json['qr_rotating'] as bool? ?? false,
      autoPublish: json['auto_publish'] as bool? ?? true,
      geoLat: (json['geo_lat'] as num?)?.toDouble(),
      geoLng: (json['geo_lng'] as num?)?.toDouble(),
      geoRadiusM: json['geo_radius_m'] as int?,
    );
  }
}
