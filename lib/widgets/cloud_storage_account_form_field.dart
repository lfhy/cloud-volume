// 账号弹框里的表单字段与技术输入框工具，统一连接信息的输入体验。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 带字段名的表单项，避免输入后只能依赖 placeholder 辨识含义。
class CloudStorageLabeledField extends StatelessWidget {
  const CloudStorageLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// URL、密钥和用户名等技术字段应尽量按半角英文输入处理。
class CloudStorageTechnicalInput extends StatelessWidget {
  const CloudStorageTechnicalInput({
    super.key,
    required this.controller,
    this.placeholder,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final Widget? placeholder;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      enableIMEPersonalizedLearning: false,
      inputFormatters: const [_TechnicalFieldFormatter()],
      obscureText: obscureText,
      onChanged: onChanged,
    );
  }
}

/// 密码类字段关闭系统智能替换，但不改写用户实际输入的密码内容。
class CloudStorageSecretInput extends StatelessWidget {
  const CloudStorageSecretInput({
    super.key,
    required this.controller,
    this.placeholder,
  });

  final TextEditingController controller;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: controller,
      placeholder: placeholder,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      enableIMEPersonalizedLearning: false,
      obscureText: true,
    );
  }
}

class _TechnicalFieldFormatter extends TextInputFormatter {
  const _TechnicalFieldFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final normalizedText = _normalize(newValue.text);
    if (normalizedText == newValue.text) {
      return newValue;
    }
    return newValue.copyWith(
      text: normalizedText,
      selection: TextSelection(
        baseOffset: _normalizedOffset(
          newValue.text,
          newValue.selection.baseOffset,
        ),
        extentOffset: _normalizedOffset(
          newValue.text,
          newValue.selection.extentOffset,
        ),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }

  static int _normalizedOffset(String text, int offset) {
    if (offset < 0) {
      return offset;
    }
    final safeOffset = offset.clamp(0, text.length).toInt();
    return _normalize(text.substring(0, safeOffset)).length;
  }

  static String _normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (_isWhitespace(rune)) {
        continue;
      }
      if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static bool _isWhitespace(int rune) {
    return rune == 0x20 ||
        rune == 0x09 ||
        rune == 0x0a ||
        rune == 0x0d ||
        rune == 0x3000;
  }
}
