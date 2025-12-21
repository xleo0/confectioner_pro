import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart'; // Необходимо добавить этот импорт
import 'package:confectioner_pro/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Обязательно оборачиваем в Provider, как в main.dart 
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => PastryProvider(),
        child: PastryProApp(), // Используем правильное имя класса 
      ),
    );

    // Ждем окончания анимаций, если они есть
    await tester.pumpAndSettle();

    // Проверяем, что приложение запустилось и отображает заголовок
    // Вместо поиска '0' и '1' (счетчик), ищем заголовок вашего приложения [cite: 108]
    expect(find.text('Кондитер Про'), findsOneWidget);
    
    // Проверяем наличие иконок навигации
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
  });
}