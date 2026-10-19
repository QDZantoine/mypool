import 'package:flutter/material.dart';

import '../theme.dart';

class ValueDisplay extends StatelessWidget {
  const ValueDisplay({
    required this.value,
    this.unit,
    this.size = ValueSize.medium,
    this.color,
    this.emptyLabel = 'non mesuré',
    this.alignEnd = false,
    super.key,
  });

  final String? value;

  final String? unit;
  final ValueSize size;
  final Color? color;

  final String emptyLabel;

  final bool alignEnd;

  static const double unitScale = 0.42;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle numberStyle = switch (size) {
      ValueSize.large => theme.textTheme.displayLarge!,
      ValueSize.medium => theme.textTheme.displayMedium!,
      ValueSize.small => theme.textTheme.displaySmall!,
    };

    if (value == null) {

      return Text(
        emptyLabel,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }

    final double unitSize = (numberStyle.fontSize ?? 32) * unitScale;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          text: value,
          style: numberStyle.copyWith(color: color),
          children: <InlineSpan>[
            if (unit != null && unit!.isNotEmpty)
              TextSpan(

                text: '\u202F${unit!}',
                style: numberStyle.copyWith(
                  color: color ?? theme.colorScheme.outline,
                  fontSize: unitSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum ValueSize { large, medium, small }

class EmptyValue extends StatelessWidget {
  const EmptyValue({required this.label, this.hint, super.key});

  final String label;

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.remove_circle_outline,
              size: 22,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: AppTheme.gap * 2),
          Text(hint!, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}
