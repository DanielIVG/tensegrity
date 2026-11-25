import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Una lectura enviada por la balanza (ESP) en /data.
class Medicion {
  const Medicion({
    required this.raw,
    required this.rawFiltrado,
    required this.gramos,
    required this.kg,
    required this.ruidoG,
    required this.sobrecarga,
    required this.humedadRaw,
    required this.humedadPct,
  });

  final int raw;
  final int rawFiltrado;
  final double gramos;
  final double kg;
  final double ruidoG;
  final bool sobrecarga;
  final int humedadRaw;
  final int humedadPct;

  factory Medicion.fromJson(Map<String, dynamic> j) => Medicion(
        raw: (j['raw'] as num).toInt(),
        rawFiltrado: (j['raw_filtrado'] as num).toInt(),
        gramos: (j['gramos'] as num).toDouble(),
        kg: (j['kg'] as num).toDouble(),
        ruidoG: (j['ruido_g'] as num).toDouble(),
        sobrecarga: j['sobrecarga'] == true,
        humedadRaw: (j['humedad_raw'] as num?)?.toInt() ?? 0,
        humedadPct: (j['humedad_pct'] as num?)?.toInt() ?? 0,
      );
}

/// Cliente HTTP simple (sin paquetes externos) para hablar con la balanza.
class BalanzaClient {
  BalanzaClient()
      : _http = HttpClient()..connectionTimeout = const Duration(seconds: 2);

  final HttpClient _http;

  Uri _uri(String host, String ruta) {
    var h = host.trim();
    h = h.replaceFirst(RegExp(r'^https?://'), '');
    h = h.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('http://$h$ruta');
  }

  Future<String> _get(Uri uri) async {
    final req = await _http.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    return body;
  }

  Future<Medicion> leer(String host) async {
    final body = await _get(_uri(host, '/data'));
    return Medicion.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Pone la balanza en cero (debe estar vacia).
  Future<void> tarar(String host) async {
    await _get(_uri(host, '/tare'));
  }

  void cerrar() => _http.close(force: true);
}
