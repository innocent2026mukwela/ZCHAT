import 'package:flutter/material.dart';

// ── Emoji data ────────────────────────────────────────────────────────────────

const _kCategories = [
  _EmojiCategory(icon: '😀', label: 'Smileys', emojis: [
    '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍',
    '🤩','😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🫢',
    '🫣','🤫','🤔','🫠','🤐','🥴','😑','😬','🙄','😯','😦','😧','😮','😲','🥱',
    '😴','🤤','😪','😵','🤯','🥳','🥸','😎','🤓','🧐','😕','🫤','😟','🙁','☹️',
    '😣','😖','😫','😩','🥺','😢','😭','😤','😠','😡','🤬','😈','👿','💀','☠️',
    '💩','🤡','👹','👺','👻','👽','👾','🤖',
  ]),
  _EmojiCategory(icon: '👋', label: 'Gestures', emojis: [
    '👋','🤚','🖐️','✋','🖖','🫱','🫲','🫳','🫴','🫷','🫸','👌','🤌','🤏','✌️',
    '🤞','🫰','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','🫵','👍','👎','✊',
    '👊','🤛','🤜','👏','🙌','🫶','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾',
    '🦿','🦵','🦶','👂','🦻','👃','🫀','🫁','🧠','🦷','🦴','👀','👁️','👅','👄',
  ]),
  _EmojiCategory(icon: '❤️', label: 'Hearts', emojis: [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','❤️‍🔥','❤️‍🩹','💔','💖','💗',
    '💓','💞','💕','💟','☮️','✝️','☯️','💝','💘','💌','💋','💍','💎','🏆','🥇',
    '🌟','⭐','✨','💫','⚡','🔥','🌈','☀️','🌤️','🌙','❄️','🌊','💧','🍀','🌸',
  ]),
  _EmojiCategory(icon: '🐶', label: 'Animals', emojis: [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐻‍❄️','🐨','🐯','🦁','🐮','🐷','🐸',
    '🐵','🙈','🙉','🙊','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐗','🐴',
    '🦄','🐝','🪱','🐛','🦋','🐌','🐞','🐜','🪲','🦟','🦗','🕷️','🐢','🐍','🦎',
    '🦖','🦕','🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🐊',
  ]),
  _EmojiCategory(icon: '🍕', label: 'Food', emojis: [
    '🍕','🍔','🌭','🍟','🌮','🌯','🫔','🥙','🧆','🥚','🍳','🥘','🍲','🫕','🥣',
    '🥗','🍿','🧂','🥫','🍱','🍘','🍙','🍚','🍛','🍜','🍝','🍠','🍢','🍣','🍤',
    '🍥','🥮','🍡','🥟','🥠','🥡','🦪','🍦','🍧','🍨','🍩','🍪','🎂','🍰','🧁',
    '🥧','🍫','🍬','🍭','🍮','🍯','🍼','🥛','☕','🫖','🍵','🧃','🥤','🧋','🍶',
    '🍾','🍷','🍸','🍹','🍺','🍻','🥂','🥃','🫗','🥤',
  ]),
  _EmojiCategory(icon: '⚽', label: 'Activity', emojis: [
    '⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🥍',
    '🏑','🎿','⛷️','🏂','🪂','🏋️','🤼','🤸','⛹️','🤺','🏇','🧘','🏄','🏊','🤽',
    '🚣','🧗','🚵','🚴','🏆','🥇','🥈','🥉','🏅','🎖️','🎗️','🎫','🎟️','🎪','🤹',
    '🎭','🎨','🎬','🎤','🎧','🎼','🎵','🎶','🎷','🪗','🎸','🎹','🎺','🎻','🪘',
  ]),
  _EmojiCategory(icon: '🚗', label: 'Travel', emojis: [
    '🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🏍️',
    '🛵','🚲','🛴','🛹','🛼','🚏','🛣️','🛤️','⛽','🚧','⚓','🛟','⛵','🚤','🛥️',
    '🛳️','⛴️','🚢','✈️','🛩️','🛫','🛬','🪂','💺','🚁','🚟','🚠','🚡','🛰️','🚀',
    '🛸','🌍','🌎','🌏','🌐','🗺️','🧭','🏔️','⛰️','🌋','🗻','🏕️','🏖️','🏜️','🏝️',
  ]),
  _EmojiCategory(icon: '💡', label: 'Objects', emojis: [
    '⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','🖲️','💾','💿','📀','📷','📸','📹','🎥',
    '📽️','🎞️','📞','☎️','📟','📠','📺','📻','🧭','⏱️','⏰','🕰️','⌛','⏳','📡',
    '🔋','🔌','💡','🔦','🕯️','🪔','🧯','🛢️','💰','💴','💵','💶','💷','💸','💳',
    '🪙','💹','📈','📉','📊','📋','📌','📍','✂️','🗃️','🗄️','🗑️','🔒','🔓','🔏',
    '🔐','🔑','🗝️','🔨','🪓','⛏️','⚒️','🛠️','🗡️','⚔️','🔫','🪃','🛡️','🪚','🔧',
    '🪛','🔩','⚙️','🗜️','⚖️','🦯','🔗','⛓️','🪝','🧲','🪜','🧰','🪤','🧱','🪞',
  ]),
  _EmojiCategory(icon: '🔣', label: 'Symbols', emojis: [
    '✅','❎','🆗','🆙','🆒','🆕','🆓','🔝','🔛','🔜','🔚','🆘','🆖','📵','🚫',
    '❌','⭕','🛑','⛔','📛','🚷','🚯','🚳','🚱','📳','📴','📶','📳','🔔','🔕',
    '🔇','🔈','🔉','🔊','📢','📣','🃏','🀄','🎴','🔮','🧿','🪬','💈','🔱','📛',
    '🔰','♻️','✔️','🔖','💠','🔷','🔶','🔹','🔸','▪️','▫️','🔺','🔻','💯','🔅',
    '🔆','🔱','⚜️','🏁','🚩','🎌','🏴','🏳️','🌈','🏴‍☠️',
  ]),
];

class _EmojiCategory {
  final String icon, label;
  final List<String> emojis;
  const _EmojiCategory({required this.icon, required this.label, required this.emojis});
}

// ── Full Emoji Picker Panel ───────────────────────────────────────────────────
// Use for the inline keyboard (slides up from input field).

class EmojiPickerPanel extends StatefulWidget {
  final void Function(String emoji) onEmojiSelected;
  final double height;
  const EmojiPickerPanel({super.key, required this.onEmojiSelected, this.height = 280});

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _kCategories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _searchResults {
    // Return all emojis across all categories that match
    return _kCategories.expand((c) => c.emojis).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1020),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
      ),
      child: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(25)),
            ),
            child: Row(children: [
              const SizedBox(width: 10),
              Icon(Icons.search_rounded, size: 16, color: Colors.white.withAlpha(120)),
              const SizedBox(width: 6),
              Expanded(child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search emoji…',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _search = v),
              )),
              if (_search.isNotEmpty)
                GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withAlpha(120)),
                ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
        // Category tabs (hidden during search)
        if (_search.isEmpty)
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: const Color(0xFF4F8AFF),
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: _kCategories.map((c) => Tab(
              height: 34,
              child: Text(c.icon, style: const TextStyle(fontSize: 18)),
            )).toList(),
          ),
        // Emoji grid
        Expanded(
          child: _search.isNotEmpty
              ? _EmojiGrid(
                  emojis: _searchResults
                      .where((e) => e.contains(_search))
                      .toList(),
                  onPick: widget.onEmojiSelected,
                )
              : TabBarView(
                  controller: _tabs,
                  children: _kCategories.map((c) => _EmojiGrid(
                    emojis: c.emojis,
                    onPick: widget.onEmojiSelected,
                  )).toList(),
                ),
        ),
      ]),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final void Function(String) onPick;
  const _EmojiGrid({required this.emojis, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (emojis.isEmpty) {
      return Center(child: Text('No emoji found', style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        childAspectRatio: 1,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: emojis.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => onPick(emojis[i]),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: Center(child: Text(emojis[i], style: const TextStyle(fontSize: 24))),
        ),
      ),
    );
  }
}

// ── Full-screen Reaction Sheet ────────────────────────────────────────────────
// Shows as a bottom sheet for reactions, with category tabs + recent strip.

class EmojiReactionSheet extends StatefulWidget {
  final void Function(String emoji) onPick;
  const EmojiReactionSheet({super.key, required this.onPick});

  @override
  State<EmojiReactionSheet> createState() => _EmojiReactionSheetState();
}

class _EmojiReactionSheetState extends State<EmojiReactionSheet> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _quickReactions = ['👍','❤️','😂','😮','😢','🙏','🔥','👏','🥳','💯'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _kCategories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF0A1020),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        // Handle
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Quick reactions strip
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _quickReactions.map((e) => GestureDetector(
              onTap: () { Navigator.pop(context); widget.onPick(e); },
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
              ),
            )).toList(),
          ),
        ),
        Divider(color: Colors.white.withAlpha(12), height: 1),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(25)),
            ),
            child: Row(children: [
              const SizedBox(width: 10),
              Icon(Icons.search_rounded, size: 16, color: Colors.white.withAlpha(120)),
              const SizedBox(width: 6),
              Expanded(child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search emoji…',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _search = v),
              )),
              if (_search.isNotEmpty)
                GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withAlpha(120)),
                  ),
                ),
            ]),
          ),
        ),
        // Category tabs
        if (_search.isEmpty)
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: const Color(0xFF4F8AFF),
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: _kCategories.map((c) => Tab(
              height: 34,
              child: Text(c.icon, style: const TextStyle(fontSize: 18)),
            )).toList(),
          ),
        // Grid
        Expanded(
          child: _search.isNotEmpty
              ? _EmojiGrid(
                  emojis: _kCategories
                      .expand((c) => c.emojis)
                      .where((e) => e.contains(_search))
                      .toList(),
                  onPick: (e) { Navigator.pop(context); widget.onPick(e); },
                )
              : TabBarView(
                  controller: _tabs,
                  children: _kCategories.map((c) => _EmojiGrid(
                    emojis: c.emojis,
                    onPick: (e) { Navigator.pop(context); widget.onPick(e); },
                  )).toList(),
                ),
        ),
      ]),
    );
  }
}
