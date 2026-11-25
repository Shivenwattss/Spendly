import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabs;
  bool loading = true;
  String? error;
  List goals = [], budgets = [], recurring = [], debts = [];
  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this);
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${ApiService.baseUrl}$path');
    late http.Response r;
    if (method == 'POST') {
      r = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
    } else if (method == 'PATCH')
      r = await http.patch(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
    else if (method == 'DELETE')
      r = await http.delete(uri);
    else
      r = await http.get(uri);
    final data = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception(data is Map ? (data['detail'] ?? r.body) : r.body);
    return data;
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        request('/goals'),
        request('/budgets'),
        request('/recurring'),
        request('/debts')
      ]);
      if (!mounted) return;
      setState(() {
        goals = r[0];
        budgets = r[1];
        recurring = r[2];
        debts = r[3];
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          error = e.toString();
        });
    }
  }

  Future<void> form(String title, List<String> labels,
      Future<void> Function(Map<String, String>) save) async {
    final ctrls = labels.map((_) => TextEditingController()).toList();
    final values = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                            controller: ctrls[i],
                            keyboardType: i == 0
                                ? TextInputType.text
                                : const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                                labelText: labels[i],
                                border: const OutlineInputBorder())))
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          ctx, ctrls.map((c) => c.text.trim()).toList()),
                      child: const Text('Save'))
                ]));
    for (final c in ctrls) {
      c.dispose();
    }
    if (values == null) return;
    try {
      await save(
          {for (var i = 0; i < labels.length; i++) labels[i]: values[i]});
      await load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  double numv(dynamic x) =>
      x is num ? x.toDouble() : double.tryParse('$x') ?? 0;
  String rupee(dynamic x) => '₹${numv(x).toStringAsFixed(0)}';
  Widget empty(String text) => Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
          child: Text(text, style: const TextStyle(color: Colors.grey))));
  Widget goalList() => ListView(padding: const EdgeInsets.all(16), children: [
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
                onPressed: () => form(
                    'New savings goal',
                    ['Name', 'Target amount', 'Already saved'],
                    (v) => request('/goals', method: 'POST', body: {
                          'name': v['Name'],
                          'target_amount':
                              double.tryParse(v['Target amount'] ?? '') ?? 0,
                          'saved_amount':
                              double.tryParse(v['Already saved'] ?? '') ?? 0
                        })),
                icon: const Icon(Icons.add),
                label: const Text('Add goal'))),
        if (goals.isEmpty)
          empty('Create a goal such as a laptop, trip or emergency fund.'),
        ...goals.map((g) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('${g['name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16))),
                        Text('${g['progress']}%')
                      ]),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: (numv(g['progress']) / 100).clamp(0, 1)),
                      const SizedBox(height: 8),
                      Text(
                          '${rupee(g['saved_amount'])} saved of ${rupee(g['target_amount'])} · ${rupee(g['remaining'])} remaining'),
                      Text(
                          'Suggested monthly contribution: ${rupee(g['suggested_monthly_contribution'])}',
                          style: const TextStyle(color: Colors.grey)),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                            onPressed: () => form(
                                'Update saved amount',
                                ['New saved amount'],
                                (v) => request('/goals/${g['id']}',
                                        method: 'PATCH',
                                        body: {
                                          'saved_amount': double.tryParse(
                                                  v['New saved amount'] ??
                                                      '') ??
                                              0
                                        })),
                            child: const Text('Update progress')),
                        IconButton(
                            onPressed: () async {
                              await request('/goals/${g['id']}',
                                  method: 'DELETE');
                              load();
                            },
                            icon: const Icon(Icons.delete_outline))
                      ])
                    ]))))
      ]);
  Widget budgetList() => ListView(padding: const EdgeInsets.all(16), children: [
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
                onPressed: () => form(
                    'Set category budget',
                    ['Category', 'Monthly limit'],
                    (v) => request('/budgets', method: 'POST', body: {
                          'category': v['Category'],
                          'monthly_limit':
                              double.tryParse(v['Monthly limit'] ?? '') ?? 0
                        })),
                icon: const Icon(Icons.add),
                label: const Text('Set budget'))),
        if (budgets.isEmpty)
          empty('Set monthly limits to track category spending.'),
        ...budgets.map((b) => Card(
            child: ListTile(
                title: Text('${b['category']}'),
                subtitle: LinearProgressIndicator(
                    value: (numv(b['percent']) / 100).clamp(0, 1)),
                trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rupee(b['spent'])),
                      Text('of ${rupee(b['monthly_limit'])}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey))
                    ]))))
      ]);
  Widget recurringList() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
                onPressed: () => form(
                    'Add recurring payment',
                    ['Name', 'Amount'],
                    (v) => request('/recurring', method: 'POST', body: {
                          'name': v['Name'],
                          'amount': double.tryParse(v['Amount'] ?? '') ?? 0,
                          'kind': 'subscription',
                          'cadence': 'monthly'
                        })),
                icon: const Icon(Icons.add),
                label: const Text('Add payment'))),
        if (recurring.isEmpty)
          empty('Track subscriptions and recurring bills here.'),
        ...recurring.map((x) => Card(
            child: ListTile(
                title: Text('${x['name']}'),
                subtitle: Text('${x['kind']} · ${x['cadence']}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(rupee(x['amount'])),
                  IconButton(
                      onPressed: () async {
                        await request('/recurring/${x['id']}',
                            method: 'DELETE');
                        load();
                      },
                      icon: const Icon(Icons.delete_outline))
                ]))))
      ]);
  Widget debtList() => ListView(padding: const EdgeInsets.all(16), children: [
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
                onPressed: () => form(
                    'Add debt or EMI',
                    [
                      'Name',
                      'Outstanding balance',
                      'Monthly payment',
                      'Annual interest rate (%)'
                    ],
                    (v) => request('/debts', method: 'POST', body: {
                          'name': v['Name'],
                          'outstanding':
                              double.tryParse(v['Outstanding balance'] ?? '') ??
                                  0,
                          'monthly_payment':
                              double.tryParse(v['Monthly payment'] ?? '') ?? 0,
                          'interest_rate': double.tryParse(
                                  v['Annual interest rate (%)'] ?? '') ??
                              0
                        })),
                icon: const Icon(Icons.add),
                label: const Text('Add debt'))),
        if (debts.isEmpty)
          empty('Track outstanding loans, EMIs and repayments.'),
        ...debts.map((d) => Card(
            child: ListTile(
                title: Text('${d['name']}'),
                subtitle: Text(
                    'Monthly payment ${rupee(d['monthly_payment'])} · ${d['interest_rate']}% p.a.'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(rupee(d['outstanding'])),
                  IconButton(
                      onPressed: () async {
                        await request('/debts/${d['id']}', method: 'DELETE');
                        load();
                      },
                      icon: const Icon(Icons.delete_outline))
                ]))))
      ]);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Financial planning'),
          bottom: TabBar(controller: tabs, isScrollable: true, tabs: const [
            Tab(text: 'Goals'),
            Tab(text: 'Budgets'),
            Tab(text: 'Subscriptions'),
            Tab(text: 'Debt & EMI')
          ])),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Could not load planning data: $error'))
              : TabBarView(controller: tabs, children: [
                  goalList(),
                  budgetList(),
                  recurringList(),
                  debtList()
                ]));
}
