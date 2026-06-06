import 'package:flutter/material.dart';

class ParchmentScaffold extends StatelessWidget {
  final Widget child;

  const ParchmentScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_view.png',
              fit: BoxFit.cover,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
