import 'dart:async';

import 'package:flutter/material.dart';

const welcomeText = 'ยินดีต้อนรับ';

/// Opening screen: the logo and [welcomeText] typed out letter by letter (about 2 seconds in all),
/// then a fade into [child]. A tap skips the wait.
class WelcomeSplash extends StatefulWidget {
  const WelcomeSplash({super.key, required this.child});
  final Widget child;

  @override
  State<WelcomeSplash> createState() => _WelcomeSplashState();
}

class _WelcomeSplashState extends State<WelcomeSplash> {
  // Thai vowel and tone marks combine with their consonant, so type grapheme clusters, not code units.
  final _letters = welcomeText.characters.toList();
  Timer? _timer;
  int _typed = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (_typed < _letters.length) {
        setState(() => _typed++);
      } else {
        t.cancel();
        // hold the finished text for a moment so it can be read
        _timer = Timer(const Duration(milliseconds: 700), _finish);
      }
    });
  }

  void _finish() {
    _timer?.cancel();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : Scaffold(
              key: const ValueKey('welcome'),
              backgroundColor: Colors.white,
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _finish,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/images/logo.png', height: 200, semanticLabel: 'CareDose ยาอุ่นใจ'),
                    const SizedBox(height: 24),
                    Text(
                      _letters.take(_typed).join(),
                      key: const ValueKey('welcome-text'),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2B8A9E)),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}
