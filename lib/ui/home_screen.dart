import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/trainer.dart';
import 'connect_view.dart';
import 'dashboard_view.dart';
import 'compete_screen.dart';
import 'history_screen.dart';
import 'layout.dart';
import 'navigation.dart';
import 'plan_screen.dart';
import 'preferences_screen.dart';
import 'recording_panel.dart';
import 'ride_session.dart';
import 'route_controller.dart';
import 'route_screen.dart';
import 'tour_screen.dart';
import 'trainer_controller.dart';
import 'update_banner.dart';

/// The app's frame: a left dock that leads to every page, and the page.
/// Wide windows get the dock beside the page (icons only, or with labels);
/// narrow ones get it as a drawer behind a small menu bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Pages are built the first time they are opened, then kept alive, so the
  /// ride dashboard (and its screen wake lock) survives a look at History.
  final _opened = <AppPage>{AppPage.ride};

  Widget _page(AppPage p) => switch (p) {
        AppPage.ride => const _RidePage(),
        AppPage.devices => const _DevicesPage(),
        AppPage.routes => const RoutesScreen(),
        AppPage.tours => const ToursScreen(),
        AppPage.compete => const CompeteScreen(),
        AppPage.plans => const PlansScreen(),
        AppPage.history => const HistoryScreen(),
        AppPage.preferences => const PreferencesScreen(),
      };

  Future<void> _offerStage(int next) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Stage $next done'),
        content: Text('Carry on into stage ${next + 1}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Stop here')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (yes == true) {
      ref.read(rideSessionProvider.notifier).continueTour();
    } else if (yes == false && mounted) {
      await endRide(context, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(pageProvider);
    ref.listen(nextStageProvider, (_, next) {
      if (next != null) _offerStage(next);
    });
    _opened.add(page);
    final body = IndexedStack(
      index: page.index,
      children: [
        for (final p in AppPage.values)
          _opened.contains(p) ? _page(p) : const SizedBox.shrink(),
      ],
    );

    final content = Column(children: [
      const UpdateBanner(),
      Expanded(child: body),
    ]);

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= dockMinWidth) {
        return Scaffold(
          body: SafeArea(
            child: Row(children: [
              const _Dock(),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ]),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 48,
          title: Text(page.label),
        ),
        drawer: const _DockDrawer(),
        body: SafeArea(child: content),
      );
    });
  }
}

/// The ride page: connect to a trainer, then the dashboard.
class _RidePage extends ConsumerWidget {
  const _RidePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    return Center(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: connected ? wideContentMaxWidth : 720),
        child: connected ? const DashboardView() : const ConnectView(),
      ),
    );
  }
}

/// Pairing at any time: the trainer, heart rate strap and Zwift shifters,
/// whether or not a ride is on.
class _DevicesPage extends StatelessWidget {
  const _DevicesPage();

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const ConnectView(),
        ),
      );
}

/// The left dock beside the page: a slim icon rail, or icons with labels.
class _Dock extends ConsumerWidget {
  const _Dock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(dockExpandedProvider);
    final page = ref.watch(pageProvider);
    final theme = Theme.of(context);
    final toggle = IconButton(
      tooltip: expanded ? 'Collapse menu' : 'Expand menu',
      icon: Icon(expanded ? Icons.chevron_left : Icons.chevron_right),
      onPressed: ref.read(dockExpandedProvider.notifier).toggle,
    );

    return NavigationRail(
      extended: expanded,
      minWidth: dockCollapsedWidth,
      minExtendedWidth: dockExpandedWidth,
      labelType: NavigationRailLabelType.none,
      selectedIndex: page.index,
      onDestinationSelected: (i) =>
          ref.read(pageProvider.notifier).state = AppPage.values[i],
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: expanded
            ? SizedBox(
                width: dockExpandedWidth,
                child: Row(children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text('Indoor Cycling',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  toggle,
                ]),
              )
            : toggle,
      ),
      destinations: [
        for (final p in AppPage.values)
          NavigationRailDestination(
            icon: Tooltip(message: p.label, child: Icon(p.icon)),
            selectedIcon: Tooltip(message: p.label, child: Icon(p.selectedIcon)),
            label: Text(p.label),
          ),
      ],
    );
  }
}

/// The dock as a drawer, for narrow windows.
class _DockDrawer extends ConsumerWidget {
  const _DockDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(pageProvider);
    return NavigationDrawer(
      selectedIndex: page.index,
      onDestinationSelected: (i) {
        ref.read(pageProvider.notifier).state = AppPage.values[i];
        Navigator.of(context).pop(); // close the drawer
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 12),
          child: Text('Indoor Cycling',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final p in AppPage.values)
          NavigationDrawerDestination(
            icon: Icon(p.icon),
            selectedIcon: Icon(p.selectedIcon),
            label: Text(p.label),
          ),
      ],
    );
  }
}
