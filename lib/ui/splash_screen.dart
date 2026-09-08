import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app.dart';
import 'theme.dart';

/// Écran de lancement (Splash Screen) avec animations :
/// - Nuage qui apparaît en flottant
/// - Goutte d'eau qui tombe du nuage
/// - Effet d'onde/piscine à l'impact de la goutte
/// - Titre et sous-titre AquaControl
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;

  // Animations dérivées
  late final Animation<double> _cloudFade;
  late final Animation<Offset> _cloudSlide;
  late final Animation<double> _dropFall;
  late final Animation<double> _dropScale;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // 1. Nuage (0.0 -> 0.35)
    _cloudFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _cloudSlide = Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
          ),
        );

    // 2. Goutte d'eau (0.3 -> 0.65)
    _dropFall = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.65, curve: Curves.easeIn),
      ),
    );
    _dropScale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(begin: 0.0, end: 1.2),
            weight: 30,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.2, end: 1.0),
            weight: 30,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.0, end: 0.0),
            weight: 40,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.3, 0.65, curve: Curves.easeInOut),
          ),
        );

    // 3. Onde / Vague de la piscine (0.6 -> 0.9)
    _rippleScale = Tween<double>(begin: 0.2, end: 2.2).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 0.9, curve: Curves.easeOutCubic),
      ),
    );
    _rippleOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
      ),
    );

    // 4. Titre AquaControl (0.5 -> 0.85)
    _titleFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.5, 0.85, curve: Curves.easeIn),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.5, 0.85, curve: Curves.easeOutCubic),
          ),
        );

    _mainController.forward();

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToHome();
      }
    });
  }

  void _goToHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ShellView(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF031019),
              const Color(0xFF062335),
              const Color(0xFF093148),
            ]
          : [
              const Color(0xFFE2F0F7),
              const Color(0xFFC7E5F3),
              const Color(0xFFA5D5EC),
            ],
    );

    return Scaffold(
      body: GestureDetector(
        onTap: _goToHome,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(gradient: bgGradient),
          child: Stack(
            children: [
              // Motif arrière-plan piscine (vagues de fond)
              Positioned.fill(
                child: CustomPaint(
                  painter: _PoolBackgroundPainter(
                    color: AppTheme.chlorine.withValues(
                      alpha: isDark ? 0.08 : 0.12,
                    ),
                  ),
                ),
              ),

              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Zone Animation : Nuage + Goutte + Bassin
                    SizedBox(
                      width: 260,
                      height: 240,
                      child: AnimatedBuilder(
                        animation: _mainController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // 1. Bassin de la piscine & effet d'onde
                              Positioned(
                                bottom: 20,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Onde d'impact
                                    Transform.scale(
                                      scale: _rippleScale.value,
                                      child: Opacity(
                                        opacity: _rippleOpacity.value,
                                        child: Container(
                                          width: 100,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: AppTheme.chlorine,
                                              width: 3.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Illustration du bassin de piscine
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(26),
                                        gradient: LinearGradient(
                                          colors: [
                                            AppTheme.chlorine,
                                            AppTheme.chlorine.withValues(
                                              alpha: 0.7,
                                            ),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.chlorine.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.pool_rounded,
                                            color: Colors.white,
                                            size: 26,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Ma Piscine',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 2. Trajectoire de la goutte d'eau (tombe du nuage vers la piscine)
                              Positioned(
                                top: 75 + (_dropFall.value * 95),
                                child: Transform.scale(
                                  scale: _dropScale.value,
                                  child: Opacity(
                                    opacity: _dropScale.value > 0 ? 1.0 : 0.0,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: AppTheme.chlorine,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.chlorine.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.water_drop,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // 3. Nuage animé (en haut)
                              Positioned(
                                top: 15,
                                child: SlideTransition(
                                  position: _cloudSlide,
                                  child: FadeTransition(
                                    opacity: _cloudFade,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.90,
                                              ),
                                        borderRadius: BorderRadius.circular(30),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.25 : 0.08,
                                            ),
                                            blurRadius: 15,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.cloud_outlined,
                                            size: 38,
                                            color: isDark
                                                ? Colors.lightBlueAccent
                                                : AppTheme.chlorine,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Titre & Branding
                    SlideTransition(
                      position: _titleSlide,
                      child: FadeTransition(
                        opacity: _titleFade,
                        child: Column(
                          children: [
                            Text(
                              'AQUACONTROL',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.0,
                                color: isDark ? Colors.white : AppTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'PILOTAGE & MÉTÉO PISCINE',
                              style: AppTheme.eyebrow.copyWith(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : AppTheme.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Indication "Toucher pour passer" en bas
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _titleFade,
                  child: Text(
                    'Appuyez pour passer',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : AppTheme.inkMuted.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter pour le motif ondulé d'arrière-plan de la piscine
class _PoolBackgroundPainter extends CustomPainter {
  const _PoolBackgroundPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    for (double i = 0; i < size.height; i += 60) {
      path.moveTo(0, i);
      for (double x = 0; x <= size.width; x += 40) {
        path.relativeQuadraticBezierTo(20, math.sin((x + i) / 30) * 12, 40, 0);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PoolBackgroundPainter oldDelegate) =>
      color != oldDelegate.color;
}
