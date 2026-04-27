import 'package:intl/intl.dart';

class BillRecord {
  final String id;
  final DateTime date;
  final String imagePath;
  final bool isAuthentic;
  final String confidence;
  final String denomination;
  final String currency;   // 'USD' | 'ECU' | 'UNKNOWN'

  BillRecord({
    required this.id,
    required this.date,
    required this.imagePath,
    required this.isAuthentic,
    required this.confidence,
    required this.denomination,
    this.currency = 'UNKNOWN',
  });

  String get formattedDate => DateFormat('dd/MM/yyyy HH:mm').format(date);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'imagePath': imagePath,
      'isAuthentic': isAuthentic ? 1 : 0,
      'confidence': confidence,
      'denomination': denomination,
      'currency': currency,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  factory BillRecord.fromMap(Map<String, dynamic> map) {
    return BillRecord(
      id: map['id'] ?? '',
      date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
      imagePath: map['imagePath'] ?? '',
      isAuthentic: map['isAuthentic'] == 1,
      confidence: map['confidence'] ?? '0%',
      denomination: map['denomination'] ?? 'Desconocida',
      currency: map['currency'] ?? 'UNKNOWN',
    );
  }

  @override
  String toString() =>
      'BillRecord(id: $id, denomination: $denomination, currency: $currency, isAuthentic: $isAuthentic)';
}