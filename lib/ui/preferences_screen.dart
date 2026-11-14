import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_export.dart';
import '../core/rider_profile.dart';
import '../core/units.dart';
import 'app_palette.dart';
import 'credits.dart';
import 'layout.dart';
import 'plan_controller.dart';
import 'recorder_controller.dart';
import 'rider_profile_controller.dart';
import 'units_controller.dart';

/// Set-and-forget settings. Add a new setting as another [_Section].
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(rideFormatProvider);
    final appearance = const _Section(
      title: 'Appearance',
      description: 'Colour palette for the app.',
      child: PaletteChooser(),
    );
    final recording = _Section(
      title: 'Recording',
      description: 'File format used when you save a ride. '
          'FIT uploads to Strava and Garmin; CSV also keeps the '
          'ERG target.',
      child: SegmentedButton<RideFormat>(
        segments: [
          for (final f in RideFormat.values)
            ButtonSegment(value: f, label: Text(f.label)),
        ],
        selected: {format},
        onSelectionChanged: (s) =>
            ref.read(rideFormatProvider.notifier).set(s.first),
      ),
    );
    final units = _Section(
      title: 'Units',
      description: 'Ride data covers speed and distance; body '
          'measurements cover height and weight. Saved rides and '
          'exported files always use metric.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UnitsPicker(
            key: const Key('rideUnits'),
            label: 'Ride data',
            value: ref.watch(rideUnitsProvider),
            onChanged: ref.read(rideUnitsProvider.notifier).set,
          ),
          const SizedBox(height: 16),
          _UnitsPicker(
            key: const Key('bodyUnits'),
            label: 'Body measurements',
            value: ref.watch(bodyUnitsProvider),
            onChanged: ref.read(bodyUnitsProvider.notifier).set,
          ),
        ],
      ),
    );
    final profile = const _Section(
      title: 'Rider profile',
      description: 'Used to estimate calories burned. Estimates '
          'stay blank until every field is filled in.',
      child: _RiderProfileForm(),
    );

    const creditsSection = _Section(
      title: 'Credits',
      description: 'Map, route and elevation data come from these projects. '
          'Tap one to read its terms.',
      child: CreditsList(),
    );
    const training = _Section(
      title: 'Training',
      description: 'Your FTP, in watts. Workout plans can set steps as a '
          'percent of it.',
      child: _FtpField(),
    );

    Widget stack(List<Widget> sections) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            sections[i],
          ],
        ]);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = isWideLayout(box.maxWidth);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1100 : 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (wide)
                    // Short settings on the left, the longer profile form on the right.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: stack([appearance, recording, training, creditsSection])),
                      const SizedBox(width: 24),
                      Expanded(child: stack([units, profile])),
                    ])
                  else
                    stack([appearance, recording, training, units, profile, creditsSection]),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}


class _FtpField extends ConsumerStatefulWidget {
  const _FtpField();

  @override
  ConsumerState<_FtpField> createState() => _FtpFieldState();
}

class _FtpFieldState extends ConsumerState<_FtpField> {
  late final _c = TextEditingController(
      text: ref.read(ftpProvider)?.toString() ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = FtpController.range;
    final v = int.tryParse(_c.text);
    final ok = v != null && v >= lo && v <= hi;
    return TextField(
      key: const Key('ftp'),
      controller: _c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'FTP',
        suffixText: 'W',
        errorText: _c.text.isEmpty || ok ? null : 'Enter $lo–$hi',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        ref.read(ftpProvider.notifier).set(ok ? v : null);
        setState(() {});
      },
    );
  }
}

class _UnitsPicker extends StatelessWidget {
  const _UnitsPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final UnitSystem value;
  final ValueChanged<UnitSystem> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label)),
      SegmentedButton<UnitSystem>(
        segments: [
          for (final u in UnitSystem.values)
            ButtonSegment(value: u, label: Text(u.label)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    ]);
  }
}

class _RiderProfileForm extends ConsumerStatefulWidget {
  const _RiderProfileForm();

  @override
  ConsumerState<_RiderProfileForm> createState() => _RiderProfileFormState();
}

class _RiderProfileFormState extends ConsumerState<_RiderProfileForm> {
  // Height is `_cm` in metric, `_feet` + `_inches` in imperial.
  final _cm = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _weight = TextEditingController();
  final _age = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill(ref.read(bodyUnitsProvider));
  }

  @override
  void dispose() {
    for (final c in [_cm, _feet, _inches, _weight, _age]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// Shows the stored (metric) profile in [units].
  void _fill(UnitSystem units) {
    final p = ref.read(riderProfileProvider);
    _age.text = p.age?.toString() ?? '';
    if (units == UnitSystem.metric) {
      _cm.text = p.heightCm?.toString() ?? '';
      _weight.text = p.weightKg == null ? '' : _trim(p.weightKg!);
      _feet.clear();
      _inches.clear();
    } else {
      final h = p.heightCm == null ? null : cmToFeetInches(p.heightCm!);
      _feet.text = h?.$1.toString() ?? '';
      _inches.text = h?.$2.toString() ?? '';
      _weight.text = p.weightKg == null ? '' : _trim(kgToPounds(p.weightKg!));
      _cm.clear();
    }
  }

  static num? _inRange(num? v, (int, int) range) =>
      v != null && v >= range.$1 && v <= range.$2 ? v : null;

  int? _heightCm(UnitSystem units) {
    if (units == UnitSystem.metric) {
      return _inRange(int.tryParse(_cm.text), RiderProfile.heightRange)?.toInt();
    }
    final ft = int.tryParse(_feet.text);
    final inch = _inches.text.isEmpty ? 0.0 : double.tryParse(_inches.text);
    if (ft == null || inch == null || ft < 0 || inch < 0 || inch >= 12) return null;
    return _inRange(feetInchesToCm(ft, inch), RiderProfile.heightRange)?.toInt();
  }

  double? _weightKg(UnitSystem units) {
    final v = double.tryParse(_weight.text);
    if (v == null) return null;
    final kg = units == UnitSystem.metric ? v : poundsToKg(v);
    return _inRange(kg, RiderProfile.weightRange)?.toDouble();
  }

  void _changed() {
    final units = ref.read(bodyUnitsProvider);
    ref.read(riderProfileProvider.notifier).update(RiderProfile(
          heightCm: _heightCm(units),
          weightKg: _weightKg(units),
          age: _inRange(int.tryParse(_age.text), RiderProfile.ageRange)?.toInt(),
          sex: ref.read(riderProfileProvider).sex,
        ));
    setState(() {}); // refresh error texts
  }

  String? _heightError(UnitSystem units) {
    final typed = units == UnitSystem.metric
        ? _cm.text.isNotEmpty
        : _feet.text.isNotEmpty || _inches.text.isNotEmpty;
    if (!typed || _heightCm(units) != null) return null;
    final (lo, hi) = RiderProfile.heightRange;
    return units == UnitSystem.metric ? 'Enter $lo–$hi' : 'Out of range';
  }

  String? _weightError(UnitSystem units) {
    if (_weight.text.isEmpty || _weightKg(units) != null) return null;
    final (lo, hi) = RiderProfile.weightRange;
    return units == UnitSystem.metric
        ? 'Enter $lo–$hi'
        : 'Enter ${kgToPounds(lo.toDouble()).ceil()}–${kgToPounds(hi.toDouble()).floor()}';
  }

  String? _ageError() {
    if (_age.text.isEmpty ||
        _inRange(int.tryParse(_age.text), RiderProfile.ageRange) != null) {
      return null;
    }
    final (lo, hi) = RiderProfile.ageRange;
    return 'Enter $lo–$hi';
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(bodyUnitsProvider);
    // Same stored values, shown in the new units.
    ref.listen(bodyUnitsProvider, (_, next) => setState(() => _fill(next)));
    final sex = ref.watch(riderProfileProvider.select((p) => p.sex));
    final imperial = units == UnitSystem.imperial;

    Widget field(String label, String suffix, TextEditingController c,
            {String? error, bool decimal = false}) =>
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _changed(),
          ),
        );
    const gap = SizedBox(width: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (imperial) ...[
            field('Height', 'ft', _feet, error: _heightError(units)),
            gap,
            field('Inches', 'in', _inches, decimal: true),
          ] else
            field('Height', 'cm', _cm, error: _heightError(units)),
          gap,
          field('Weight', imperial ? 'lb' : 'kg', _weight,
              error: _weightError(units), decimal: true),
          gap,
          field('Age', 'years', _age, error: _ageError()),
        ]),
        const SizedBox(height: 16),
        SegmentedButton<Sex>(
          emptySelectionAllowed: true,
          segments: [
            for (final s in Sex.values) ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {if (sex != null) sex},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            final current = ref.read(riderProfileProvider);
            ref.read(riderProfileProvider.notifier).update(current.copyWith(sex: s.first));
          },
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
