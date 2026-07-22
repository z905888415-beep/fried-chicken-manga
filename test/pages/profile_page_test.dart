import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpProfilePage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_token': 'current-token',
      'user_user_id': '1',
      'user_username': 'alice',
      'user_nickname': 'Alice',
      'user_avatar': '',
      'saved_username': 'alice',
      'saved_password': 'alice-pass',
      'saved_credentials': jsonEncode([
        {
          'username': 'alice',
          'password': 'alice-pass',
          'token': 'current-token',
          'user_id': '1',
          'nickname': 'Alice',
          'avatar': '',
        },
        {
          'username': 'bob',
          'password': 'bob-pass',
          'token': 'bob-token',
          'user_id': '2',
          'nickname': 'Bob',
          'avatar': '',
        },
      ]),
    });
    await UserManager().init();

    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('switch account sheet shows add account button', (tester) async {
    await pumpProfilePage(tester);

    // 新交互：先点「编辑」展开操作区，才出现「切换账号」按钮
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
  });

  testWidgets('profile page shows general settings entry', (tester) async {
    await pumpProfilePage(tester);

    // 「通用」入口已重设计为「主题设置」（trailing 显示当前主题模式）
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
  });
}
