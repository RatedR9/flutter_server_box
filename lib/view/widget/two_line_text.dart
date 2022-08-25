import 'package:flutter/material.dart';
import 'package:toolbox/data/res/font_style.dart';

class TwoLineText extends StatelessWidget {
  const TwoLineText({Key? key, required this.up, required this.down})
      : super(key: key);
  final String up;
  final String down;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          up,
          style: const TextStyle(fontSize: 15),
        ),
        Text(
          down,
          style: size11,
        )
      ],
    );
  }
}
