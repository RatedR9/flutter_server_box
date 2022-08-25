import 'package:flutter/material.dart';
import 'package:toolbox/data/res/color.dart';
import 'package:toolbox/view/widget/round_rect_card.dart';

Widget buildInput(BuildContext context, TextEditingController controller,
    {int maxLines = 20,
    String? hint,
    Function(String)? onSubmitted,
    bool? obscureText}) {
  return RoundRectCard(
    TextField(
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
          fillColor: Theme.of(context).cardColor,
          hintText: hint,
          filled: true,
          border: InputBorder.none),
      controller: controller,
      obscureText: obscureText ?? false,
    ),
  );
}

InputDecoration buildDecoration(String label,
    {TextStyle? textStyle, IconData? icon, String? hint}) {
  return InputDecoration(
      labelText: label,
      labelStyle: textStyle,
      hintText: hint,
      icon: Icon(
        icon,
        color: primaryColor,
      ));
}
