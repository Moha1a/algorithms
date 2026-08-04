import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/business_hours_service.dart';
import '../theme/app_colors.dart';
import 'home_shell_screen.dart';

class OutletHoursSetupScreen extends StatefulWidget {
  const OutletHoursSetupScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OutletHoursSetupScreen> createState() => _OutletHoursSetupScreenState();
}

class _OutletHoursSetupScreenState extends State<OutletHoursSetupScreen> {
  late final Map<String, _DayHours> _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _days = {
      for (final key in BusinessHoursService.dayKeys)
        key: _DayHours.fromMap(
          (widget.profile['businessHours'] is Map)
              ? (widget.profile['businessHours'] as Map)[key]
              : null,
        ),
    };
  }

  Future<void> _pickTime(String dayKey, int periodIndex, bool isOpen) async {
    final day = _days[dayKey]!;
    final period = day.periods[periodIndex];
    final current = isOpen ? period.open : period.close;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        period.open = picked;
      } else {
        period.close = picked;
      }
    });
  }

  Future<void> _save() async {
    final hasOpenDay = _days.values.any((day) => !day.closed);
    if (!hasOpenDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر يوم عمل واحد على الأقل.')),
      );
      return;
    }

    setState(() => _saving = true);
    final businessHours = {
      for (final entry in _days.entries) entry.key: entry.value.toMap(),
    };
    final uid = (widget.profile['uid'] ?? '').toString();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'businessHours': businessHours,
      'businessHoursConfigured': true,
      'businessHoursUpdatedAt': FieldValue.serverTimestamp(),
      'approvalStatus': 'approved',
    }, SetOptions(merge: true));
    if (!mounted) return;
    final nextProfile = {...widget.profile, 'businessHours': businessHours};
    setState(() => _saving = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeShellScreen(profile: nextProfile)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أوقات عمل المنفذ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFD89B)),
            ),
            child: const Text(
              'حدد أوقات افتتاح وغلق المنفذ. يمكن اختيار فترتين في اليوم، أو الاكتفاء بفترة واحدة، أو جعل اليوم مغلقاً.',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final key in BusinessHoursService.dayKeys)
            _DayHoursCard(
              dayKey: key,
              value: _days[key]!,
              onChanged: () => setState(() {}),
              onPickTime: _pickTime,
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_saving ? 'جاري الحفظ...' : 'حفظ أوقات العمل'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHoursCard extends StatelessWidget {
  const _DayHoursCard({
    required this.dayKey,
    required this.value,
    required this.onChanged,
    required this.onPickTime,
  });

  final String dayKey;
  final _DayHours value;
  final VoidCallback onChanged;
  final Future<void> Function(String dayKey, int periodIndex, bool isOpen)
      onPickTime;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    BusinessHoursService.dayLabels[dayKey] ?? dayKey,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Switch(
                  value: !value.closed,
                  onChanged: (open) {
                    value.closed = !open;
                    onChanged();
                  },
                ),
                Text(value.closed ? 'مغلق' : 'مفتوح'),
              ],
            ),
            if (!value.closed) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < value.periods.length; i++)
                _PeriodRow(
                  label: i == 0 ? 'الفترة الأولى' : 'الفترة الثانية',
                  period: value.periods[i],
                  enabled: i == 0 || value.periods[i].enabled,
                  onToggle: i == 0
                      ? null
                      : (enabled) {
                          value.periods[i].enabled = enabled;
                          onChanged();
                        },
                  onPickOpen: () => onPickTime(dayKey, i, true),
                  onPickClose: () => onPickTime(dayKey, i, false),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.period,
    required this.enabled,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
  });

  final String label;
  final _Period period;
  final bool enabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (onToggle != null)
                  Switch(value: period.enabled, onChanged: onToggle),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onPickOpen : null,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('فتح ${_fmt(period.open)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onPickClose : null,
                    icon: const Icon(Icons.lock_clock_rounded),
                    label: Text('غلق ${_fmt(period.close)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'ص' : 'م';
    return '$hour:$minute $suffix';
  }
}

class _DayHours {
  _DayHours({required this.closed, required this.periods});

  bool closed;
  final List<_Period> periods;

  factory _DayHours.fromMap(Object? raw) {
    if (raw is Map) {
      final periodsRaw = raw['periods'];
      final periods = <_Period>[];
      if (periodsRaw is List) {
        for (final item in periodsRaw.take(2)) {
          periods.add(_Period.fromMap(item));
        }
      }
      while (periods.length < 2) {
        periods.add(_Period.defaults(periods.length));
      }
      return _DayHours(closed: raw['closed'] == true, periods: periods);
    }
    return _DayHours(
      closed: false,
      periods: [_Period.defaults(0), _Period.defaults(1)],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'closed': closed,
      'periods': closed
          ? <Map<String, dynamic>>[]
          : periods
              .where((period) => period.enabled)
              .map((period) => period.toMap())
              .toList(),
    };
  }
}

class _Period {
  _Period({required this.open, required this.close, required this.enabled});

  TimeOfDay open;
  TimeOfDay close;
  bool enabled;

  factory _Period.defaults(int index) {
    return _Period(
      open: index == 0
          ? const TimeOfDay(hour: 8, minute: 0)
          : const TimeOfDay(hour: 17, minute: 0),
      close: index == 0
          ? const TimeOfDay(hour: 14, minute: 0)
          : const TimeOfDay(hour: 22, minute: 0),
      enabled: index == 0,
    );
  }

  factory _Period.fromMap(Object? raw) {
    if (raw is Map) {
      return _Period(
        open: _parse(raw['open']) ?? const TimeOfDay(hour: 8, minute: 0),
        close: _parse(raw['close']) ?? const TimeOfDay(hour: 14, minute: 0),
        enabled: raw['enabled'] != false,
      );
    }
    return _Period.defaults(0);
  }

  Map<String, dynamic> toMap() => {
        'open': _store(open),
        'close': _store(close),
        'enabled': enabled,
      };

  static TimeOfDay? _parse(Object? raw) {
    final parts = (raw?.toString() ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _store(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
