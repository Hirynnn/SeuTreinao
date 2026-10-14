import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_treinao/core/app_theme.dart';

void main() {
  test('tema escuro usa fundo preto e vermelho como cor principal', () {
    final theme = buildSeuTreinaoTheme(Brightness.dark);

    expect(theme.scaffoldBackgroundColor, const Color(0xFF080808));
    expect(theme.colorScheme.primary, const Color(0xFFE50914));
    expect(theme.colorScheme.surface, const Color(0xFF171717));
  });

  test('tema claro usa fundo branco e mantém a identidade vermelha', () {
    final theme = buildSeuTreinaoTheme(Brightness.light);

    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(theme.colorScheme.primary, const Color(0xFFE50914));
    expect(theme.colorScheme.onSurface, const Color(0xFF171717));
  });
}
