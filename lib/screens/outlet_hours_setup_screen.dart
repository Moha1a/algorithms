import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/business_hours_service.dart';
import '../theme/app_colors.dart';
import 'outlet_location_setup_screen.dart';

class OutletHoursSetupScreen extends StatefulWidget {
  const OutletHoursSetupScreen({
    super.key,
    required this.profile,
    this.popOnSave = false,
  });

  final Map<String, dynamic> profile;
  final bool popOnSave;

  @override
  State<OutletHoursSetupScreen> createState() => _OutletHoursSetupScreenState();
}

class _OutletHoursSetupScreenState extends State<OutletHoursSetupScreen> {
  late final List<_Period> _defaultPeriods;
  late final Map<String, _HolidayOverride> _holidayOverrides;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _defaultPeriods = _readDefaultPeriods();
    _holidayOverrides = _readHolidayOverrides();
  }

  List<_Period> _readDefaultPeriods() {
    final raw = widget.profile['businessHours'];
    if (raw is Map) {
      for (final key in BusinessHoursService.dayKeys) {
        final day = raw[key];
        if (day is Map && day['closed'] != true) {
          final periods = _periodsFromRaw(day['periods']);
          if (periods.isNotEmpty) return _ensureTwoPeriods(periods);
        }
      }
    }
    return [_Period.defaults(0), _Period.defaults(1)];
  }

  Map<String, _HolidayOverride> _readHolidayOverrides() {
    final overrides = <String, _HolidayOverride>{};
    final raw = widget.profile['businessHours'];
    if (raw is! Map) return overrides;

    for (final key in BusinessHoursService.dayKeys) {
      final day = raw[key];
      if (day is! Map) continue;
      if (day['closed'] == true) {
        overrides[key] = _HolidayOverride(
          enabled: true,
          closed: true,
          periods: [_Period.defaults(0), _Period.defaults(1)],
        );
        continue;
      }
      final periods = _ensureTwoPeriods(_periodsFromRaw(day['periods']));
      if (periods.isNotEmpty && !_samePeriods(periods, _defaultPeriods)) {
        overrides[key] = _HolidayOverride(
          enabled: true,
          closed: false,
          periods: periods,
        );
      }
    }
    return overrides;
  }

  List<_Period> _periodsFromRaw(Object? raw) {
    if (raw is! List) return <_Period>[];
    return raw.take(2).map(_Period.fromMap).toList();
  }

  List<_Period> _ensureTwoPeriods(List<_Period> periods) {
    final next = periods.map((period) => period.copy()).toList();
    while (next.length < 2) {
      next.add(_Period.defaults(next.length));
    }
    next[0].enabled = true;
    return next;
  }

  bool _samePeriods(List<_Period> a, List<_Period> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].enabled != b[i].enabled ||
          _Period.store(a[i].open) != _Period.store(b[i].open) ||
          _Period.store(a[i].close) != _Period.store(b[i].close)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _pickTime(_Period period, bool isOpen) async {
    final picked = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: isOpen ? period.open : period.close,
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
    if (_defaultPeriods.where((period) => period.enabled).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر وقت افتتاح واحد على الأقل.')),
      );
      return;
    }

    final businessHours = <String, dynamic>{};
    for (final key in BusinessHoursService.dayKeys) {
      final override = _holidayOverrides[key];
      if (override != null && override.enabled) {
        businessHours[key] = override.toMap();
      } else {
        businessHours[key] = _dayMap(_defaultPeriods);
      }
    }

    setState(() => _saving = true);
    final uid = (widget.profile['uid'] ?? '').toString();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'businessHours': businessHours,
      'businessHoursConfigured': true,
      'businessHoursUpdatedAt': FieldValue.serverTimestamp(),
      'approvalStatus': 'approved',
      'adminForceOpen': FieldValue.delete(),
      'adminForceClosed': FieldValue.delete(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    final nextProfile = {...widget.profile, 'businessHours': businessHours};
    setState(() => _saving = false);
    if (widget.popOnSave) {
      Navigator.of(context).pop(nextProfile);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => OutletLocationSetupScreen(profile: nextProfile),
      ),
      (_) => false,
    );
  }

  Map<String, dynamic> _dayMap(List<_Period> periods) {
    return {
      'closed': false,
      'periods': periods
          .where((period) => period.enabled)
          .map((period) => period.toMap())
          .toList(),
    };
  }

  _HolidayOverride _holidayFor(String key) {
    return _holidayOverrides.putIfAbsent(
      key,
      () => _HolidayOverride(
        enabled: false,
        closed: true,
        periods: [_Period.defaults(0), _Period.defaults(1)],
      ),
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
              'حدد وقت الافتتاح والإغلاق لكل الأيام مرة واحدة. إذا عندك يوم عطلة أو يوم وقته مختلف، فعّله من قسم أيام العطل.',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'الوقت العام لكل الأيام',
            child: Column(
              children: [
                for (var i = 0; i < _defaultPeriods.length; i++)
                  _PeriodRow(
                    label: i == 0 ? 'الفترة الأولى' : 'الفترة الثانية',
                    period: _defaultPeriods[i],
                    enabled: i == 0 || _defaultPeriods[i].enabled,
                    canDisable: i != 0,
                    onToggle: (enabled) =>
                        setState(() => _defaultPeriods[i].enabled = enabled),
                    onPickOpen: () => _pickTime(_defaultPeriods[i], true),
                    onPickClose: () => _pickTime(_defaultPeriods[i], false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'أيام العطل أو الأوقات المختلفة',
            child: Column(
              children: [
                for (final key in BusinessHoursService.dayKeys)
                  _HolidayDayTile(
                    dayKey: key,
                    value: _holidayFor(key),
                    onChanged: () => setState(() {}),
                    onPickTime: _pickTime,
                  ),
              ],
            ),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _HolidayDayTile extends StatelessWidget {
  const _HolidayDayTile({
    required this.dayKey,
    required this.value,
    required this.onChanged,
    required this.onPickTime,
  });

  final String dayKey;
  final _HolidayOverride value;
  final VoidCallback onChanged;
  final Future<void> Function(_Period period, bool isOpen) onPickTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value.enabled ? const Color(0xFFFFFBF3) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value.enabled
              ? const Color(0xFFE7B45A)
              : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  BusinessHoursService.dayLabels[dayKey] ?? dayKey,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Text('تخصيص'),
              Switch(
                value: value.enabled,
                onChanged: (enabled) {
                  value.enabled = enabled;
                  onChanged();
                },
              ),
            ],
          ),
          if (value.enabled) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('المنفذ مغلق هذا اليوم بالكامل'),
              value: value.closed,
              onChanged: (closed) {
                value.closed = closed;
                onChanged();
              },
            ),
            if (!value.closed)
              for (var i = 0; i < value.periods.length; i++)
                _PeriodRow(
                  label: i == 0 ? 'الفترة الأولى' : 'الفترة الثانية',
                  period: value.periods[i],
                  enabled: i == 0 || value.periods[i].enabled,
                  canDisable: i != 0,
                  onToggle: (enabled) {
                    value.periods[i].enabled = enabled;
                    onChanged();
                  },
                  onPickOpen: () => onPickTime(value.periods[i], true),
                  onPickClose: () => onPickTime(value.periods[i], false),
                ),
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.period,
    required this.enabled,
    required this.canDisable,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
  });

  final String label;
  final _Period period;
  final bool enabled;
  final bool canDisable;
  final ValueChanged<bool> onToggle;
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
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (canDisable) ...[
                  const Text('تفعيل'),
                  Switch(value: period.enabled, onChanged: onToggle),
                ],
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onPickOpen : null,
                    icon: const Icon(Icons.keyboard_rounded),
                    label: Text('يفتح ${_fmt(period.open)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onPickClose : null,
                    icon: const Icon(Icons.keyboard_rounded),
                    label: Text('يغلق ${_fmt(period.close)}'),
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

class _HolidayOverride {
  _HolidayOverride({
    required this.enabled,
    required this.closed,
    required this.periods,
  });

  bool enabled;
  bool closed;
  final List<_Period> periods;

  Map<String, dynamic> toMap() {
    if (closed) {
      return {'closed': true, 'periods': <Map<String, dynamic>>[]};
    }
    return {
      'closed': false,
      'periods': periods
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

  _Period copy() => _Period(open: open, close: close, enabled: enabled);

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
        'open': store(open),
        'close': store(close),
        'enabled': enabled,
      };

  static TimeOfDay? _parse(Object? raw) {
    final parts = (raw?.toString() ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String store(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
