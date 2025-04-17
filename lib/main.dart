import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';

import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sinmark SK58 Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PrintScreen(),
    );
  }
}

class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  final TextEditingController _textController = TextEditingController();
  String _status = 'Neconectat';
  List<dynamic> _scanResults = [];
  dynamic _selectedDevice;
  bool _isScanning = false;
  BleDevice? _connectedDevice;
  bool _isConnected = false;
  bool _isPrinting = false;
  final GlobalKey _qrKey = GlobalKey();
  bool _initComplete = false;
  bool _isLinux = false;

  final String _printerServiceUuid = "000018f0-0000-1000-8000-00805f9b34fb";
  final String _printerCharacteristicUuid =
      "00002af1-0000-1000-8000-00805f9b34fb";

  @override
  void initState() {
    super.initState();

    _textController.text = "SK58 Printer Test";
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_initComplete) {
      _isLinux = Theme.of(context).platform == TargetPlatform.linux;
      _setupBLE();
      _initComplete = true;
    }
  }

  @override
  void dispose() {
    _disconnectDevice();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _setupBLE() async {
    if (!_isLinux) {
      await _checkPermissions();
    } else {
      print("Rulăm pe Linux - permisiunile sunt gestionate diferit");
    }

    UniversalBle.onScanResult = (bleDevice) {
      if (!mounted) return;
      setState(() {
        if (!_scanResults
            .any((device) => device.deviceId == bleDevice.deviceId)) {
          _scanResults.add(bleDevice);
        }
      });
    };

    UniversalBle.onConnectionChange =
        (String deviceId, bool isConnected, String? error) {
      print(
          'OnConnectionChange: Device ID: $deviceId, Is Connected: $isConnected, Error: $error');
      if (!mounted) return;

      setState(() {
        if (isConnected) {
          _connectedDevice = _scanResults.firstWhere(
              (device) => device.deviceId == deviceId,
              orElse: null) as BleDevice?;
          _isConnected = true;
          _status = 'Conectat, descopăr servicii...';

          if (_connectedDevice != null) {
            _discoverServices(deviceId);
          } else {
            _status =
                'Eroare: Dispozitivul conectat nu a fost găsit în lista scanată.';
          }
        } else {
          if (_connectedDevice?.deviceId == deviceId) {
            _connectedDevice = null;
            _isConnected = false;
            _status = error != null ? 'Eroare: $error' : 'Deconectat';
          }
        }
      });
    };

    UniversalBle.onAvailabilityChange = (state) {
      print('Bluetooth state changed: $state');
      if (!mounted) return;

      setState(() {
        if (state != AvailabilityState.poweredOn) {
          _status = 'Bluetooth nu este activat';
        } else if (_status == 'Bluetooth nu este activat') {
          _status = 'Neconectat';
        }
      });
    };
  }

  Future<void> _checkPermissions() async {
    if (!_isLinux) {
      if (await Permission.bluetoothScan.request().isGranted &&
          await Permission.bluetoothConnect.request().isGranted) {
        if (Theme.of(context).platform == TargetPlatform.android) {
          if (!await Permission.location.request().isGranted) {
            if (mounted) {
              setState(() {
                _status = 'Eroare: Permisiune Locație necesară';
              });
            }
            return;
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _status = 'Eroare: Permisiuni Bluetooth necesare';
          });
        }
      }
    } else {
      print("Rulăm pe desktop - permisiunile sunt gestionate diferit");
    }
  }

  Future<void> _scanDevices() async {
    await _checkPermissions();
    if (!mounted || _status.startsWith('Eroare:')) return;

    try {
      if (!_isLinux) {
        AvailabilityState state =
            await UniversalBle.getBluetoothAvailabilityState();
        if (state != AvailabilityState.poweredOn) {
          if (mounted) {
            setState(() => _status = 'Eroare: Pornește Bluetooth!');
          }
          return;
        }
      } else {
        print("Rulăm pe desktop - presupunem că Bluetooth este pornit");
      }
    } catch (e) {
      print("Eroare la verificarea stării Bluetooth: $e");
      if (mounted) {
        setState(
            () => _status = 'Eroare: Nu se poate verifica starea Bluetooth');
      }
      return;
    }

    if (_isScanning) return;

    setState(() {
      _scanResults = [];
      _isScanning = true;
      _status = 'Scanare...';
    });

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [], withNamePrefix: []),
      );

      Timer(const Duration(seconds: 10), _stopScan);
    } catch (e) {
      print("Nu s-a putut porni scanarea: $e");
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = 'Eroare pornire scanare: $e';
        });
      }
    }
  }

  void _stopScan() {
    if (!_isScanning) return;

    UniversalBle.stopScan();

    if (!mounted) return;

    setState(() {
      _isScanning = false;
      if (_scanResults.isEmpty) {
        _status = 'Niciun dispozitiv găsit';
      } else if (!_isConnected) {
        _status = 'Selectează un dispozitiv';
      }
    });
  }

  Future<void> _connectDevice(dynamic device) async {
    if (_isScanning) {
      _stopScan();
    }
    if (!mounted) return;

    if (device is! BleDevice) {
      print(
          "Eroare: Încercare de conectare la un tip de dispozitiv necunoscut.");
      setState(() {
        _status = 'Eroare: Tip dispozitiv invalid (${device.runtimeType})';
      });
      return;
    }
    final BleDevice bleDevice = device;

    final String deviceId = bleDevice.deviceId;
    final String deviceName = bleDevice.name?.isEmpty == true
        ? 'Nume necunoscut'
        : (bleDevice.name ?? deviceId);

    setState(() {
      _selectedDevice = bleDevice;
      _status = 'Conectare la $deviceName...';
    });

    try {
      await UniversalBle.connect(deviceId).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Conectarea a durat prea mult (timeout 15s)');
        },
      );
    } catch (e) {
      print("Eroare la conectare: $e");
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _isConnected = false;
          _selectedDevice = null;
          _status = 'Eroare conectare: $e';
        });
      }
    }
  }

  Future<void> _discoverServices(String deviceId) async {
    try {
      setState(() {
        print("Începem descoperirea serviciilor pentru $deviceId...");
        _status = 'Se caută serviciul de printare...';
      });

      await UniversalBle.discoverServices(deviceId);

      setState(() {
        print("Serviciile au fost descoperite cu succes pentru $deviceId.");
        _status = 'Imprimantă pregătită';
      });
    } catch (e) {
      print("Eroare la descoperirea serviciilor: $e");
      if (mounted) {
        setState(() {
          _status = 'Eroare descoperire servicii: $e';
        });
      }
    }
  }

  Future<void> _printLabel() async {
    if (_isPrinting) {
      print("Ignorare comandă nouă: Printare deja în curs.");
      return;
    }

    final textToPrint = _textController.text;
    if (textToPrint.isEmpty) {
      _showSnackbar('EROARE: Textul nu poate fi gol!');
      return;
    }

    if (!_isConnected || _connectedDevice == null) {
      _showSnackbar('EROARE: Imprimanta nu este conectată sau pregătită.');
      return;
    }

    setState(() {
      _isPrinting = true;
      _status = 'Pregătire printare...';
    });

    try {
      List<int> commands = [];

      commands.add(0x1B);
      commands.add(0x40);

      commands.add(0x1B);
      commands.add(0x61);
      commands.add(0x01);

      commands.add(0x1D);
      commands.add(0x28);
      commands.add(0x6B);
      commands.add(0x04);
      commands.add(0x00);
      commands.add(0x31);
      commands.add(0x41);
      commands.add(0x32);
      commands.add(0x00);

      commands.add(0x1D);
      commands.add(0x28);
      commands.add(0x6B);
      commands.add(0x03);
      commands.add(0x00);
      commands.add(0x31);
      commands.add(0x43);
      commands.add(0x08);

      commands.add(0x1D);
      commands.add(0x28);
      commands.add(0x6B);
      commands.add(0x03);
      commands.add(0x00);
      commands.add(0x31);
      commands.add(0x45);
      commands.add(0x33);

      final qrData = textToPrint.codeUnits;
      final qrDataLength = qrData.length + 3;
      final pL = qrDataLength & 0xFF;
      final pH = (qrDataLength >> 8) & 0xFF;

      commands.add(0x1D);
      commands.add(0x28);
      commands.add(0x6B);
      commands.add(pL);
      commands.add(pH);
      commands.add(0x31);
      commands.add(0x50);
      commands.add(0x30);

      commands.addAll(qrData);

      commands.add(0x1D);
      commands.add(0x28);
      commands.add(0x6B);
      commands.add(0x03);
      commands.add(0x00);
      commands.add(0x31);
      commands.add(0x51);
      commands.add(0x30);

      commands.add(0x0A);

      commands.addAll(textToPrint.codeUnits);

      commands.add(0x0A);
      commands.add(0x0A);
      commands.add(0x0A);

      setState(() {
        _status = 'Se trimite la imprimantă...';
      });

      int chunkSize = 20;
      print("Trimitere ${commands.length} bytes în bucăți de $chunkSize...");

      for (int i = 0; i < commands.length; i += chunkSize) {
        if (!mounted || !_isPrinting) {
          print("Printare anulată în timpul trimiterii.");
          return;
        }

        int end =
            (i + chunkSize < commands.length) ? i + chunkSize : commands.length;
        List<int> chunk = commands.sublist(i, end);

        try {
          Uint8List dataToSend = Uint8List.fromList(chunk);

          await UniversalBle.writeValue(
            _connectedDevice!.deviceId,
            _printerServiceUuid,
            _printerCharacteristicUuid,
            dataToSend,
            BleOutputProperty.withoutResponse,
          );

          print("Trimis chunk: ${chunk.length} bytes");

          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          print("Eroare la scrierea chunk-ului: $e");
          if (mounted) {
            _showSnackbar('Eroare la trimiterea datelor: $e');
            setState(() {
              _isPrinting = false;
              _status = 'Eroare printare: $e';
            });
          }
          return;
        }
      }

      if (mounted) {
        _showSnackbar('Printare finalizată cu succes!');
        setState(() {
          _isPrinting = false;
          _status = 'Imprimantă pregătită';
        });
      }
    } catch (e) {
      print("Eroare în funcția _printLabel: $e");
      if (mounted) {
        _showSnackbar('EROARE la printare: $e');
        setState(() {
          _isPrinting = false;
          _status = 'Eroare printare: $e';
        });
      }
    }
  }


  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice != null) {
      final deviceId = _connectedDevice!.deviceId;
      final deviceName = _connectedDevice!.name ?? deviceId;
      try {
        setState(() {
          _status = 'Deconectare de la $deviceName...';
        });

        print("Deconectare universal_ble de la $deviceId...");
        await UniversalBle.disconnect(deviceId);

        if (mounted) {
          setState(() {
            _connectedDevice = null;
            _isConnected = false;
            _selectedDevice = null;
            _status = 'Deconectat';
          });
        }
      } catch (e) {
        print("Eroare la deconectare: $e");
        if (mounted) {
          setState(() {
            _connectedDevice = null;
            _isConnected = false;
            _selectedDevice = null;
            _status = 'Eroare deconectare: $e';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printare Etichete SK58'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))),
            ),
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Deconectare',
              onPressed: _disconnectDevice,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: _isConnected && !_isPrinting ? _printLabel : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPrinting ? Colors.orange : Colors.redAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: Text(
                _isPrinting ? 'Printare în curs...' : 'Printează Eticheta'),
          ),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Status: $_status'),
                const SizedBox(height: 10),
                TextField(
                  controller: _textController,
                  onChanged: (value) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Text și Număr pentru QR/Etichetă',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isScanning ||
                          _status.contains('Conectare') ||
                          _isPrinting
                      ? null
                      : _scanDevices,
                  child: Text(_isScanning
                      ? 'Scanare în curs...'
                      : 'Scanează Dispozitive Bluetooth'),
                ),
                const SizedBox(height: 10),
                const Text('Dispozitive Găsite:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: _scanResults.isEmpty && !_isScanning
                      ? Center(child: Text(_status))
                      : ListView.builder(
                          itemCount: _scanResults.length,
                          itemBuilder: (context, index) {
                            final device = _scanResults[index];

                            if (device is! BleDevice) {
                              return const SizedBox.shrink();
                            }

                            final bleDevice = device;
                            final bool isConnected =
                                _connectedDevice?.deviceId ==
                                    bleDevice.deviceId;
                            final bool isConnecting =
                                _selectedDevice?.deviceId ==
                                        bleDevice.deviceId &&
                                    _status.contains('Conectare');

                            final String deviceName =
                                bleDevice.name?.isEmpty == true
                                    ? 'Nume necunoscut (${bleDevice.deviceId})'
                                    : (bleDevice.name ?? bleDevice.deviceId);
                            final String deviceId = bleDevice.deviceId;

                            return ListTile(
                              enabled: !isConnecting,
                              title: Text(deviceName),
                              subtitle: Text(deviceId),
                              trailing: isConnecting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Icon(
                                      isConnected
                                          ? Icons.bluetooth_connected
                                          : Icons.bluetooth,
                                      color: isConnected
                                          ? Theme.of(context).primaryColor
                                          : null,
                                    ),
                              onTap: isConnecting
                                  ? null
                                  : () {
                                      print(
                                          "Dispozitiv selectat: ${bleDevice.toString()}");

                                      setState(() {
                                        _selectedDevice = bleDevice;
                                      });

                                      _connectDevice(bleDevice);
                                    },
                              selected: _selectedDevice?.deviceId == deviceId &&
                                  !isConnected,
                              selectedTileColor: Colors.grey,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -5000,
            left: 0,
            child: RepaintBoundary(
              key: _qrKey,
              child: Container(
                color: Colors.white,
                child: QrImageView(
                  data: _textController.text.isNotEmpty
                      ? _textController.text
                      : "placeholder",
                  version: QrVersions.auto,
                  size: 300,
                  gapless: false,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return "";
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
