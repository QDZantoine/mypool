import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class HoldButton extends StatefulWidget {
  const HoldButton({
    required this.label,
    required this.icon,
    required this.onPressStart,
    required this.onPressEnd,
    this.enabled = true,
    this.color,
    this.disabledExplanation,
    super.key,
  });

  final String label;
  final IconData icon;

  final VoidCallback onPressStart;

  final VoidCallback onPressEnd;

  final bool enabled;
  final Color? color;

  final String? disabledExplanation;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  bool _held = false;

  void _start(PointerDownEvent event) {
    if (!widget.enabled || _held) {
      return;
    }
    setState(() => _held = true);
    widget.onPressStart();
  }

  void _end() {
    if (!_held) {
      return;
    }
    setState(() => _held = false);
    widget.onPressEnd();
  }

  @override
  void dispose() {

    if (_held) {
      _held = false;
      final VoidCallback onPressEnd = widget.onPressEnd;
      scheduleMicrotask(onPressEnd);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = widget.color ?? theme.colorScheme.primary;
    final Color background = widget.enabled
        ? (_held ? base : base.withValues(alpha: 0.16))
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = widget.enabled
        ? (_held ? theme.colorScheme.onPrimary : base)
        : theme.disabledColor;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      hint:
          'Maintenez le doigt appuyé. Le mouvement s’arrête au '
          'relâchement.',
      child: Listener(

        onPointerDown: _start,
        onPointerUp: (PointerUpEvent event) => _end(),
        onPointerCancel: (PointerCancelEvent event) => _end(),

        onPointerMove: (PointerMoveEvent event) {
          if (!_held) {
            return;
          }
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          if (!box.size.contains(box.globalToLocal(event.position))) {
            _end();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(

          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          constraints: const BoxConstraints(
            minHeight: AppTheme.touchTarget * 1.6,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.enabled ? base : theme.dividerColor,
              width: _held ? 3 : 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon, size: 40, color: foreground),
              const SizedBox(height: 8),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: foreground),
              ),
              if (!widget.enabled && widget.disabledExplanation != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.disabledExplanation!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
