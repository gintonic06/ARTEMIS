import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parámetros',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red.shade400),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();

  final List<String> nombresCampos = [
    'Nombre',
    'Edad',
    'Observación',
    'Altura (cm)',
    'Segmento Hombro a Tobillo (cm)',
    'Segmento Braquial (cm)',
  ];

  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final Map<String, String> valores = {};

  void _goToNextPage() {
    if (_formKey.currentState!.validate()) {
      for (int i = 0; i < nombresCampos.length; i++) {
        valores[nombresCampos[i]] = _controllers[i].text;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ResultPage(valores: valores)),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Artemis',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            fontFamily: 'Monterchi Serif',
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 20.0),
              child: Text(
                'Datos del paciente',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Image.asset(
                      'assets/Dibujo.png',
                      fit: BoxFit.contain,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              const Icon(Icons.error_outline, size: 100),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Form(
                          key: _formKey,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (int i = 0; i < nombresCampos.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12.0,
                                    ),
                                    child: TextFormField(
                                      style: const TextStyle(fontSize: 20),
                                      controller: _controllers[i],
                                      decoration: InputDecoration(
                                        labelStyle: const TextStyle(
                                          fontSize: 20,
                                        ),
                                        labelText: nombresCampos[i],
                                        border: const OutlineInputBorder(),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Este campo es obligatorio';
                                        }
                                        if (i == 1 || i >= 3) {
                                          final double? numValue =
                                              double.tryParse(value);
                                          if (numValue == null) {
                                            return 'Debe ser un número válido';
                                          }
                                          switch (i) {
                                            case 1: // Edad
                                              if (numValue < 0 ||
                                                  numValue > 120) {
                                                return 'Edad inválida';
                                              }
                                              break;
                                            case 3: // Altura
                                              if (numValue < 50 ||
                                                  numValue > 250) {
                                                return 'Altura inválida';
                                              }
                                              break;
                                            case 4: // Hombro a tobillo
                                              if (numValue < 30 ||
                                                  numValue > 180) {
                                                return 'Segmento inválido';
                                              }
                                              break;
                                            case 5: // Braquial
                                              if (numValue < 10 ||
                                                  numValue > 80) {
                                                return 'Segmento inválido';
                                              }
                                              break;
                                          }
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: _goToNextPage,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(
                                      double.infinity,
                                      50,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: const Text('Siguiente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultPage extends StatefulWidget {
  final Map<String, String> valores;

  const ResultPage({super.key, required this.valores});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  List<FlSpot> tibialData = [];
  List<FlSpot> braquialData = [];
  int _currentIndex = 0;
  //Timer? _timer;
  bool _recording = false;
  Color alertaColor = Colors.transparent;
  bool showAlerta = false;
  bool connectionError = false;
  //double _maxX = 5.0;
  //double _minX = 0;
  double _maxY = 2.0;
  final int _maxDataPoints = 50 * 30;
  late WebSocketChannel channel;
  Stream? dataStream;
  Timer? _stopRecordingTimer;
  double windowSize = 5.0;
  double windowStart = 0.0; // Inicio de la ventana actual
  late Timer _windowTimer;
  bool isLiveWindow = false;
  double _windowStart = 0;
  final double _windowSize = 5;
  double? vopMedida;
  double? freqMedida;

  @override
  void dispose() {
    _stopRecordingTimer?.cancel();
    channel?.sink.close();
    _windowTimer.cancel();
    _stopRecordingTimer?.cancel();
    channel.sink.close();
    super.dispose();
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);
      final double tibialY = (data['tibial'] ?? 0).toDouble();
      final double braquialY = (data['braquial'] ?? 0).toDouble();
      if (!mounted) return;

      setState(() {
        connectionError = false;
      });
      _updateChartData(tibialY, braquialY);
      if (data.containsKey("vop")) {
        // Recibí el resultado final de VOP
        setState(() {
          vopMedida = data["vop"]?.toDouble();
           // Ya terminó la grabación y análisis
        });
        return;
      }
      if (data.containsKey("freq")) {
        // Recibí el resultado final de Freq
        setState(() {
          freqMedida = data["freq"];
          _recording = false; // Ya terminó la grabación y análisis
        });
        return;
      }
    } catch (e) {
      print('Error procesando mensaje WebSocket: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    // Abres la conexión WebSocket solo 1 vez
    channel = WebSocketChannel.connect(
      Uri.parse('ws://172.20.10.6:8765/ws/flutter'),
    );

    // Escuchas mensajes siempre que lleguen mientras el widget esté activo
    channel.stream.listen(
      (message) {
        if (!_recording && vopMedida != null && freqMedida != null) return; // Solo procesa si grabando
        _handleWebSocketMessage(message);
      },
      onError: (error) {
        if (!mounted) return;

        setState(() => connectionError = true);
      },
      onDone: () {
        if (!mounted) return;

        setState(() => connectionError = true);
      },
    );
    // Timer para avanzar ventana cada 5 segundos
    _windowTimer = Timer.periodic(Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        if (!isLiveWindow) {
          windowStart += windowSize;
          if (windowStart >= 5) {
            isLiveWindow = true; // Pasamos a modo seguimiento en vivo
          }
        }
      });
    });
  }

  void _updateChartData(double tibialY, double braquialY) {
    if (!mounted) return;
    setState(() {
      double t = _currentIndex.toDouble() * (1 / 50);

      // Añadir nuevos puntos
      tibialData.add(FlSpot(t, tibialY));
      braquialData.add(FlSpot(t, braquialY));
      _currentIndex++;

      // Ajustar ejes dinámicamente
      //_maxX = t < 5 ? 5 : t; // Mostrar 2 segundos más que el último dato
      //_minX = max(0, _maxX - 5);
      _maxY = max(
        _maxY,
        max(tibialY, braquialY) + 0.5,
      ); // Margen de 0.5 unidades

      // Limitar datos para mejor rendimiento
      if (tibialData.length > _maxDataPoints) {
        tibialData.removeAt(0);
        braquialData.removeAt(0);
      }

      // Detección de anomalías
      if (tibialY > 35 || braquialY > 35) {
        alertaColor = Colors.yellow;
        showAlerta = true;
      }
    });
    if (isLiveWindow) {
      // En modo vivo maxX = t, minX = 10 (ventana fija que crece con t)
      windowStart = 5;
    }
  }

  void _startRecording() {
    // Enviar altura al backend antes de empezar la grabación
    final alturaTexto = widget.valores['Altura (cm)'];
    if (alturaTexto != null) {
      final altura = double.tryParse(alturaTexto);
      if (altura != null) {
        channel.sink.add(
          jsonEncode({'command': 'set_altura', 'altura': altura}),
        );
      }
    }
    if (_recording) return;
    if (!mounted) return;
    setState(() {
      _recording = true;
      vopMedida = null;
      freqMedida = null;
      tibialData.clear();
      braquialData.clear();
      _currentIndex = 0;
      //_maxX = 5;
      _maxY = 0;
      alertaColor = Colors.transparent;
      showAlerta = false;
      connectionError = false;
      _windowStart = 0;
    });

    // Envías start para que el servidor comience a enviar datos
    channel.sink.add('start');

    // Reiniciás el timer de ventana
    _windowTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        _windowStart += _windowSize;
      });
    });

    // Timer para detener la grabación después de 30 segundos
    _stopRecordingTimer = Timer(const Duration(seconds: 30), () {
      _stopRecording();
    });
  }

  void _stopRecording() {
    if (!_recording) return;

    // Envías stop para detener la simulación en el servidor
    channel.sink.add('stop');

    // Cancelás timers
    _windowTimer.cancel();
    _stopRecordingTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _recording = false;
    });
  }

  void _clearAlerta() {
    if (!mounted) return;

    setState(() {
      alertaColor = Colors.transparent;
      showAlerta = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.valores['Nombre'] ?? '';
    final edad = widget.valores['Edad'] ?? '';
    final obs = widget.valores['Observación'] ?? '';
    final altura = widget.valores['Altura (cm)'] ?? '';
    final lT = widget.valores['Segmento Hombro a Tobillo (cm)'] ?? '';
    final lB = widget.valores['Segmento Braquial (cm)'] ?? '';
    final double minX = _windowStart;
    final double maxX = _windowStart + _windowSize;

    final visibleTibialData =
        tibialData
            .where((point) => point.x >= minX && point.x <= maxX)
            .toList();

    final visibleBraquialData =
        braquialData
            .where((point) => point.x >= minX && point.x <= maxX)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Artemis',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            fontFamily: 'Monterchi Serif',
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Icon(
            connectionError ? Icons.wifi_off : Icons.wifi,
            color: connectionError ? Colors.red : Colors.green,
            size: 30,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          double baseFontSize = min(constraints.maxWidth * 0.015, 22.0);

          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LineChart(
                            LineChartData(
                              minX: minX,
                              maxX: maxX,

                              minY: 0,
                              maxY: _maxY,
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  axisNameSize: baseFontSize * 3,
                                  axisNameWidget: Text(
                                    'Tiempo (s)',
                                    style: TextStyle(
                                      fontSize: baseFontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    reservedSize: baseFontSize * 2.5,
                                    getTitlesWidget: (value, meta) {
                                      return SideTitleWidget(
                                        axisSide: meta.axisSide,
                                        space: 6, // espacio con el eje
                                        child: Transform.rotate(
                                          angle:
                                              -0.5, // rotar en radianes (-0.5 ≈ -30°)
                                          child: Text(
                                            '${value.toStringAsFixed(1).replaceAll('.', ',')}s',
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  axisNameSize: baseFontSize * 3,
                                  axisNameWidget: RotatedBox(
                                    quarterTurns: 0,
                                    child: Text(
                                      'Amplitud',
                                      style: TextStyle(
                                        fontSize: baseFontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  sideTitles: SideTitles(
                                    showTitles: false,
                                    reservedSize: baseFontSize * 2.5,
                                    interval: 0.5,
                                    // max(5, _maxY / 5).roundToDouble(),
                                    getTitlesWidget:
                                        (value, meta) => Text(
                                          '${value.toInt()}',
                                          style: TextStyle(
                                            fontSize: baseFontSize * 0.8,
                                          ),
                                        ),
                                  ),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              gridData: FlGridData(show: true),
                              borderData: FlBorderData(
                                show: true,
                                border: const Border(
                                  left: BorderSide(),
                                  bottom: BorderSide(),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: visibleTibialData,
                                  isCurved: true,
                                  color: Colors.red,
                                  barWidth: 2,
                                  dotData: FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.red.withAlpha(
                                      (0.1 * 255).toInt(),
                                    ),
                                  ),
                                ),
                                LineChartBarData(
                                  spots: visibleBraquialData,
                                  isCurved: true,
                                  color: Colors.blue,
                                  barWidth: 2,
                                  dotData: FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.blue.withAlpha(
                                      (0.1 * 255).toInt(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color.fromARGB(
                                        255,
                                        152,
                                        49,
                                        18,
                                      ),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Observación: $obs',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                      Text(
                                        'Nombre: $nombre',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                      Text(
                                        'Edad: $edad',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color.fromARGB(
                                        255,
                                        152,
                                        49,
                                        18,
                                      ),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Altura: $altura cm',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                      Text(
                                        'Lₜ: $lT cm',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                      Text(
                                        'Lᵦ: $lB cm',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: baseFontSize * 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (showAlerta)
                        Column(
                          children: [
                            Icon(Icons.warning, size: 50, color: alertaColor),
                            const SizedBox(height: 8),
                            Text(
                              '¡Advertencia! Señal anómala detectada',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: baseFontSize * 0.9,
                              ),
                            ),
                          ],
                        ),
                      Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: EdgeInsets.all(showAlerta ? 8.0 : 16.0),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color.fromARGB(255, 152, 49, 18),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              vopMedida != null
                                  ? '${vopMedida!.toStringAsFixed(2)} m/s'
                                  : 'VOP',
                              style: TextStyle(
                                fontSize:
                                    showAlerta
                                        ? baseFontSize * 3
                                        : baseFontSize * 3,
                              ),
                            ),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 10,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color.fromARGB(
                                      255,
                                      152,
                                      49,
                                      18,
                                    ),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  freqMedida != null
                                  ? '${freqMedida!.toStringAsFixed(0)} bpm'
                                  : 'FR',
                                  style: TextStyle(fontSize: baseFontSize * 3),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color.fromARGB(
                                      255,
                                      152,
                                      49,
                                      18,
                                    ),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'I%',
                                  style: TextStyle(fontSize: baseFontSize * 4),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          ElevatedButton(
                            onPressed: _recording ? null : _startRecording,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              'Empezar',
                              style: TextStyle(
                                fontSize: baseFontSize * 4,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 10,
                            children: [
                              ElevatedButton(
                                onPressed:
                                    (_recording || showAlerta)
                                        ? () {
                                          if (_recording) _stopRecording();
                                          if (showAlerta) _clearAlerta();
                                        }
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 50,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Esc',
                                  style: TextStyle(
                                    fontSize: baseFontSize * 2.4,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Enviar',
                                  style: TextStyle(
                                    fontSize: baseFontSize * 2.4,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
