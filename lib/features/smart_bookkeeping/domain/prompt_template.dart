import 'dart:convert';

import 'package:flutter/foundation.dart';

const defaultPromptId = 'builtin-default';

const defaultPromptContent = '''请从账单图片或OCR文字中提取一笔主要交易。

当前时间：{{CURRENT_TIME}}
输入来源：{{INPUT_SOURCE}}

OCR文字：
{{OCR_TEXT}}

可选支出分类：
{{EXPENSE_CATEGORIES}}

可选收入分类：
{{INCOME_CATEGORIES}}

识别要求：
1. 优先识别实际支付或到账金额，不使用订单号、优惠金额或账户余额。
2. 备注优先使用商户、店铺或商品的简洁名称。
3. 分类必须从提供的分类中选择；无法可靠判断时将分类留空。
4. 无法识别交易时间时使用当前时间。''';

const promptVariables = <String>{
  'CURRENT_TIME',
  'OCR_TEXT',
  'EXPENSE_CATEGORIES',
  'INCOME_CATEGORIES',
  'INPUT_SOURCE',
};

@immutable
final class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.content,
    required this.isBuiltIn,
  });

  final String id;
  final String name;
  final String content;
  final bool isBuiltIn;

  static const defaultTemplate = PromptTemplate(
    id: defaultPromptId,
    name: '默认提示词',
    content: defaultPromptContent,
    isBuiltIn: true,
  );

  PromptTemplate copyWith({String? id, String? name, String? content}) {
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      isBuiltIn: isBuiltIn,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'isBuiltIn': isBuiltIn,
  };

  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    );
  }
}

@immutable
final class PromptLibrary {
  const PromptLibrary({required this.templates, required this.activeId});

  final List<PromptTemplate> templates;
  final String activeId;

  PromptTemplate get active => templates.firstWhere(
    (template) => template.id == activeId,
    orElse: () => PromptTemplate.defaultTemplate,
  );

  PromptTemplate? byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }
}

Set<String> unknownPromptVariables(String content) {
  final matches = RegExp(r'\{\{([A-Za-z0-9_]+)\}\}').allMatches(content);
  return {
    for (final match in matches)
      if (!promptVariables.contains(match.group(1))) match.group(1)!,
  };
}

String renderPromptTemplate(
  String content, {
  required Map<String, String> values,
}) {
  var rendered = content;
  for (final variable in promptVariables) {
    rendered = rendered.replaceAll('{{$variable}}', values[variable] ?? '');
  }
  return rendered;
}

String encodeCustomPrompts(List<PromptTemplate> templates) => jsonEncode([
  for (final template in templates)
    if (!template.isBuiltIn) template.toJson(),
]);

List<PromptTemplate> decodeCustomPrompts(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final value = jsonDecode(source) as List<dynamic>;
    return [
      for (final item in value)
        PromptTemplate.fromJson(item as Map<String, dynamic>),
    ];
  } on Object {
    return const [];
  }
}
