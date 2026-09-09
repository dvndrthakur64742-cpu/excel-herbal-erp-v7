from pathlib import Path
import re


def read(path: str):
    p = Path(path)
    return p, p.read_text()


def replace_once(s: str, old: str, new: str, label: str) -> str:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return s.replace(old, new, 1)


def regex_once(s: str, pattern: str, new: str, label: str) -> str:
    out, count = re.subn(pattern, new, s, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return out

# Profile: shell AppBar already owns the page title. Remove duplicate in-page title and tighten identity card.
p, s = read('flutter-app/lib/screens/home/profile_screen.dart')
s = replace_once(
    s,
    "    return ListView(\n      padding: const EdgeInsets.all(16),\n      children: [\n        Text('Profile', style: Theme.of(context).textTheme.headlineSmall),\n        const SizedBox(height: 12),",
    "    return ListView(\n      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),\n      children: [",
    'profile duplicate title',
)
s = replace_once(s, 'padding: const EdgeInsets.all(18),', 'padding: const EdgeInsets.all(14),', 'profile identity padding')
s = replace_once(s, 'width: 58,\n                  height: 58,', 'width: 48,\n                  height: 48,', 'profile avatar size')
s = replace_once(s, 'size: 30,', 'size: 24,', 'profile icon size')
s = replace_once(s, 'const SizedBox(width: 14),', 'const SizedBox(width: 12),', 'profile identity gap')
p.write_text(s)

# Home: replace consumer-style gradient hero + duplicate branch/access metrics with a restrained ERP identity panel.
p, s = read('flutter-app/lib/screens/home/home_screen.dart')
start = s.index('  Widget _welcomeHero(')
end = s.index('  Widget _workspaceCards(', start)
new_hero = r'''  Widget _welcomeHero(
    BuildContext context,
    AppState app,
    Map<String, dynamic> employee,
  ) {
    final designation = _designation(app);
    final name = '${employee['full_name'] ?? 'Employee'}'.trim();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.badge_outlined,
              color: scheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_dayPart()}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  designation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

'''
s = s[:start] + new_hero + s[end:]
s = regex_once(
    s,
    r"\nclass _HeroMetric extends StatelessWidget \{.*?\n\}\n\nclass _StatusPill extends StatelessWidget",
    "\nclass _StatusPill extends StatelessWidget",
    'remove obsolete hero metric',
)
p.write_text(s)

# My Work: accept exact initial section so Quick Actions land on the intended tab.
p, s = read('flutter-app/lib/screens/my_work/my_work_screen.dart')
s = replace_once(
    s,
    'class MyWorkScreen extends ConsumerStatefulWidget {\n  const MyWorkScreen({super.key});\n\n  @override',
    "class MyWorkScreen extends ConsumerStatefulWidget {\n  const MyWorkScreen({super.key, this.initialSection});\n\n  final String? initialSection;\n\n  @override",
    'mywork constructor',
)
s = replace_once(
    s,
    "    if (tabs.isEmpty) {\n      return const Center(child: Text('No authorised My Work functions.'));\n    }\n    return DefaultTabController(\n      length: tabs.length,",
    "    if (tabs.isEmpty) {\n      return const Center(child: Text('No authorised My Work functions.'));\n    }\n    final requestedLabel = switch (widget.initialSection) {\n      'attendance' => 'Attendance & Duty',\n      'daily' => 'Daily Order',\n      'leave_visit' => 'Leave & Visit',\n      _ => null,\n    };\n    final requestedIndex = requestedLabel == null\n        ? -1\n        : tabs.indexWhere((tab) => tab.$1 == requestedLabel);\n    return DefaultTabController(\n      length: tabs.length,\n      initialIndex: requestedIndex < 0 ? 0 : requestedIndex,",
    'mywork initial tab',
)
p.write_text(s)

# Quick Actions: use section-specific callbacks instead of generic My Work navigation.
p, s = read('flutter-app/lib/screens/home/actions_screen.dart')
s = replace_once(s, '  final VoidCallback openMyWork;', '  final void Function(String section) openMyWork;', 'actions callback type')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('attendance'),", 'attendance deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'create order deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'evening deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'field visit deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'leave deep link')
p.write_text(s)

# Shell: remember the requested My Work section per surface and reset it on normal nav taps.
p, s = read('flutter-app/lib/shell/app_shell.dart')
s = replace_once(
    s,
    "  int mobileIndex = 0;\n  String desktopRoute = 'home';",
    "  int mobileIndex = 0;\n  String? mobileMyWorkSection;\n  String desktopRoute = 'home';\n  String? desktopMyWorkSection;",
    'shell section state',
)
s = replace_once(s, "      'my_work' => const MyWorkScreen(),", "      'my_work' => MyWorkScreen(initialSection: desktopMyWorkSection),", 'desktop mywork screen')
s = replace_once(
    s,
    "          openMyWork: () {\n            if (app.sectionVisible('my_work'))\n              setState(() => desktopRoute = 'my_work');\n          },",
    "          openMyWork: (section) {\n            if (app.sectionVisible('my_work')) {\n              setState(() {\n                desktopMyWorkSection = section;\n                desktopRoute = 'my_work';\n              });\n            }\n          },",
    'desktop quick action deep link',
)
s = replace_once(s, "        'my_work' => const MyWorkScreen(),", "        'my_work' => MyWorkScreen(initialSection: mobileMyWorkSection),", 'mobile mywork screen')
s = replace_once(
    s,
    "            openMyWork: () => _selectMobileRoute(app, 'my_work'),",
    "            openMyWork: (section) => _openMyWorkSection(app, section),",
    'mobile quick action callback',
)
s = replace_once(
    s,
    '            onDestinationSelected: (v) => setState(() => mobileIndex = v),',
    "            onDestinationSelected: (v) {\n              final id = '${items[v]['id']}';\n              setState(() {\n                mobileIndex = v;\n                if (id == 'my_work') mobileMyWorkSection = null;\n              });\n            },",
    'bottom nav reset',
)
s = replace_once(
    s,
    "  void _selectMobileRoute(AppState app, String id) {\n    final items = app.bottomNav;\n    final index = items.indexWhere((item) => '${item['id']}' == id);\n    if (index >= 0) setState(() => mobileIndex = index);\n  }",
    "  void _openMyWorkSection(AppState app, String section) {\n    final items = app.bottomNav;\n    final index = items.indexWhere((item) => '${item['id']}' == 'my_work');\n    if (index < 0) return;\n    setState(() {\n      mobileMyWorkSection = section;\n      mobileIndex = index;\n    });\n  }\n\n  void _selectMobileRoute(AppState app, String id) {\n    final items = app.bottomNav;\n    final index = items.indexWhere((item) => '${item['id']}' == id);\n    if (index >= 0) {\n      setState(() {\n        mobileIndex = index;\n        if (id == 'my_work') mobileMyWorkSection = null;\n      });\n    }\n  }",
    'mobile deep link helper',
)
p.write_text(s)

print('Final premium UI polish applied successfully.')
