import 'package:flutter/material.dart';

/// Grafica de linea simple con las ultimas lecturas de peso (en gramos).
class GraficaPeso extends StatelessWidget {
  const GraficaPeso({super.key, required this.valores});

  final List<double> valores;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: CustomPaint(
        painter: _PintorGrafica(
          valores: List<double>.of(valores),
          linea: cs.primary,
          rejilla: cs.outlineVariant,
          texto: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PintorGrafica extends CustomPainter {
  _PintorGrafica({
    required this.valores,
    required this.linea,
    required this.rejilla,
    required this.texto,
  });

  final List<double> valores;
  final Color linea;
  final Color rejilla;
  final Color texto;

  void _etiqueta(Canvas canvas, String s, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 11, color: texto)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final marco = Paint()
      ..color = rejilla
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, marco);

    if (valores.length < 2) {
      _etiqueta(canvas, 'Esperando datos...', const Offset(8, 8));
      return;
    }

    var minV = valores.reduce((a, b) => a < b ? a : b);
    var maxV = valores.reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 20) {
      final centro = (maxV + minV) / 2;
      minV = centro - 10;
      maxV = centro + 10;
    }
    final rango = maxV - minV;
    const margen = 18.0;
    final alto = size.height - 2 * margen;

    final path = Path();
    for (var i = 0; i < valores.length; i++) {
      final x = size.width * i / (valores.length - 1);
      final y = margen + alto * (1 - (valores[i] - minV) / rango);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = linea
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _etiqueta(canvas, '${maxV.round()} g', const Offset(4, 2));
    _etiqueta(canvas, '${minV.round()} g', Offset(4, size.height - 15));
  }

  @override
  bool shouldRepaint(covariant _PintorGrafica old) => true;
}
