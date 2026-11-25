import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'import_screen.dart';

enum TransactionType { income, expense }

class SpendlyTransaction {
  const SpendlyTransaction({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    required this.type,
    required this.source,
  });

  final String id;
  final String title;
  final String category;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String source;
}

class ApiService {
  static final List<SpendlyTransaction> _transactions = [];

  static Future<List<SpendlyTransaction>> getTransactions() async =>
      List.unmodifiable(_transactions);

  static Future<void> addTransaction(SpendlyTransaction transaction) async {
    _transactions.insert(0, transaction);
  }
}

class AppHome extends StatefulWidget {
  const AppHome({super.key});

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  int tab = 0;
  List<SpendlyTransaction> items = [];

  bool loading = true;
  String? error;

  double get income => items
      .where((e) => e.type == TransactionType.income)
      .fold(0, (sum, e) => sum + e.amount);

  double get spent => items
      .where((e) => e.type == TransactionType.expense)
      .fold(0, (sum, e) => sum + e.amount);

  double get balance => income - spent;

  String money(double value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  @override
  void initState() {
    super.initState();
    loadTransactions();
  }

  // Load transactions from FastAPI
  Future<void> loadTransactions() async {
    try {
      final data = await ApiService.getTransactions();

      if (!mounted) return;

      setState(() {
        items = data;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  // Import CSV statement
  Future<void> openImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ImportScreen(),
      ),
    );

    if (!mounted) return;

    await loadTransactions();
  }

  // Add transaction
  Future<void> add() async {
    final result = await showModalBottomSheet<SpendlyTransaction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddSheet(),
    );

    if (result == null) return;

    try {
      await ApiService.addTransaction(result);
      await loadTransactions();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction saved successfully!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Spendly',
      'Activity',
      'Budgets',
      'Profile',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[tab],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (tab == 0) ...[
            IconButton(
              onPressed: openImport,
              tooltip: 'Import transactions',
              icon: const Icon(Icons.upload_file),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 40),
                      const SizedBox(height: 12),
                      const Text('Could not connect to Spendly server'),
                      TextButton(
                        onPressed: loadTransactions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  child: IndexedStack(
                    index: tab,
                    children: [
                      dashboard(),
                      activity(),
                      budgets(),
                      profile(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: add,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) {
          setState(() => tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // Dashboard
  Widget dashboard() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        const Text(
          'YOUR MONEY, SIMPLIFIED',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Available balance',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 5),
        Text(
          money(balance),
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: metric(
                'Total spent',
                money(spent),
                Icons.north_east,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: metric(
                'Total income',
                money(income),
                Icons.south_west,
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Text(
          'Recent activity',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Center(
              child: Text('No transactions yet. Tap + to add one.'),
            ),
          )
        else
          ...items.take(5).map(tile),
        const SizedBox(height: 18),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF4778D8),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spendly insight',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Add more transactions to discover your spending patterns.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Summary cards
  Widget metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // Transaction tile
  Widget tile(SpendlyTransaction t) {
    final isIncome = t.type == TransactionType.income;

    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            isIncome ? Icons.south_west : Icons.shopping_bag_outlined,
          ),
        ),
        title: Text(
          t.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${t.category} · ${DateFormat('d MMM').format(t.date)} · ${t.source}',
        ),
        trailing: Text(
          '${isIncome ? '+' : '−'}${money(t.amount)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isIncome ? Colors.green : null,
          ),
        ),
      ),
    );
  }

  // Activity
  Widget activity() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'All transactions',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...items.map(tile),
      ],
    );
  }

  // Budgets
  Widget budgets() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Budgets',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('Plan your monthly spending by category.'),
        const SizedBox(height: 18),
        budget('Food & Drinks', spent, 6000),
        budget('Transport', 0, 2500),
        budget('Shopping', 0, 3000),
      ],
    );
  }

  Widget budget(String name, double used, double limit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${money(used)} / ${money(limit)}'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (used / limit).clamp(0.0, 1.0),
              minHeight: 7,
            ),
          ],
        ),
      ),
    );
  }

  // Profile
  Widget profile() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text(
          'Profile',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        ListTile(
          leading: Icon(Icons.account_balance_outlined),
          title: Text('Connected accounts'),
          subtitle: Text(
            'Bank integrations will be added through supported providers.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Privacy & security'),
        ),
        ListTile(
          leading: Icon(Icons.settings_outlined),
          title: Text('Settings'),
        ),
      ],
    );
  }
}

// Add transaction form
class AddSheet extends StatefulWidget {
  const AddSheet({super.key});

  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  final title = TextEditingController();
  final amount = TextEditingController();

  TransactionType type = TransactionType.expense;
  String category = 'Food & Drinks';

  final categories = [
    'Food & Drinks',
    'Transport',
    'Shopping',
    'Bills',
    'Education',
    'Health',
    'Entertainment',
    'Income',
    'Other',
  ];

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid description and amount.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      SpendlyTransaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.text.trim(),
        category: category,
        amount: value,
        date: DateTime.now(),
        type: type,
        source: 'Manual',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add transaction',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (selection) {
                setState(() {
                  type = selection.first;
                  category = type == TransactionType.income
                      ? 'Income'
                      : 'Food & Drinks';
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: categories.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  category = value ?? category;
                });
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: save,
                child: const Text('Save transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
