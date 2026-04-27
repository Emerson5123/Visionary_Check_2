import 'package:flutter/material.dart';
import '../services/bill_repository.dart';
import '../models/bill_record.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/accessible_widget.dart';
import '../services/tts_service.dart';
import '../services/accessibility_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final BillRepository _billRepository = BillRepository();
  final TTSService _tts = TTSService();
  final AccessibilityService _accessibility = AccessibilityService();
  late Future<List<BillRecord>> _billsFuture;

  @override
  void initState() {
    super.initState();
    _accessibility.clearFocus();
    _billsFuture = _billRepository.getAllBills();
    _announceScreen();
  }

  void _announceScreen() async {
    await Future.delayed(const Duration(milliseconds: 400));
    await _tts.speak(
      'Historial de verificaciones. '
          'Toca un elemento para escucharlo, doble toque para ver detalles. '
          'Desliza a la izquierda sobre un registro para eliminarlo.',
    );
  }

  void _reloadBills() {
    setState(() => _billsFuture = _billRepository.getAllBills());
  }

  void _showDeleteConfirmation() async {
    await _tts.speak('¿Deseas eliminar todo el historial? Doble toque en Eliminar para confirmar.');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.deepPurple.shade800,
        title: const Text('Limpiar Historial', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Eliminar TODO el historial? Esta acción no se puede deshacer.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.amber)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await _billRepository.clearAllBills();
              if (mounted) {
                await _tts.speak(
                  success ? 'Historial eliminado.' : 'Error al eliminar el historial.',
                );
                _reloadBills();
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBillDetails(BillRecord bill) async {
    final currencyLabel = bill.currency == 'USD'
        ? 'dólar estadounidense'
        : bill.currency == 'ECU' ? 'billete ecuatoriano' : 'billete';

    await _tts.speak(
      'Detalles: $currencyLabel de ${bill.denomination}, '
          '${bill.isAuthentic ? 'auténtico' : 'sospechoso'}, '
          'confianza ${bill.confidence}, '
          'verificado el ${bill.formattedDate}.',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.deepPurple.shade800,
        title: const Text('Detalles del Billete', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogRow('Denominación', bill.denomination),
            const SizedBox(height: 10),
            _dialogRow('Moneda', bill.currency == 'USD' ? 'USD 🇺🇸' : bill.currency == 'ECU' ? 'Ecuador 🇪🇨' : 'Desconocida'),
            const SizedBox(height: 10),
            _dialogRow('Estado', bill.isAuthentic ? 'Auténtico ✅' : 'Sospechoso ⚠️'),
            const SizedBox(height: 10),
            _dialogRow('Confianza', bill.confidence),
            const SizedBox(height: 10),
            _dialogRow('Fecha', bill.formattedDate),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Historial',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
        onDeletePressed: _showDeleteConfirmation,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade900, Colors.deepPurple.shade500],
          ),
        ),
        child: FutureBuilder<List<BillRecord>>(
          future: _billsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 60),
                    const SizedBox(height: 16),
                    AccessibleButton(
                      description: 'Botón reintentar cargar historial',
                      label: 'Reintentar',
                      onActivate: _reloadBills,
                      backgroundColor: Colors.amber,
                      textColor: Colors.black,
                    ),
                  ],
                ),
              );
            }

            final bills = snapshot.data ?? [];

            if (bills.isEmpty) {
              return Center(
                child: AccessibleWidget(
                  description: 'No hay verificaciones aún. Vuelve a la pantalla principal para verificar un billete.',
                  onActivate: () => _tts.speak('No hay verificaciones aún. Vuelve a la pantalla principal para verificar un billete.'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, color: Colors.white.withOpacity(0.3), size: 80),
                      const SizedBox(height: 16),
                      Text('No hay verificaciones aún',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                final bill = bills[index];
                final currencyLabel = bill.currency == 'USD'
                    ? 'dólar estadounidense'
                    : bill.currency == 'ECU' ? 'billete ecuatoriano' : 'billete';
                final accessibleDesc =
                    'Registro ${index + 1}: $currencyLabel de ${bill.denomination}, '
                    '${bill.isAuthentic ? 'auténtico' : 'sospechoso'}, '
                    'confianza ${bill.confidence}, '
                    'verificado el ${bill.formattedDate}. '
                    'Doble toque para ver detalles.';

                return Dismissible(
                  key: Key(bill.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    await _tts.speak(
                      '¿Eliminar este registro de ${bill.denomination}? Doble toque en Sí para confirmar.',
                    );
                    return await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: Colors.deepPurple.shade800,
                        title: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                        content: const Text('¿Eliminar este registro?', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Sí', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) async {
                    await _billRepository.deleteBill(bill.id);
                    _reloadBills();
                    await _tts.speak('Registro eliminado.');
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: AccessibleWidget(
                    description: accessibleDesc,
                    onActivate: () => _showBillDetails(bill),
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: Colors.white.withOpacity(0.1),
                      child: ListTile(
                        leading: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: bill.isAuthentic ? Colors.green.shade400 : Colors.red.shade400,
                          ),
                          child: Icon(
                            bill.isAuthentic ? Icons.check : Icons.close,
                            color: Colors.white, size: 26,
                          ),
                        ),
                        title: Text(
                          '${bill.currency == 'USD' ? 'USD' : 'ECU'} ${bill.denomination}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(bill.formattedDate,
                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: bill.isAuthentic ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    bill.isAuthentic ? 'Auténtico' : 'Sospechoso',
                                    style: TextStyle(
                                      color: bill.isAuthentic ? Colors.green.shade200 : Colors.red.shade200,
                                      fontSize: 11, fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(bill.confidence,
                                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5), size: 16),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ', style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}