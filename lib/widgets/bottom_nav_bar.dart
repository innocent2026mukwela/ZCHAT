import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key});

  static const _items = [
    _NavItem(label: 'Chats',   icon: Icons.forum_rounded,          route: '/home'),
    _NavItem(label: 'zFeed',   icon: Icons.dynamic_feed_rounded,   route: '/threads'),
    _NavItem(label: 'Courses', icon: Icons.school_outlined,        route: '/courses'),
    _NavItem(label: 'AI',      icon: Icons.auto_awesome_rounded,   route: '/ai'),
    _NavItem(label: 'Planner', icon: Icons.event_note_outlined,    route: '/planner'),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF041338).withAlpha(220),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(22))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(70),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final item in _items)
                    Expanded(
                      child: _NavButton(
                        item: item,
                        selected: _isSelected(path, item.route),
                        onTap: () {
                          if (!_isSelected(path, item.route)) context.go(item.route);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSelected(String path, String route) {
    if (route == '/threads') return path == '/threads' || path.startsWith('/threads/');
    if (route == '/ai') return path == '/ai' || path.startsWith('/ai/');
    return path == route || path.startsWith('$route/');
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(135);

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF2563EB).withAlpha(42)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: color, size: 22),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
  });
}
