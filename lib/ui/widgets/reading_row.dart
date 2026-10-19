import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';
import 'measure_scale.dart';
import 'value_display.dart';

class ReadingRow extends StatelessWidget {
  const ReadingRow({
    required this.parameter,
    required this.value,
    this.age,
    this.onTap,
    super.key,
  });

  final WaterParameter parameter;

  final double? value;

  final Duration? age;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParameterStatus status = parameter.statusOf(value);
    final Color statusColor = AppTheme.colorForStatus(status);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gutter,
        vertical: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      parameter.label.toUpperCase(),
                      style: AppTheme.eyebrow.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: AppTheme.gap * 2),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppTheme.gap * 2),

                        Flexible(
                          child: Text(
                            age == null
                                ? AppTheme.labelForStatus(status)
                                : '${AppTheme.labelForStatus(status)} · '
                                      '${_formatAge(age!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.gap * 3),

              ValueDisplay(
                value: value == null ? null : _bare(value!),
                unit: parameter.unit,
                size: ValueSize.small,
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          MeasureScale(parameter: parameter, value: value),
        ],
      ),
    );

    if (onTap == null) {
      return MergeSemantics(child: content);
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: content,
        ),
      ),
    );
  }

  String _bare(double v) =>
      v.toStringAsFixed(parameter.decimals).replaceAll('.', ',');

  static String _formatAge(Duration age) {
    if (age.inMinutes < 2) {
      return 'à l’instant';
    }
    if (age.inHours < 1) {
      return 'il y a ${age.inMinutes} min';
    }
    if (age.inHours < 24) {
      return 'il y a ${age.inHours} h';
    }
    final int days = age.inDays;
    return 'il y a $days jour${days > 1 ? 's' : ''}';
  }
}
