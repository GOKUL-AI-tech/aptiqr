import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/location/location_service.dart';
import '../../../core/utils/app_date.dart';
import '../../../models/daily_test.dart';
import '../../../models/question.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/loading_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Combines a calendar date with a wall-clock time into a single local
/// DateTime. Shared by the generate form and the edit sheet below.
///
/// [rolloverFrom], when given, rolls the result forward one day if [time]
/// is at or before it — this is what makes an overnight window (e.g.
/// Opens 21:55, Closes 07:00) actually work. Without it, "Closes 07:00"
/// combined with the same test_date as "Opens 21:55" lands *earlier* than
/// the open time on that same calendar day, so close_time < open_time and
/// the test's window is inverted — isOpenNow (DailyTest.isOpenNow) is
/// then false at every moment, showing "Closed"/"Not open yet" even right
/// after the intended open time. Pass the open time as rolloverFrom when
/// combining the close/results time so they roll onto the next day
/// whenever they're numerically <= the open time.
DateTime _combine(DateTime date, TimeOfDay time, {TimeOfDay? rolloverFrom}) {
  var result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (rolloverFrom != null) {
    final refMinutes = rolloverFrom.hour * 60 + rolloverFrom.minute;
    final thisMinutes = time.hour * 60 + time.minute;
    if (thisMinutes <= refMinutes) {
      result = result.add(const Duration(days: 1));
    }
  }
  return result;
}

/// Deck slide 07 — "Auto or manual question selection, question count,
/// duration, and QR generation."
class DailyTestConfigScreen extends ConsumerStatefulWidget {
  const DailyTestConfigScreen({super.key});

  @override
  ConsumerState<DailyTestConfigScreen> createState() => _DailyTestConfigScreenState();
}

class _DailyTestConfigScreenState extends ConsumerState<DailyTestConfigScreen> {
  // AppDate.todayIst(), not DateTime.now() — this is what actually
  // gets stamped into daily_tests.test_date on generate. If this
  // admin's device clock/timezone disagrees with the college's real
  // IST calendar day, the test silently lands on the "wrong" date —
  // it still shows up in this admin's own Recent tests (no date
  // filter there), but a faculty/student device computing today
  // correctly (or just differently) never finds it. See
  // core/utils/app_date.dart.
  DateTime _date = AppDate.todayIst();
  int _questionCount = AppConstants.defaultQuestionCount;
  int _duration = AppConstants.defaultDurationMinutes;
  String _mode = 'auto';
  final Set<String> _selectedQuestionIds = {};
  bool _generating = false;
  String? _error;
  DailyTest? _generated;

  // Security & automation (applied right after generation via set_test_options).
  bool _rotatingQr = true;
  bool _autoPublish = true;
  bool _useGeofence = false;
  int _geoRadius = 150;
  double? _geoLat;
  double? _geoLng;
  bool _locating = false;

  Future<void> _captureLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final pos = await LocationService.current();
      setState(() {
        _geoLat = pos.latitude;
        _geoLng = pos.longitude;
      });
    } on LocationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // Previously hardcoded (10 AM / 2 PM / 3 PM, from AppConstants, with no
  // way to see or change them before generating) — now shown and editable
  // up front, since "the test opens whenever AppConstants says" was one
  // of the reasons a test's actual window didn't match what the admin
  // assumed. See AdminService.generateDailyTest / .toUtc() there for why
  // these must be picked in local time and converted correctly.
  TimeOfDay _openTime = const TimeOfDay(hour: AppConstants.defaultOpenHour, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: AppConstants.defaultCloseHour, minute: 0);
  TimeOfDay _resultsTime = const TimeOfDay(hour: AppConstants.defaultResultsHour, minute: 0);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _generate() async {
    final category = ref.read(currentAdminProvider).valueOrNull?.category;
    if (category == null) {
      setState(() => _error = 'Could not determine your admin category yet — try again in a moment.');
      return;
    }
    if (_mode == 'manual' && _selectedQuestionIds.length != _questionCount) {
      setState(() => _error = 'Select exactly $_questionCount questions for manual mode (${_selectedQuestionIds.length} selected).');
      return;
    }
    if (_useGeofence && (_geoLat == null || _geoLng == null)) {
      setState(() => _error = 'Tap "Use my current location" to set the test location, or turn the geofence off.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final open = _combine(_date, _openTime);
      final close = _combine(_date, _closeTime, rolloverFrom: _openTime);
      final results = _combine(_date, _resultsTime, rolloverFrom: _openTime);
      final test = await ref.read(adminServiceProvider).generateDailyTest(
            testDate: _date,
            category: category,
            questionCount: _questionCount,
            durationMinutes: _duration,
            openTime: open,
            closeTime: close,
            resultsTime: results,
            selectionMode: _mode,
            questionIds: _mode == 'manual' ? _selectedQuestionIds.toList() : null,
          );
      var finalTest = test;
      if (!_rotatingQr || !_autoPublish || _useGeofence) {
        // Defaults (rotating QR on, auto-publish on, no geofence) need no
        // extra call; anything else is applied before the QR is shown.
        finalTest = await ref.read(adminServiceProvider).setTestOptions(
              testId: test.id,
              qrRotating: _rotatingQr,
              autoPublish: _autoPublish,
              geoLat: _useGeofence ? _geoLat : null,
              geoLng: _useGeofence ? _geoLng : null,
              geoRadiusM: _useGeofence ? _geoRadius : null,
            );
      }
      setState(() => _generated = finalTest);
      ref.invalidate(recentTestsProvider);
      // Take the admin straight to the shareable QR — that's the whole
      // point of generating a test, and they can always come back to it
      // later via the QR icon on this test's Recent tests row below.
      if (mounted) {
        context.push('/admin/daily-test/qr', extra: finalTest);
      }
    } catch (e) {
      final msg = '$e'.contains('duplicate key') || '$e'.contains('already exists')
          ? 'A ${category.label} test for ${DateFormat('MMM d, yyyy').format(_date)} already exists. Edit it below if it\'s still '
              '"scheduled", or delete it (tap the trash icon) if it has already opened, then generate again.'
          : '$e';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _confirmDelete(DailyTest test) async {
    final dateLabel = DateFormat('MMM d, yyyy').format(test.testDate);
    final hasRealData = test.status != DailyTestStatus.draft && test.status != DailyTestStatus.scheduled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $dateLabel\'s test?'),
        content: Text(
          hasRealData
              ? 'This test is "${test.status.name}" — deleting it permanently removes every student\'s '
                  'attempt, answers, and ranking for that day. This cannot be undone.'
              : 'This removes the test and its question set. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteDailyTest(test.id);
      ref.invalidate(recentTestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $dateLabel\'s test.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentTestsProvider);
    final adminAsync = ref.watch(currentAdminProvider);
    final categoryLabel = adminAsync.valueOrNull?.category.label;

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryLabel == null ? 'Daily Test' : '$categoryLabel Daily Test'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(recentTestsProvider);
            await ref.read(recentTestsProvider.future);
          }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            categoryLabel == null ? 'Generate a test' : 'Generate today\'s $categoryLabel test',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Test date'),
            subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_date)),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: _pickDate,
          ),
          Row(
            children: [
              Expanded(
                child: _TimePickerTile(
                  label: 'Opens',
                  time: _openTime,
                  onChanged: (t) => setState(() => _openTime = t),
                ),
              ),
              Expanded(
                child: _TimePickerTile(
                  label: 'Closes',
                  time: _closeTime,
                  onChanged: (t) => setState(() => _closeTime = t),
                ),
              ),
            ],
          ),
          _TimePickerTile(
            label: 'Results visible',
            time: _resultsTime,
            onChanged: (t) => setState(() => _resultsTime = t),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '$_questionCount',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Question count'),
                  onChanged: (v) => _questionCount = int.tryParse(v) ?? _questionCount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '$_duration',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration (min)'),
                  onChanged: (v) => _duration = int.tryParse(v) ?? _duration,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Selection mode', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto')),
              ButtonSegment(value: 'manual', label: Text('Manual')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (_mode == 'manual') ...[
            const SizedBox(height: 16),
            Text('Pick exactly $_questionCount questions', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            _ManualQuestionPicker(selected: _selectedQuestionIds, onToggle: (id) => setState(() => _selectedQuestionIds.contains(id) ? _selectedQuestionIds.remove(id) : _selectedQuestionIds.add(id))),
          ],
          const SizedBox(height: 16),
          Text('Security & automation', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rotating QR (every 30 s)'),
            subtitle: const Text('A screenshot of the code stops working within ~90 seconds.'),
            value: _rotatingQr,
            onChanged: (v) => setState(() => _rotatingQr = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-publish results'),
            subtitle: const Text('Publish rankings automatically at the results time.'),
            value: _autoPublish,
            onChanged: (v) => setState(() => _autoPublish = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Only allow starting inside a location'),
            subtitle: Text(_useGeofence && _geoLat != null
                ? 'Centre set (${_geoLat!.toStringAsFixed(5)}, ${_geoLng!.toStringAsFixed(5)}), radius $_geoRadius m'
                : 'Geofence the test to your classroom/lab.'),
            value: _useGeofence,
            onChanged: (v) => setState(() => _useGeofence = v),
          ),
          if (_useGeofence) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _locating ? null : _captureLocation,
                    icon: _locating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded),
                    label: const Text('Use my current location'),
                  ),
                ),
              ],
            ),
            Slider(
              value: _geoRadius.toDouble(),
              min: 50,
              max: 1000,
              divisions: 19,
              label: '$_geoRadius m',
              onChanged: (v) => setState(() => _geoRadius = v.round()),
            ),
            const Text('GPS indoors can be off by 30-50 m, so avoid radii below ~100 m.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat_rounded, color: AppColors.admin),
            title: const Text('Recurring schedule'),
            subtitle: const Text('Auto-generate this test on chosen weekdays'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/admin/templates'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          LoadingButton(label: 'Generate & Create QR', loading: _generating, onPressed: _generate, color: AppColors.admin),
          if (_generated != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.adminLight, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.admin),
                  SizedBox(width: 10),
                  Expanded(child: Text('Test generated. View/share its QR any time from the list below.')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Recent tests', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AsyncValueWidget<List<DailyTest>>(
            value: recentAsync,
            data: (tests) => Column(
              children: tests.map((t) {
                // Only a test that hasn't opened yet can safely be
                // edited — once students can start attempting it,
                // changing the question set/timing under them would be
                // unsafe (see update_daily_test in functions.sql, which
                // enforces this same rule server-side regardless of what
                // the UI allows tapping). Deleting is allowed at any
                // status though — see _confirmDelete — since that's the
                // only way out of "test_date is unique and this one is
                // already published/closed, so I can't edit it or make a
                // new one for that date."
                final editable = t.status == DailyTestStatus.draft || t.status == DailyTestStatus.scheduled;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('MMM d, yyyy').format(t.testDate)),
                  subtitle: Text('${t.questionCount} questions · ${t.selectionMode}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusPill(status: t.status.name),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.qr_code_rounded, color: AppColors.admin, size: 20),
                        tooltip: 'View/share QR',
                        // Unlike the edit sheet below (onTap), viewing/
                        // sharing the QR is safe at any status — a
                        // published or closed test's QR just no longer
                        // unlocks anything new, so there's no reason to
                        // gate this behind `editable` the way editing is.
                        onPressed: () => context.push('/admin/daily-test/qr', extra: t),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                        tooltip: 'Delete test',
                        onPressed: () => _confirmDelete(t),
                      ),
                      if (editable) const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    ],
                  ),
                  onTap: () {
                    if (!editable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('This test has already opened, so it can no longer be edited. You can still delete it below.')),
                      );
                      return;
                    }
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _EditTestSheet(test: t),
                    ).then((changed) {
                      if (changed == true) ref.invalidate(recentTestsProvider);
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final void Function(TimeOfDay) onChanged;
  const _TimePickerTile({required this.label, required this.time, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(time.format(context)),
      trailing: const Icon(Icons.access_time_rounded),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time);
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Text(status, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _ManualQuestionPicker extends ConsumerWidget {
  final Set<String> selected;
  final void Function(String id) onToggle;
  const _ManualQuestionPicker({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionsProvider);
    return SizedBox(
      height: 320,
      child: AsyncValueWidget<List<Question>>(
        value: questionsAsync,
        data: (questions) => ListView.builder(
          itemCount: questions.length,
          itemBuilder: (context, i) {
            final q = questions[i];
            return CheckboxListTile(
              dense: true,
              value: selected.contains(q.id),
              onChanged: (_) => onToggle(q.id),
              title: Text(q.questionText, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(q.subject, style: const TextStyle(fontSize: 11)),
            );
          },
        ),
      ),
    );
  }
}

/// Edit sheet for a single "Recent tests" row. Only ever opened for a
/// test whose status is still 'draft' or 'scheduled' — see the onTap
/// check in _DailyTestConfigScreenState and the server-side enforcement
/// of the same rule in update_daily_test (functions.sql). Pops `true` on
/// a successful save so the caller knows to refresh the list, `false`/
/// null otherwise (dismissed, or nothing changed).
class _EditTestSheet extends ConsumerStatefulWidget {
  final DailyTest test;
  const _EditTestSheet({required this.test});

  @override
  ConsumerState<_EditTestSheet> createState() => _EditTestSheetState();
}

class _EditTestSheetState extends ConsumerState<_EditTestSheet> {
  late int _questionCount;
  late int _duration;
  late String _mode;
  late DateTime _testDate;
  late TimeOfDay _openTime;
  late TimeOfDay _closeTime;
  late TimeOfDay _resultsTime;
  final Set<String> _selectedQuestionIds = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _questionCount = widget.test.questionCount;
    _duration = widget.test.durationMinutes;
    _mode = widget.test.selectionMode;
    _testDate = widget.test.testDate;
    // .openTime/.closeTime/.resultsTime are already .toLocal() in
    // DailyTest.fromJson, so TimeOfDay.fromDateTime here reflects what
    // the admin actually sees on the home screen, not raw UTC.
    _openTime = TimeOfDay.fromDateTime(widget.test.openTime);
    _closeTime = TimeOfDay.fromDateTime(widget.test.closeTime);
    _resultsTime = TimeOfDay.fromDateTime(widget.test.resultsTime);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _testDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _testDate = picked);
  }

  Future<void> _save() async {
    if (_mode == 'manual' && _selectedQuestionIds.isNotEmpty && _selectedQuestionIds.length != _questionCount) {
      setState(() => _error = 'Select exactly $_questionCount questions for manual mode (${_selectedQuestionIds.length} selected), or leave the picker untouched to keep the current set.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminServiceProvider).updateDailyTest(
            testId: widget.test.id,
            // Date/time are always sent (even if unchanged) — harmless
            // no-op when unchanged, and it keeps this logic simple. This
            // is independent of the question-set reshuffle below, which
            // only fires when count/mode/ids are non-null.
            testDate: _testDate,
            openTime: _combine(_testDate, _openTime),
            closeTime: _combine(_testDate, _closeTime, rolloverFrom: _openTime),
            resultsTime: _combine(_testDate, _resultsTime, rolloverFrom: _openTime),
            questionCount: _questionCount != widget.test.questionCount ? _questionCount : null,
            durationMinutes: _duration != widget.test.durationMinutes ? _duration : null,
            selectionMode: _mode != widget.test.selectionMode ? _mode : null,
            // Only re-pick questions if the admin actually touched the
            // manual picker on this sheet — an empty selection here means
            // "didn't change it", not "clear the questions".
            questionIds: _mode == 'manual' && _selectedQuestionIds.isNotEmpty ? _selectedQuestionIds.toList() : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // daily_tests.test_date is `unique` (see schema.sql) — moving this
      // test onto a date that already has one throws a duplicate-key
      // error the admin should actually understand, not a raw Postgres
      // message.
      final msg = '$e'.contains('duplicate key') || '$e'.contains('already exists')
          ? 'A test for ${DateFormat('MMM d, yyyy').format(_testDate)} already exists. Edit or delete that one first.'
          : 'Could not save: $e';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit test', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Test date'),
              subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_testDate)),
              trailing: const Icon(Icons.calendar_today_rounded),
              onTap: _pickDate,
            ),
            Row(
              children: [
                Expanded(
                  child: _TimePickerTile(label: 'Opens', time: _openTime, onChanged: (t) => setState(() => _openTime = t)),
                ),
                Expanded(
                  child: _TimePickerTile(label: 'Closes', time: _closeTime, onChanged: (t) => setState(() => _closeTime = t)),
                ),
              ],
            ),
            _TimePickerTile(label: 'Results visible', time: _resultsTime, onChanged: (t) => setState(() => _resultsTime = t)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '$_questionCount',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Question count'),
                    onChanged: (v) => _questionCount = int.tryParse(v) ?? _questionCount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_duration',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duration (min)'),
                    onChanged: (v) => _duration = int.tryParse(v) ?? _duration,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Selection mode', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('Auto')),
                ButtonSegment(value: 'manual', label: Text('Manual')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode == 'manual') ...[
              const SizedBox(height: 16),
              Text(
                _selectedQuestionIds.isEmpty
                    ? 'Keeps the current question set unless you pick $_questionCount below.'
                    : 'Pick exactly $_questionCount questions',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              _ManualQuestionPicker(
                selected: _selectedQuestionIds,
                onToggle: (id) => setState(() => _selectedQuestionIds.contains(id) ? _selectedQuestionIds.remove(id) : _selectedQuestionIds.add(id)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 20),
            LoadingButton(label: 'Save changes', loading: _saving, onPressed: _save, color: AppColors.admin),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
