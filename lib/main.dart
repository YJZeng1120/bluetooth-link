import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const BluetoothLinkApp());
}

class BluetoothLinkApp extends StatelessWidget {
  const BluetoothLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '藍牙防丟失',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
