import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/application/app_font_controller.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'termethis_theme.dart';

class TermethisApp extends ConsumerWidget {
  const TermethisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final appFont = ref.watch(appFontProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ja'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: TermethisTheme.light(appFont.family),
      darkTheme: TermethisTheme.dark(appFont.family),
      routerConfig: router,
    );
  }
}
