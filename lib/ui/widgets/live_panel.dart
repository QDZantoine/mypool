import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';
import 'value_display.dart';

class LivePanel extends StatelessWidget {
  const LivePanel({
    required this.verdict,
    required this.detail,
    required this.tone,
    required this.isLive,
    this.ph,
    this.temperatureC,
    this.linkLabel,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String verdict;

  final String detail;

  final Color tone;

  final bool isLive;

  final double? ph;
  final double? temperatureC;

  final String? linkLabel;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gutter,
        22,
        AppTheme.gutter,
        AppTheme.gutter,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[

              ExcludeSemantics(
                child: _LinkDot(isLive: isLive, tone: tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (linkLabel ?? '').toUpperCase(),
                  style: AppTheme.eyebrow.copyWith(
                    color: isLive ? tone : theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(verdict, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(detail, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.science_outlined),
              label: Text(actionLabel!),
            ),
          ],
          if (ph != null || temperatureC != null) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _BigValue(
                    label: 'pH',
                    value: ph,
                    parameter: WaterParameter.ph,
                  ),
                ),
                Container(
                  width: 1,
                  height: 64,
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _BigValue(
                    label: 'Température',
                    value: temperatureC,
                    parameter: WaterParameter.temperature,
                    unit: '°C',
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({
    required this.label,
    required this.value,
    required this.parameter,
    this.unit,
    this.alignEnd = false,
  });

  final String label;
  final double? value;
  final WaterParameter parameter;
  final String? unit;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParameterStatus status = parameter.statusOf(value);

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: AppTheme.eyebrow.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: AppTheme.gap),
        ValueDisplay(
          value: value
              ?.toStringAsFixed(parameter.decimals)
              .replaceAll('.', ','),
          unit: unit,
          alignEnd: alignEnd,
          emptyLabel: 'non mesuré',
        ),
        if (value != null) ...<Widget>[
          const SizedBox(height: AppTheme.gap),
          Text(
            AppTheme.labelForStatus(status),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.colorForStatus(status),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _LinkDot extends StatefulWidget {
  const _LinkDot({required this.isLive, required this.tone});

  final bool isLive;
  final Color tone;

  @override
  State<_LinkDot> createState() => _LinkDotState();
}

class _LinkDotState extends State<_LinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_LinkDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.isLive) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.isLive
        ? widget.tone
        : Theme.of(context).colorScheme.outline;

    if (!widget.isLive || MediaQuery.disableAnimationsOf(context)) {
      return _dot(color, 1.0);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) =>
          _dot(color, 0.45 + _controller.value * 0.55),
    );
  }

  Widget _dot(Color color, double opacity) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
