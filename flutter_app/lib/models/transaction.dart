enum TransactionType { income, expense }

class SpendlyTransaction {
  final String id;
  final String title;
  final String category;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String source;

  const SpendlyTransaction({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    required this.type,
    this.source = 'Manual',
  });

  factory SpendlyTransaction.fromJson(Map<String, dynamic> json) => SpendlyTransaction(
        id: json['id'].toString(),
        title: json['title'] as String? ?? json['description'] as String? ?? 'Transaction',
        category: json['category'] as String? ?? 'Other',
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'].toString()),
        type: json['type'] == 'income' ? TransactionType.income : TransactionType.expense,
        source: json['source'] as String? ?? 'Manual',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'amount': amount,
        'type': type.name,
        'date': date.toIso8601String(),
        'source': source,
      };
}
