import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/ui/screens/detail/play_item_on_screen.dart';

void main() {
  testWidgets('the page on screen asks itself to play, in place', (
    tester,
  ) async {
    late BuildContext pageContext;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/item/:itemId',
          builder: (context, state) {
            pageContext = context;
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/item/ep-4?serverId=server-1&seasonContext=season-6');
    await tester.pumpAndSettle();

    playItemOnScreen(pageContext);
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      '/item/ep-4?serverId=server-1&seasonContext=season-6&autoPlay=true',
      reason: 'the detail screen only plays when asked through autoPlay',
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(
      router.state.uri.path,
      '/home',
      reason: 'the page replaces itself, so Back does not land on it twice',
    );
  });
}
