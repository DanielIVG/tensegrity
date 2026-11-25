import 'dart:async';

import 'package:flutter/material.dart';

import 'grafica.dart';
import 'peso_client.dart';

void main() {
  runApp(const TensegrityApp());
}

class TensegrityApp extends StatelessWidget {
  const TensegrityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balanza Tensegridad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const PaginaBalanza(),
    );
  }
}

enum Estado { desconectado, conectando, conectado, error }

class PaginaBalanza extends StatefulWidget {
  const PaginaBalanza({super.key});

  @override
  State<PaginaBalanza> createState() => _PaginaBalanzaState();
}

class _PaginaBalanzaState extends State<PaginaBalanza> {
  static const _maxPuntos = 60;

  // IP por defecto: la de la red propia de la balanza (modo AP).
  // Si la balanza se conecta a tu WiFi, escribe la IP que muestra el
  // monitor serie.
  final _ipCtrl = TextEditingController(text: '192.168.4.1');
  final _cliente = BalanzaClient();
  final List<double> _historial = [];

  Timer? _timer;
  bool _ocupado = false;
  int _fallos = 0;
  Estado _estado = Estado.desconectado;
  Medicion? _ultima;
  String? _mensajeError;

  bool get _activo => _timer != null;

  @override
  void dispose() {
    _timer?.cancel();
    _cliente.cerrar();
    _ipCtrl.dispose();
    super.dispose();
  }

  void _alternarConexion() {
    if (_activo) {
      _timer?.cancel();
      setState(() {
        _timer = null;
        _estado = Estado.desconectado;
        _mensajeError = null;
      });
      return;
    }
    setState(() {
      _estado = Estado.conectando;
      _mensajeError = null;
      _fallos = 0;
      _historial.clear();
      _ultima = null;
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _leer());
    });
    _leer();
  }

  Future<void> _leer() async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      final m = await _cliente.leer(_ipCtrl.text);
      if (!mounted || !_activo) return;
      setState(() {
        _fallos = 0;
        _ultima = m;
        _estado = Estado.conectado;
        _mensajeError = null;
        _historial.add(m.gramos);
        if (_historial.length > _maxPuntos) _historial.removeAt(0);
      });
    } catch (e) {
      if (!mounted || !_activo) return;
      setState(() {
        _fallos++;
        _mensajeError = 'No se pudo leer de ${_ipCtrl.text.trim()}';
        if (_fallos >= 3) _estado = Estado.error;
      });
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _tarar() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _cliente.tarar(_ipCtrl.text);
      _historial.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Balanza puesta en cero')),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo hacer la tara')),
      );
    }
  }

  String _fmt(double v, int dec) => v.toStringAsFixed(dec);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = _ultima;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balanza de tensegridad'),
        backgroundColor: cs.inversePrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    enabled: !_activo,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'IP de la balanza',
                      hintText: '192.168.1.50',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _alternarConexion,
                  child: Text(_activo ? 'Desconectar' : 'Conectar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ChipEstado(estado: _estado, mensaje: _mensajeError),
            const SizedBox(height: 16),
            Card(
              color: (m?.sobrecarga ?? false)
                  ? cs.errorContainer
                  : cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Peso aproximado', style: tt.labelLarge),
                    const SizedBox(height: 8),
                    Text(
                      m == null ? '— g' : '≈ ${_fmt(m.gramos, 0)} g',
                      style: tt.displayMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      m == null ? '— kg' : '≈ ${_fmt(m.kg, 2)} kg',
                      style: tt.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      m == null
                          ? 'Sin datos'
                          : 'Ruido estimado: ±${_fmt(m.ruidoG, 1)} g',
                      style: tt.bodyMedium,
                    ),
                    if (m?.sobrecarga ?? false) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sobrecarga: más de 10 kg',
                        style: tt.titleSmall?.copyWith(color: cs.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lectura del HX711 (cuentas)', style: tt.titleSmall),
                    const SizedBox(height: 8),
                    Text('Cruda: ${m?.raw ?? '—'}'),
                    Text('Filtrada: ${m?.rawFiltrado ?? '—'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Humedad de la tierra (YL-38)', style: tt.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      m == null ? '— %' : '${m.humedadPct} %',
                      style: tt.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: m == null ? 0 : m.humedadPct / 100,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Text('Lectura cruda: ${m?.humedadRaw ?? '—'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Últimas lecturas', style: tt.titleSmall),
                    const SizedBox(height: 8),
                    GraficaPeso(valores: _historial),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _estado == Estado.conectado ? _tarar : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Tara (poner en cero con la balanza vacía)'),
            ),
            const SizedBox(height: 16),
            Text(
              'El peso es aproximado: la celda tiene ruido y deriva con el '
              'tiempo y la temperatura. Haz la tara con la balanza vacía y '
              'repítela si el cero se mueve.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.estado, this.mensaje});

  final Estado estado;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    late final String texto;
    late final Color color;
    switch (estado) {
      case Estado.desconectado:
        texto = 'Desconectado';
        color = cs.outline;
      case Estado.conectando:
        texto = 'Conectando…';
        color = cs.tertiary;
      case Estado.conectado:
        texto = 'Conectado';
        color = Colors.green;
      case Estado.error:
        texto = mensaje ?? 'Sin conexión';
        color = cs.error;
    }
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(texto)),
      ],
    );
  }
}
