import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../common/motion.dart';
import '../common/settings.dart';
import '../components/backdrop.dart';
import '../services/downloads.dart';
import '../services/power.dart';

/// The first-run walkthrough.
///
/// It explains what the app does and asks for the three permissions playback
/// actually depends on: reading the music library, posting the playback
/// notification, and surviving the device's battery optimizer. Every request is
/// skippable, and finishing writes [SettingKey.onboarded], which is what
/// `FathomApp` reads to mount the shell instead.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _pages = 5;

  final PageController _controller = PageController();
  int _index = 0;
  bool _libraryBusy = false;
  bool? _notifications;
  bool _notificationBusy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    context.read<FathomSettings>().set(SettingKey.onboarded, true);
  }

  Future<void> _next() async {
    if (_index == _pages - 1) {
      _finish();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: const FathomSpringCurve(),
    );
  }

  Future<void> _askLibrary() async {
    if (_libraryBusy) return;
    setState(() => _libraryBusy = true);
    await context.read<FathomLibrary>().load(grantIfMissing: true);
    if (!mounted) return;
    setState(() => _libraryBusy = false);
  }

  Future<void> _askNotifications() async {
    if (_notificationBusy) return;
    setState(() => _notificationBusy = true);
    final granted =
        await context.read<FathomDownloads>().requestNotificationPermission();
    if (!mounted) return;
    setState(() {
      _notificationBusy = false;
      _notifications = granted;
    });
  }

  Future<void> _askBackground() async {
    final power = context.read<FathomPowerState>();
    await power.requestBatteryExemption();
    await power.refreshBatteryExemption();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    final libraryStatus =
        context.select<FathomLibrary, FathomLibraryStatus>((l) => l.status);
    final batteryExempt =
        context.select<FathomPowerState, bool>((p) => p.isBatteryExempt);

    final pages = <Widget>[
      const _WelcomePage(),
      _LibraryPage(
        accent: accent,
        status: libraryStatus,
        busy: _libraryBusy,
        onAllow: _askLibrary,
      ),
      _NotificationPage(
        accent: accent,
        granted: _notifications,
        busy: _notificationBusy,
        onAllow: _askNotifications,
      ),
      _BackgroundPage(
        accent: accent,
        exempt: batteryExempt,
        onAllow: _askBackground,
      ),
      const _FeaturesPage(),
    ];

    return Scaffold(
      backgroundColor: FathomColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _index == _pages - 1
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: TextButton(
                              onPressed: _finish,
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: FathomColors.onSurfaceMuted,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: pages,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pages; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _index ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _index
                                    ? accent
                                    : FathomColors.onSurface
                                        .withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _PrimaryButton(
                        label: _index == 0
                            ? 'Get started'
                            : _index == _pages - 1
                                ? 'Start listening'
                                : 'Continue',
                        accent: accent,
                        onTap: _next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _PageBody(
      icon: TablerIcons.waveSine,
      title: 'Fathom',
      body:
          'A quiet player for the music already on this device.\n\nNo account, '
          'no feed, nothing uploaded. Search can fetch a track you ask for, and '
          'everything else stays local.',
    );
  }
}

class _LibraryPage extends StatelessWidget {
  const _LibraryPage({
    required this.accent,
    required this.status,
    required this.busy,
    required this.onAllow,
  });

  final Color accent;
  final FathomLibraryStatus status;
  final bool busy;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final ready = status == FathomLibraryStatus.ready;
    return _PageBody(
      icon: TablerIcons.music,
      title: 'Your library',
      body:
          'Fathom reads the audio files on this device to build your library. '
          'It needs access to titles, artists, durations and embedded artwork.',
      footer: Column(
        children: [
          _PrimaryButton(
            label: ready
                ? 'Library access is on'
                : busy
                    ? 'Asking…'
                    : 'Allow library access',
            accent: accent,
            enabled: !ready && !busy,
            onTap: onAllow,
          ),
          const SizedBox(height: 10),
          Text(
            'Fathom never uploads your files.',
            style: TextStyle(
              fontSize: 12,
              color: FathomColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage({
    required this.accent,
    required this.granted,
    required this.busy,
    required this.onAllow,
  });

  final Color accent;
  final bool? granted;
  final bool busy;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      icon: TablerIcons.bell,
      title: 'Lock screen controls',
      body: 'Android shows playback on the lock screen and in the notification '
          'shade. That notification is also what keeps audio alive when the '
          'screen turns off.',
      footer: Column(
        children: [
          _PrimaryButton(
            label: granted == true
                ? 'Notifications are on'
                : busy
                    ? 'Asking…'
                    : 'Allow notifications',
            accent: accent,
            enabled: granted != true && !busy,
            onTap: onAllow,
          ),
          if (granted == false) ...[
            const SizedBox(height: 10),
            Text(
              'You can allow this later in Android settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: FathomColors.onSurfaceMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackgroundPage extends StatelessWidget {
  const _BackgroundPage({
    required this.accent,
    required this.exempt,
    required this.onAllow,
  });

  final Color accent;
  final bool exempt;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      icon: TablerIcons.batteryCharging,
      title: 'Keep playing',
      body:
          'Some Android builds stop background audio to save power. Exempting '
          'Fathom from battery optimization keeps playback running with the '
          'screen off.',
      footer: Column(
        children: [
          _PrimaryButton(
            label: exempt
                ? 'Background playback is on'
                : 'Allow background playback',
            accent: accent,
            enabled: !exempt,
            onTap: onAllow,
          ),
          const SizedBox(height: 10),
          Text(
            'Opens an Android settings screen.',
            style: TextStyle(
              fontSize: 12,
              color: FathomColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  static const _features = <(IconData, String, String)>[
    (
      TablerIcons.search,
      'Search and keep',
      'Find a track online, download it once, then play it locally forever.',
    ),
    (
      TablerIcons.adjustmentsHorizontal,
      'Ten-band equalizer',
      'Shape the sound by hand or import a measured AutoEQ curve.',
    ),
    (
      TablerIcons.palette,
      'Make it yours',
      'Four accents, custom colors, AMOLED black, and Google Fonts.',
    ),
    (
      TablerIcons.list,
      'A real queue',
      'Reorder, shuffle, repeat, and resume exactly where you left off.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            'What is inside',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.1,
              color: FathomColors.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          for (final feature in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(feature.$1, size: 21, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.$2,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: FathomColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          feature.$3,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: FathomColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final accent = context.select<FathomSettings, Color>((s) => s.accent);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 36, color: accent),
          ),
          const SizedBox(height: 26),
          Text(
            title,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
              height: 1.1,
              color: FathomColors.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              color: FathomColors.onSurfaceMuted,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 30),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: enabled ? 1 : 0.35),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: FathomColors.onAccent(accent),
          ),
        ),
      ),
    );
  }
}
