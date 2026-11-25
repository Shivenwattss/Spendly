import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import 'import_screen.dart';
import 'assistant_screen.dart';
import 'smart_insights_screen.dart';
import 'planning_screen.dart';
import 'discover_screen.dart';

class AppHome extends StatefulWidget {
  const AppHome({super.key});
  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  int tab = 0;
  bool loading = true;
  String? error;
  List<SpendlyTransaction> items = [];
  Map<String, dynamic> analytics = {};
  String search = '';
  String filter = 'All';

  double get income => items
      .where((e) => e.type == TransactionType.income)
      .fold(0, (s, e) => s + e.amount);
  double get spent => items
      .where((e) => e.type == TransactionType.expense)
      .fold(0, (s, e) => s + e.amount);
  double get balance => income - spent;
  String money(num value) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(value);

  @override
  void initState() {
    super.initState();
    refreshAll();
  }

  Future<void> refreshAll() async {
    if (mounted)
      setState(() {
        loading = true;
        error = null;
      });
    try {
      final results = await Future.wait(
          [ApiService.getTransactions(), ApiService.getAnalytics()]);
      if (!mounted) return;
      setState(() {
        items = results[0] as List<SpendlyTransaction>;
        analytics = results[1] as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> openImport() async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const ImportScreen()));
    if (changed == true) await refreshAll();
  }

  Future<void> openEditor({SpendlyTransaction? existing}) async {
    final result = await showModalBottomSheet<SpendlyTransaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionSheet(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await ApiService.addTransaction(result);
      } else {
        await ApiService.updateTransaction(result);
      }
      await refreshAll();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(existing == null
                ? 'Transaction added'
                : 'Transaction updated')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> deleteItem(SpendlyTransaction item) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete transaction?'),
              content: Text('Delete “${item.title}”?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'))
              ],
            ));
    if (confirm != true) return;
    try {
      await ApiService.deleteTransaction(item.id);
      await refreshAll();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Spendly',
      'Activity',
      'Budgets',
      'Analytics',
      'Profile',
      'Discover'
    ];
    return Scaffold(
      appBar: AppBar(
          title: Text(titles[tab],
              style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (tab == 0 || tab == 1)
              IconButton(
                  tooltip: 'Import CSV',
                  onPressed: openImport,
                  icon: const Icon(Icons.upload_file_rounded)),
            if (tab == 0)
              IconButton(
                  tooltip: 'Smart insights',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SmartInsightsScreen())),
                  icon: const Icon(Icons.lightbulb_outline_rounded)),
            if (tab == 0)
              IconButton(
                  tooltip: 'Financial planning',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PlanningScreen())),
                  icon: const Icon(Icons.flag_outlined)),
            if (tab == 0)
              IconButton(
                  tooltip: 'Ask Spendly AI',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AssistantScreen())),
                  icon: const Icon(Icons.auto_awesome_rounded)),
            IconButton(
                tooltip: 'Refresh',
                onPressed: refreshAll,
                icon: const Icon(Icons.refresh)),
          ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorView()
              : SafeArea(
                  child: IndexedStack(
                    index: tab,
                    children: [
                      dashboard(),
                      activity(),
                      budgets(),
                      analyticsPage(),
                      profile(),
                      const DiscoverScreen(),
                    ],
                  ),
                ),
      floatingActionButton: tab == 0 || tab == 1
          ? FloatingActionButton(
              onPressed: () => openEditor(), child: const Icon(Icons.add))
          : null,
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Activity'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Budgets'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Analytics'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile'),
            NavigationDestination(
                icon: Icon(Icons.music_note_outlined),
                selectedIcon: Icon(Icons.music_note),
                label: 'Discover'),
          ]),
    );
  }

  Widget _errorView() => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Could not connect to Spendly API',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: refreshAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again')),
            const SizedBox(height: 8),
            const Text(
                'Check that the FastAPI backend is running at 127.0.0.1:8000.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ])));

  Widget dashboard() =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 100), children: [
        const Text('YOUR MONEY, SIMPLIFIED',
            style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        const Text('Available balance', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(money(balance),
            style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: _metric('Total income', money(income), Icons.south_west,
                  Colors.green)),
          const SizedBox(width: 10),
          Expanded(
              child: _metric(
                  'Total spent', money(spent), Icons.north_east, Colors.orange))
        ]),
        const SizedBox(height: 26),
        _sectionTitle('Recent activity',
            trailing: TextButton(
                onPressed: () => setState(() => tab = 1),
                child: const Text('See all'))),
        if (items.isEmpty)
          _empty('No transactions yet',
              'Add a transaction or import a CSV statement.')
        else
          ...items.take(5).map(_transactionTile),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
                leading: const Icon(Icons.lightbulb_outline_rounded),
                title: const Text('Explore smart insights',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Spending patterns, large expenses and monthly trends'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SmartInsightsScreen())))),
        const SizedBox(height: 12),
        _insightCard(),
      ]);

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(height: 12),
                    Text(label,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)))
                  ])));

  Widget _sectionTitle(String title, {Widget? trailing}) => Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700))),
        if (trailing != null) trailing
      ]);

  Widget _transactionTile(SpendlyTransaction item) {
    final isIncome = item.type == TransactionType.income;
    return Card(
        child: ListTile(
      onTap: () => openEditor(existing: item),
      leading: CircleAvatar(
          backgroundColor: (isIncome ? Colors.green : Colors.blueGrey)
              .withValues(alpha: .12),
          child: Icon(_categoryIcon(item.category),
              color: isIncome ? Colors.green : null)),
      title: Text(item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${item.category} · ${DateFormat('d MMM').format(item.date)} · ${item.source}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${isIncome ? '+' : '−'}${money(item.amount)}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isIncome ? Colors.green : null)),
        PopupMenuButton<String>(
            tooltip: 'Transaction options',
            onSelected: (v) {
              if (v == 'edit') openEditor(existing: item);
              if (v == 'delete') deleteItem(item);
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete'))
                ])
      ]),
    ));
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & drinks':
      case 'groceries':
        return Icons.restaurant_outlined;
      case 'travel':
      case 'transport':
        return Icons.directions_car_outlined;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'bills':
        return Icons.receipt_long_outlined;
      case 'health':
        return Icons.health_and_safety_outlined;
      case 'entertainment':
        return Icons.movie_outlined;
      case 'salary':
      case 'income':
        return Icons.payments_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Widget activity() {
    final filtered = items.where((item) {
      final matchesSearch = '${item.title} ${item.category} ${item.source}'
          .toLowerCase()
          .contains(search.toLowerCase());
      final matchesFilter = filter == 'All' ||
          (filter == 'Income' && item.type == TransactionType.income) ||
          (filter == 'Expenses' && item.type == TransactionType.expense);
      return matchesSearch && matchesFilter;
    }).toList();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search transactions',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) => setState(() => search = v))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<String>(segments: const [
            ButtonSegment(value: 'All', label: Text('All')),
            ButtonSegment(value: 'Expenses', label: Text('Expenses')),
            ButtonSegment(value: 'Income', label: Text('Income'))
          ], selected: {
            filter
          }, onSelectionChanged: (v) => setState(() => filter = v.first))),
      Expanded(
          child: filtered.isEmpty
              ? _empty(
                  'No matching transactions', 'Try another search or filter.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  children: filtered.map(_transactionTile).toList())),
    ]);
  }

  Widget budgets() {
    final totals = <String, double>{};
    for (final item in items.where((e) => e.type == TransactionType.expense)) {
      totals[item.category] = (totals[item.category] ?? 0) + item.amount;
    }
    const limits = {
      'Food': 6000.0,
      'Groceries': 5000.0,
      'Travel': 4000.0,
      'Shopping': 5000.0,
      'Bills': 4000.0,
      'Entertainment': 2500.0
    };
    final categories = {...limits.keys, ...totals.keys}.toList()..sort();
    return ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
        children: [
          const Text('Category budgets',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
              'Starter monthly limits. These are editable in a future budgets release.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ...categories.map((name) {
            final used = totals[name] ?? 0;
            final limit = limits[name] ?? 3000.0;
            final ratio = (used / limit).clamp(0.0, 1.0);
            return Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        Text('${money(used)} / ${money(limit)}')
                      ]),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          color: ratio >= 1 ? Colors.red : null),
                      const SizedBox(height: 5),
                      Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                              ratio >= 1
                                  ? 'Limit reached'
                                  : '${(ratio * 100).round()}% used',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)))
                    ])));
          }),
        ]);
  }

  Widget analyticsPage() {
    final categories = (analytics['categories'] as List? ?? []).cast<Map>();
    final months = (analytics['months'] as List? ?? []).cast<Map>();
    final rate = (analytics['savings_rate'] as num?)?.toDouble() ?? 0;
    final maxCategory = categories.fold<double>(
        0,
        (m, c) => ((c['amount'] as num).toDouble() > m
            ? (c['amount'] as num).toDouble()
            : m));
    return RefreshIndicator(
        onRefresh: refreshAll,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
            children: [
              const Text('Your spending overview',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('Insights calculated from your saved transactions.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 18),
              GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.8,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 2,
                  children: [
                    _smallStat(
                        'Income',
                        money((analytics['income'] as num?) ?? 0),
                        Colors.green),
                    _smallStat(
                        'Expenses',
                        money((analytics['expenses'] as num?) ?? 0),
                        Colors.orange),
                    _smallStat('Net balance',
                        money((analytics['balance'] as num?) ?? 0), null),
                    _smallStat('Savings rate', '${rate.toStringAsFixed(1)}%',
                        Colors.blue),
                  ]),
              const SizedBox(height: 20),
              _sectionTitle('Spending by category'),
              const SizedBox(height: 8),
              if (categories.isEmpty)
                _empty('No expense data yet',
                    'Add or import expenses to see your category breakdown.')
              else
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            children: categories.map((c) {
                          final amount = (c['amount'] as num).toDouble();
                          final share = (c['share'] as num).toDouble();
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(c['category'].toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600))),
                                  Text(money(amount)),
                                  const SizedBox(width: 8),
                                  Text('${share.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12))
                                ]),
                                const SizedBox(height: 7),
                                LinearProgressIndicator(
                                    value: maxCategory == 0
                                        ? 0
                                        : amount / maxCategory,
                                    minHeight: 7)
                              ]));
                        }).toList()))),
              const SizedBox(height: 18),
              _sectionTitle('Monthly cash flow'),
              const SizedBox(height: 8),
              if (months.isEmpty)
                _empty('No monthly data yet',
                    'Your monthly income and expenses will appear here.')
              else
                ...months.reversed.take(6).map((m) {
                  final inc = (m['income'] as num).toDouble();
                  final exp = (m['expense'] as num).toDouble();
                  final maxVal =
                      [inc, exp, 1.0].reduce((a, b) => a > b ? a : b);
                  final monthDate = DateTime.tryParse('${m['month']}-01');
                  final label = monthDate == null
                      ? m['month'].toString()
                      : DateFormat('MMMM yyyy').format(monthDate);
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                _barRow('Income', inc, maxVal, Colors.green),
                                const SizedBox(height: 8),
                                _barRow('Expenses', exp, maxVal, Colors.orange),
                                const SizedBox(height: 8),
                                Text(
                                    'Net: ${money((m['savings'] as num).toDouble())}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey))
                              ])));
                }),
              const SizedBox(height: 12),
              _insightCard(rate: rate),
            ]));
  }

  Widget _smallStat(String label, String value, Color? color) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: color)))
              ])));

  Widget _barRow(String label, double value, double max, Color color) =>
      Row(children: [
        SizedBox(
            width: 68,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                    value: value / max,
                    minHeight: 10,
                    color: color,
                    backgroundColor: color.withValues(alpha: .12)))),
        const SizedBox(width: 10),
        SizedBox(
            width: 76,
            child: Text(money(value),
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))
      ]);

  Widget _insightCard({double? rate}) {
    final actualRate = rate ?? (income > 0 ? (balance / income * 100) : 0);
    final text = items.isEmpty
        ? 'Add transactions to start seeing your spending patterns.'
        : actualRate < 0
            ? 'Your recorded expenses are higher than your income. Review the largest categories in Analytics.'
            : 'You are retaining ${actualRate.toStringAsFixed(1)}% of recorded income after expenses. Keep tracking to build a clearer picture.';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF4778D8)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Spendly insight',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(text, style: const TextStyle(color: Colors.grey))
                  ]))
            ])));
  }

  Widget _empty(String title, String subtitle) => Padding(
      padding: const EdgeInsets.all(26),
      child: Column(children: [
        const Icon(Icons.inbox_outlined, size: 38, color: Colors.grey),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 12))
      ]));

  Widget profile() =>
      ListView(padding: const EdgeInsets.all(20), children: const [
        Text('Profile',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        SizedBox(height: 12),
        Card(
            child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('Connected accounts'),
                subtitle: Text(
                    'Bank integrations are not enabled in this development build.'))),
        Card(
            child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Privacy & security'),
                subtitle: Text(
                    'Use sample data only until authentication and production security are implemented.'))),
        Card(
            child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Spendly version'),
                subtitle:
                    Text('Development build · Flutter + FastAPI + SQLite'))),
      ]);
}

class TransactionSheet extends StatefulWidget {
  final SpendlyTransaction? existing;
  const TransactionSheet({super.key, this.existing});
  @override
  State<TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<TransactionSheet> {
  late final TextEditingController title;
  late final TextEditingController amount;
  late TransactionType type;
  late String category;
  late DateTime date;
  final categories = const [
    'Food',
    'Groceries',
    'Travel',
    'Shopping',
    'Bills',
    'Education',
    'Health',
    'Entertainment',
    'Salary',
    'Freelance',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    title = TextEditingController(text: item?.title ?? '');
    amount = TextEditingController(
        text: item == null ? '' : item.amount.toStringAsFixed(0));
    type = item?.type ?? TransactionType.expense;
    category = item?.category ?? 'Food';
    if (!categories.contains(category)) category = 'Other';
    date = item?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    super.dispose();
  }

  void save() {
    final value = double.tryParse(amount.text.trim());
    if (title.text.trim().isEmpty ||
        value == null ||
        value <= 0 ||
        value > 100000000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a description and a valid amount.')));
      return;
    }
    Navigator.pop(
        context,
        SpendlyTransaction(
            id: widget.existing?.id ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            title: title.text.trim(),
            category: category,
            amount: value,
            date: date,
            type: type,
            source: widget.existing?.source ?? 'Manual'));
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
                widget.existing == null
                    ? 'Add transaction'
                    : 'Edit transaction',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                      value: TransactionType.expense, label: Text('Expense')),
                  ButtonSegment(
                      value: TransactionType.income, label: Text('Income'))
                ],
                selected: {
                  type
                },
                onSelectionChanged: (v) => setState(() {
                      type = v.first;
                      if (type == TransactionType.income &&
                          !['Salary', 'Freelance', 'Other'].contains(category))
                        category = 'Salary';
                      if (type == TransactionType.expense &&
                          ['Salary', 'Freelance'].contains(category))
                        category = 'Food';
                    })),
            const SizedBox(height: 12),
            TextField(
                controller: title,
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                    labelText: 'Category', border: OutlineInputBorder()),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v ?? category)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null) setState(() => date = picked);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(DateFormat('d MMM yyyy').format(date))),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: save,
                    child: Text(widget.existing == null
                        ? 'Save transaction'
                        : 'Save changes'))),
          ])));
}
