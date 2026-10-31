// =============================================================================
// Electricity Bill Calculator  (Flutter + Dart, Material 3)
//
// Single-file layout so it runs as-is in FlutLab. The file is organised into
// three clearly separated layers; each can be moved to its own file later:
//
//   1. DOMAIN      – pure Dart business logic: slabs, bill, calculator,
//                    exceptions.   -> lib/domain/...
//   2. FORMATTING  – small helpers for money / number display.
//   3. UI          – Flutter widgets that only *use* the domain classes.
//
// NOTE: Layers 1 and the form logic (validators, calculate, reset) are
// unchanged from the previous version. Only the visual design is new.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ElectricityBillApp());

// =============================================================================
// 1. DOMAIN LAYER (pure Dart business logic)
// =============================================================================

/// Base type for every error the domain layer can raise, so the UI can catch
/// one type and show a friendly message.
abstract class ElectricityBillException implements Exception {
  final String message;
  const ElectricityBillException(this.message);

  @override
  String toString() => message;
}

/// Thrown when a slab / tariff configuration is invalid (gaps, overlaps...).
class InvalidTariffException extends ElectricityBillException {
  const InvalidTariffException(String message) : super(message);
}

/// Thrown when the *input* of a calculation is invalid (negative units...).
class BillCalculationException extends ElectricityBillException {
  const BillCalculationException(String message) : super(message);
}

/// One tier of the tariff.
///
/// A slab covers the units in the range (minUnits, maxUnits].
/// `maxUnits == null` means "no upper limit" (the last, open-ended slab).
class TariffSlab {
  final double minUnits;
  final double? maxUnits;
  final double ratePerUnit;

  TariffSlab({
    required this.minUnits,
    this.maxUnits,
    required this.ratePerUnit,
  }) {
    final upper = maxUnits;
    if (minUnits.isNaN || minUnits < 0) {
      throw const InvalidTariffException('Slab start must be zero or greater.');
    }
    if (upper != null && (upper.isNaN || upper <= minUnits)) {
      throw InvalidTariffException(
          'Slab end ($upper) must be greater than its start ($minUnits).');
    }
    if (ratePerUnit.isNaN || ratePerUnit < 0) {
      throw const InvalidTariffException('Rate per unit cannot be negative.');
    }
  }

  bool get isUnbounded => maxUnits == null;

  /// How many of [totalUnits] fall inside this slab.
  ///
  /// Example: slab (100, 300], totalUnits = 250  ->  150 units in this slab.
  double unitsConsumedIn(double totalUnits) {
    if (totalUnits <= minUnits) return 0;
    final upper = maxUnits;
    final cappedTop =
        (upper == null || totalUnits < upper) ? totalUnits : upper;
    return cappedTop - minUnits;
  }
}

/// The cost produced by a single slab for a given consumption.
class SlabCharge {
  final TariffSlab slab;
  final double unitsInSlab;
  final double amount;

  const SlabCharge({
    required this.slab,
    required this.unitsInSlab,
    required this.amount,
  });
}

/// Immutable result of a bill calculation.
class ElectricityBill {
  final double consumedUnits;
  final List<SlabCharge> slabCharges;
  final double energyCharge;
  final double fixedCharge;
  final double taxPercent;
  final double taxAmount;
  final double totalAmount;

  const ElectricityBill({
    required this.consumedUnits,
    required this.slabCharges,
    required this.energyCharge,
    required this.fixedCharge,
    required this.taxPercent,
    required this.taxAmount,
    required this.totalAmount,
  });

  /// Effective cost per unit after all charges and taxes.
  double get averageRatePerUnit =>
      consumedUnits > 0 ? totalAmount / consumedUnits : 0;
}

/// Calculates bills from a slab configuration, a fixed charge and a tax rate.
class ElectricityBillCalculator {
  /// Upper sanity limit for a single billing cycle.
  static const double maxSupportedUnits = 100000;

  final List<TariffSlab> slabs;
  final double fixedCharge;
  final double taxPercent;

  ElectricityBillCalculator({
    required List<TariffSlab> slabs,
    this.fixedCharge = 0,
    this.taxPercent = 0,
  }) : slabs = List<TariffSlab>.unmodifiable(slabs) {
    _validateConfiguration();
  }

  /// Sample residential tariff:
  /// first 100 units @ 3.50, next 200 units @ 5.00, remaining @ 7.50.
  factory ElectricityBillCalculator.residential() {
    return ElectricityBillCalculator(
      slabs: [
        TariffSlab(minUnits: 0, maxUnits: 100, ratePerUnit: 3.50),
        TariffSlab(minUnits: 100, maxUnits: 300, ratePerUnit: 5.00),
        TariffSlab(minUnits: 300, ratePerUnit: 7.50),
      ],
      fixedCharge: 50,
      taxPercent: 5,
    );
  }

  /// Same slabs, different fixed charge / tax (used by the UI toggles).
  ElectricityBillCalculator copyWith({
    double? fixedCharge,
    double? taxPercent,
  }) {
    return ElectricityBillCalculator(
      slabs: slabs,
      fixedCharge: fixedCharge ?? this.fixedCharge,
      taxPercent: taxPercent ?? this.taxPercent,
    );
  }

  /// Ensures the slabs form one continuous ladder starting at 0:
  /// (0, a] -> (a, b] -> (b, c] -> ... -> (z, infinity)
  void _validateConfiguration() {
    if (slabs.isEmpty) {
      throw const InvalidTariffException('At least one slab is required.');
    }
    if (fixedCharge.isNaN || fixedCharge < 0) {
      throw const InvalidTariffException('Fixed charge cannot be negative.');
    }
    if (taxPercent.isNaN || taxPercent < 0 || taxPercent > 100) {
      throw const InvalidTariffException('Tax must be between 0 and 100 %.');
    }
    if (slabs.first.minUnits != 0) {
      throw const InvalidTariffException('The first slab must start at 0.');
    }

    for (var i = 0; i < slabs.length; i++) {
      final slab = slabs[i];
      final isLast = i == slabs.length - 1;

      if (isLast) {
        if (!slab.isUnbounded) {
          throw const InvalidTariffException(
              'The last slab must be open-ended (no maximum).');
        }
      } else {
        if (slab.isUnbounded) {
          throw InvalidTariffException(
              'Only the last slab can be open-ended (slab ${i + 1}).');
        }
        if (slabs[i + 1].minUnits != slab.maxUnits) {
          throw InvalidTariffException(
              'Gap or overlap between slab ${i + 1} and slab ${i + 2}.');
        }
      }
    }
  }

  /// Computes the full bill for [units] consumed.
  ElectricityBill calculate(double units) {
    if (units.isNaN || units.isInfinite) {
      throw const BillCalculationException('Units must be a valid number.');
    }
    if (units < 0) {
      throw const BillCalculationException('Units cannot be negative.');
    }
    if (units > maxSupportedUnits) {
      throw BillCalculationException(
          'Units exceed the supported limit of ${maxSupportedUnits.toInt()}.');
    }

    // Incremental (tiered) pricing: every slab charges only the units that
    // fall inside it, e.g. 250 units -> 100 @ A + 150 @ B.
    final charges = <SlabCharge>[];
    var energyCharge = 0.0;

    for (final slab in slabs) {
      final unitsInSlab = slab.unitsConsumedIn(units);
      final amount = _round2(unitsInSlab * slab.ratePerUnit);
      energyCharge += amount;
      charges.add(SlabCharge(
        slab: slab,
        unitsInSlab: unitsInSlab,
        amount: amount,
      ));
    }
    energyCharge = _round2(energyCharge);

    // Tax (VAT / sales tax) applies to energy + fixed charges.
    final taxableAmount = energyCharge + fixedCharge;
    final taxAmount = _round2(taxableAmount * taxPercent / 100);
    final total = _round2(taxableAmount + taxAmount);

    return ElectricityBill(
      consumedUnits: units,
      slabCharges: List<SlabCharge>.unmodifiable(charges),
      energyCharge: energyCharge,
      fixedCharge: fixedCharge,
      taxPercent: taxPercent,
      taxAmount: taxAmount,
      totalAmount: total,
    );
  }

  /// Rounds to 2 decimals so every line on the bill adds up exactly.
  static double _round2(double value) => (value * 100).roundToDouble() / 100;
}

// =============================================================================
// 2. FORMATTING HELPERS
// =============================================================================

const String kCurrencySymbol = '₹';

/// 1234.5 -> "₹1,234.50"
String formatMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final remaining = digits.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) buffer.write(',');
  }
  return '$kCurrencySymbol${buffer.toString()}.${parts[1]}';
}

/// 250.0 -> "250", 250.5 -> "250.50"
String formatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

String slabRangeLabel(TariffSlab slab) {
  final upper = slab.maxUnits;
  return upper == null
      ? 'Above ${formatNumber(slab.minUnits)} units'
      : '${formatNumber(slab.minUnits)} – ${formatNumber(upper)} units';
}

// =============================================================================
// 3. UI LAYER (Flutter, Material 3)
// =============================================================================

// ------------------------------- design tokens -------------------------------

const Color kBrandColor = Color(0xFF6D4AFF);

const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0EA5E9)],
);

/// One accent colour per slab, reused in the hero bar and the breakdown.
const List<Color> kSlabColors = [
  Color(0xFFFFC145), // amber
  Color(0xFF14C8A0), // mint
  Color(0xFFFF6B9D), // pink
  Color(0xFF4CC9F0), // sky
  Color(0xFFFF9F6B), // orange
];

Color slabColor(int index) => kSlabColors[index % kSlabColors.length];

class ElectricityBillApp extends StatelessWidget {
  const ElectricityBillApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electricity Bill Calculator',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kBrandColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kBrandColor,
        brightness: Brightness.dark,
      ),
      home: const BillCalculatorPage(),
    );
  }
}

class BillCalculatorPage extends StatefulWidget {
  const BillCalculatorPage({Key? key}) : super(key: key);

  @override
  State<BillCalculatorPage> createState() => _BillCalculatorPageState();
}

class _BillCalculatorPageState extends State<BillCalculatorPage> {
  final _formKey = GlobalKey<FormState>();

  // The default tariff; fixed charge & tax are overridden from the form.
  final ElectricityBillCalculator _baseCalculator =
      ElectricityBillCalculator.residential();

  late final TextEditingController _unitsController;
  late final TextEditingController _fixedController;
  late final TextEditingController _taxController;

  bool _includeFixed = true;
  bool _includeTax = true;
  bool _isCalculating = false;

  ElectricityBill? _bill;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController();
    _fixedController =
        TextEditingController(text: formatNumber(_baseCalculator.fixedCharge));
    _taxController =
        TextEditingController(text: formatNumber(_baseCalculator.taxPercent));
  }

  @override
  void dispose() {
    _unitsController.dispose();
    _fixedController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
    });

    // Short delay purely for UX feedback (spinner + animated reveal).
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    try {
      final calculator = _baseCalculator.copyWith(
        fixedCharge:
            _includeFixed ? double.parse(_fixedController.text.trim()) : 0,
        taxPercent: _includeTax ? double.parse(_taxController.text.trim()) : 0,
      );
      final bill =
          calculator.calculate(double.parse(_unitsController.text.trim()));

      setState(() {
        _bill = bill;
        _isCalculating = false;
      });
    } on ElectricityBillException catch (e) {
      setState(() {
        _bill = null;
        _errorMessage = e.message;
        _isCalculating = false;
      });
    }
  }

  void _reset() {
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    setState(() {
      _unitsController.clear();
      _fixedController.text = formatNumber(_baseCalculator.fixedCharge);
      _taxController.text = formatNumber(_baseCalculator.taxPercent);
      _includeFixed = true;
      _includeTax = true;
      _bill = null;
      _errorMessage = null;
    });
  }

  // ------------------------------------------------------------- validators

  String? _validateUnits(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the units consumed';
    final parsed = double.tryParse(text);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 'Enter a valid number (e.g. 250 or 250.5)';
    }
    if (parsed < 0) return 'Units cannot be negative';
    if (parsed > ElectricityBillCalculator.maxSupportedUnits) {
      return 'Maximum supported is '
          '${ElectricityBillCalculator.maxSupportedUnits.toInt()} units';
    }
    return null;
  }

  String? _validateOptionalAmount(
    String? value, {
    required bool enabled,
    required String label,
    double? max,
  }) {
    if (!enabled) return null; // toggled off -> ignored
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required (or switch it off)';
    final parsed = double.tryParse(text);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 'Enter a valid number';
    }
    if (parsed < 0) return '$label cannot be negative';
    if (max != null && parsed > max) {
      return '$label cannot exceed ${formatNumber(max)}';
    }
    return null;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bill = _bill;
    final showResults = bill != null && !_isCalculating;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Container(
        // Soft brand-tinted wash behind the whole screen.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withOpacity(0.14),
              scheme.surface,
              scheme.surface,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _HeroHeader(bill: bill, isCalculating: _isCalculating),
                  const SizedBox(height: 18),
                  _buildInputCard(context),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _errorMessage == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _ErrorBanner(message: _errorMessage!),
                          ),
                  ),
                  if (showResults)
                    // New key per bill -> staggered reveal replays each time.
                    KeyedSubtree(
                      key: ValueKey<ElectricityBill>(bill!),
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          _Reveal(
                            delay: Duration.zero,
                            child: _ChargesSummaryCard(bill: bill),
                          ),
                          const SizedBox(height: 18),
                          _Reveal(
                            delay: const Duration(milliseconds: 140),
                            child: _SlabBreakdownCard(bill: bill),
                          ),
                          const SizedBox(height: 18),
                          _Reveal(
                            delay: const Duration(milliseconds: 260),
                            child: const _FootnoteBadge(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(BuildContext context) {
    return _SurfaceCard(
      child: Form(
        key: _formKey,
        // Validate as the user types (after first interaction).
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(number: 1, title: 'Consumption'),
            const SizedBox(height: 14),
            TextFormField(
              controller: _unitsController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              // Allow '-' on purpose so negative input gets a clear message.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _calculate(),
              validator: _validateUnits,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: _fieldDecoration(
                context,
                label: 'Units consumed',
                hint: 'e.g. 250',
                icon: Icons.bolt_rounded,
                suffixText: 'kWh',
              ),
            ),
            const SizedBox(height: 26),
            const _SectionTitle(number: 2, title: 'Charges'),
            const SizedBox(height: 14),
            _OptionPanel(
              icon: Icons.home_repair_service_outlined,
              title: 'Fixed service charge',
              subtitle: 'Monthly meter / service fee',
              value: _includeFixed,
              onChanged: (v) => setState(() => _includeFixed = v),
              field: TextFormField(
                controller: _fixedController,
                enabled: _includeFixed,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                validator: (v) => _validateOptionalAmount(v,
                    enabled: _includeFixed, label: 'Fixed charge'),
                decoration: _fieldDecoration(
                  context,
                  label: 'Fixed charge',
                  prefixText: '$kCurrencySymbol ',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _OptionPanel(
              icon: Icons.account_balance_outlined,
              title: 'Tax (VAT / sales tax)',
              subtitle: 'Applied on energy + fixed charges',
              value: _includeTax,
              onChanged: (v) => setState(() => _includeTax = v),
              field: TextFormField(
                controller: _taxController,
                enabled: _includeTax,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                validator: (v) => _validateOptionalAmount(v,
                    enabled: _includeTax, label: 'Tax rate', max: 100),
                decoration: _fieldDecoration(
                  context,
                  label: 'Tax rate',
                  suffixText: '%',
                ),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: _GradientButton(
                    onPressed: _isCalculating ? null : _calculate,
                    loading: _isCalculating,
                    icon: Icons.calculate_rounded,
                    label: _isCalculating ? 'Calculating…' : 'Calculate bill',
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isCalculating ? null : _reset,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared styling helpers
// -----------------------------------------------------------------------------

/// Rounded, filled input style used by every text field.
InputDecoration _fieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  IconData? icon,
  String? prefixText,
  String? suffixText,
}) {
  final scheme = Theme.of(context).colorScheme;

  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefixText,
    suffixText: suffixText,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: scheme.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: border(scheme.outline.withOpacity(0.25)),
    enabledBorder: border(scheme.outline.withOpacity(0.25)),
    disabledBorder: border(scheme.outline.withOpacity(0.12)),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 2),
  );
}

/// Elevated, rounded container used for every content block.
class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;

  const _SurfaceCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.clip = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    final content = clip
        ? ClipRRect(borderRadius: radius, child: child)
        : Padding(padding: padding, child: child);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.outline.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// Numbered gradient badge + title ("1  Consumption").
class _SectionTitle extends StatelessWidget {
  final int number;
  final String title;

  const _SectionTitle({Key? key, required this.number, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: kBrandGradient,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Fades + slides its child in after [delay] (used for staggered results).
class _Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _Reveal({Key? key, required this.child, required this.delay})
      : super(key: key);

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero header
// -----------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  final ElectricityBill? bill;
  final bool isCalculating;

  const _HeroHeader({
    Key? key,
    required this.bill,
    required this.isCalculating,
  }) : super(key: key);

  static const TextStyle _amountStyle = TextStyle(
    fontSize: 50,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -1,
    height: 1.1,
  );

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final status =
        isCalculating ? 'Calculating…' : (b != null ? 'Calculated' : 'Ready');

    Widget amount;
    if (isCalculating) {
      amount = const SizedBox(
        key: ValueKey('loading'),
        height: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 34,
            height: 34,
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          ),
        ),
      );
    } else if (b == null) {
      amount = Text(
        formatMoney(0),
        key: const ValueKey('idle'),
        style: _amountStyle.copyWith(color: Colors.white.withOpacity(0.45)),
      );
    } else {
      // Count-up animation from 0 to the final total.
      amount = TweenAnimationBuilder<double>(
        key: const ValueKey('total'),
        tween: Tween<double>(begin: 0, end: b.totalAmount),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) =>
            Text(formatMoney(value), style: _amountStyle),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: kBrandColor.withOpacity(0.40),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Decorative glass circles.
            const Positioned(
                right: -40,
                top: -40,
                child: _GlowCircle(size: 170, opacity: 0.12)),
            const Positioned(
                left: -50,
                bottom: -60,
                child: _GlowCircle(size: 190, opacity: 0.09)),
            const Positioned(
                right: 60,
                bottom: 30,
                child: _GlowCircle(size: 54, opacity: 0.10)),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Electricity Bill',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            key: ValueKey(status),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'TOTAL PAYABLE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: amount,
                    ),
                    if (b == null && !isCalculating) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Enter your units below to see the bill',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.80),
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (b != null && !isCalculating) ...[
                      const SizedBox(height: 18),
                      _UsageBar(bill: b),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _GlassChip(
                            icon: Icons.speed_rounded,
                            label: '${formatNumber(b.consumedUnits)} kWh',
                          ),
                          _GlassChip(
                            icon: Icons.price_change_outlined,
                            label:
                                'Avg ${formatMoney(b.averageRatePerUnit)} / unit',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowCircle({Key? key, required this.size, required this.opacity})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _GlassChip({Key? key, required this.icon, required this.label})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked bar showing how the consumed units are split across slabs.
class _UsageBar extends StatelessWidget {
  final ElectricityBill bill;

  const _UsageBar({Key? key, required this.bill}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    final legend = <Widget>[];

    for (var i = 0; i < bill.slabCharges.length; i++) {
      final charge = bill.slabCharges[i];
      if (charge.unitsInSlab <= 0) continue; // skip slabs that were not reached

      // Flex proportional to the units in that slab.
      final flex = (charge.unitsInSlab * 100).round().clamp(1, 100000000);
      segments.add(Expanded(
        flex: flex,
        child: Container(
          margin: EdgeInsets.only(right: segments.isEmpty ? 0 : 0),
          color: slabColor(i),
        ),
      ));
      legend.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: slabColor(i), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'Slab ${i + 1} · ${formatNumber(charge.unitsInSlab)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: Row(children: segments),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: legend),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Input widgets
// -----------------------------------------------------------------------------

/// A toggleable option card that expands to reveal its text field.
class _OptionPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget field;

  const _OptionPanel({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.field,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value
            ? scheme.primary.withOpacity(0.07)
            : scheme.onSurface.withOpacity(0.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: value
              ? scheme.primary.withOpacity(0.35)
              : scheme.outline.withOpacity(0.20),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: value
                      ? scheme.primary
                      : scheme.onSurface.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: value ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: value
                ? Padding(padding: const EdgeInsets.only(top: 14), child: field)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  final String label;

  const _GradientButton({
    Key? key,
    required this.onPressed,
    required this.loading,
    required this.icon,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.75,
      child: Container(
        decoration: BoxDecoration(
          gradient: kBrandGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: loading
                        ? const SizedBox(
                            key: ValueKey('spinner'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Icon(icon,
                            key: const ValueKey('icon'), color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Result widgets
// -----------------------------------------------------------------------------

/// Receipt-style summary: energy / fixed / tax and the total.
class _ChargesSummaryCard extends StatelessWidget {
  final ElectricityBill bill;

  const _ChargesSummaryCard({Key? key, required this.bill}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Bill summary',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryRow(
            icon: Icons.bolt_rounded,
            label: 'Energy charges',
            value: formatMoney(bill.energyCharge),
          ),
          _SummaryRow(
            icon: Icons.home_repair_service_outlined,
            label: 'Fixed service charge',
            value: formatMoney(bill.fixedCharge),
          ),
          _SummaryRow(
            icon: Icons.account_balance_outlined,
            label: 'Tax (${formatNumber(bill.taxPercent)}%)',
            value: formatMoney(bill.taxAmount),
          ),
          const SizedBox(height: 10),
          const _DashedDivider(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total payable',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  formatMoney(bill.totalAmount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(
            value,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Dashed "tear-off" line for the receipt look.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline.withOpacity(0.45);

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 10).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: 5,
              height: 1.5,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }
}

/// Expandable accordion with per-slab cost.
class _SlabBreakdownCard extends StatelessWidget {
  final ElectricityBill bill;

  const _SlabBreakdownCard({Key? key, required this.bill}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SurfaceCard(
      clip: true,
      child: Theme(
        // Hide the default divider lines of ExpansionTile.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.layers_rounded, color: scheme.primary),
          ),
          title: Text(
            'Slab rates breakdown',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('Cost generated by each tier'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            for (var i = 0; i < bill.slabCharges.length; i++)
              _SlabRow(
                index: i,
                charge: bill.slabCharges[i],
                energyTotal: bill.energyCharge,
              ),
          ],
        ),
      ),
    );
  }
}

class _SlabRow extends StatelessWidget {
  final int index; // zero-based
  final SlabCharge charge;
  final double energyTotal;

  const _SlabRow({
    Key? key,
    required this.index,
    required this.charge,
    required this.energyTotal,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = slabColor(index);
    final used = charge.unitsInSlab > 0;

    // Share of the energy bill produced by this slab (drives the bar).
    final share = energyTotal > 0 ? charge.amount / energyTotal : 0.0;

    return Opacity(
      opacity: used ? 1 : 0.5, // dim slabs that were not reached
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slabRangeLabel(charge.slab),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        used
                            ? '${formatNumber(charge.unitsInSlab)} units × '
                                '$kCurrencySymbol${charge.slab.ratePerUnit.toStringAsFixed(2)}'
                            : 'Not reached · '
                                '$kCurrencySymbol${charge.slab.ratePerUnit.toStringAsFixed(2)} / unit',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatMoney(charge.amount),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: share),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: color.withOpacity(0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(share * 100).toStringAsFixed(1)}% of energy charges',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FootnoteBadge extends StatelessWidget {
  const _FootnoteBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Tiered pricing: each slab charges only the units inside it.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.error.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded,
                color: scheme.onErrorContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
