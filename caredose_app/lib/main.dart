import 'package:flutter/material.dart';

import 'theme.dart';

void main() {
  runApp(MaterialApp(
    title: 'CareDose',
    theme: buildTheme(),
    home: const Scaffold(body: Center(child: Text('CareDose'))),
  ));
}
