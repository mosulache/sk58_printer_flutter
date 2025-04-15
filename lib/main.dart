import 'package:flutter/material.dart';
import 'dart:async'; // Pentru Timer
import 'dart:typed_data'; // Pentru Uint8List
import 'dart:ui' as ui; // Pentru ui.Image
import 'package:flutter/rendering.dart'; // Pentru RepaintBoundary

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Import QR
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart'; // Import ESC/POS
import 'package:image/image.dart' as img; // Import Image

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
        primarySwatch: Colors.blue, // Sau ce culoare vrei tu, fetițo
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
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _selectedDevice;
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  BluetoothDevice? _connectedDevice;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  BluetoothCharacteristic? _writeCharacteristic;
  final GlobalKey _qrKey = GlobalKey(); // Cheie pentru a captura widget-ul QR
  bool _isPrinting = false; // << ADAUGAT: Starea de printare

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _textController.dispose(); // Curățăm controller-ul
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted) {
      // Permisiuni OK
      if (Theme.of(context).platform == TargetPlatform.android) {
        if (!await Permission.location.request().isGranted) {
          if (!mounted) return;
          setState(() {
            _status = 'Eroare: Permisiune Locație necesară';
          });
          return;
        }
      }
    } else {
      if (!mounted) return;
      setState(() {
        _status = 'Eroare: Permisiuni Bluetooth necesare';
      });
    }
  }

  Future<void> _scanDevices() async {
    await _checkPermissions();
    if (!mounted || _status.startsWith('Eroare:')) return;

    if (!await FlutterBluePlus.isSupported) {
       if (!mounted) return;
       setState(() => _status = 'Bluetooth nu este suportat');
       return;
    }
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
       if (!mounted) return;
      setState(() => _status = 'Eroare: Pornește Bluetooth!');
      return;
    }
    if (_isScanning) return;

    setState(() {
      _scanResults = [];
      _isScanning = true;
      _status = 'Scanare...';
    });

    try {
      Timer? stopScanTimer;
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        final now = DateTime.now();
        final filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
        setState(() {
          _scanResults = filteredResults;
        });
        stopScanTimer?.cancel();
        stopScanTimer = Timer(const Duration(seconds: 5), _stopScan);
      }, onError: (e) {
        print("Eroare la scanare: $e");
        if (!mounted) return;
        setState(() => _status = 'Eroare scanare');
        _stopScan();
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      stopScanTimer ??= Timer(const Duration(seconds: 15), _stopScan);
    } catch (e) {
      print("Nu s-a putut porni scanarea: $e");
       if (!mounted) return;
      setState(() => _status = 'Eroare pornire scanare');
      _stopScan();
    }
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
     if (!mounted) return;
    setState(() {
      _isScanning = false;
      if (_scanResults.isEmpty) {
        _status = 'Niciun dispozitiv găsit';
      } else if (_connectionState == BluetoothConnectionState.disconnected){
         // Actualizăm statusul doar dacă nu suntem conectați/în conectare
         _status = 'Selectează un dispozitiv';
      }
    });
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    if (_isScanning) {
      // Așteptăm oprirea scanării și anularea subscripției
      await _scanSubscription?.cancel();
      await FlutterBluePlus.stopScan();
      if (mounted) {
        setState(() { _isScanning = false; });
      }
    }
     if (!mounted) return;

    setState(() {
      _selectedDevice = device;
      _status = 'Conectare la ${device.platformName}...';
      _writeCharacteristic = null;
    });

    await _connectionSubscription?.cancel(); // Anulăm subscripția veche

    _connectionSubscription = device.connectionState.listen((BluetoothConnectionState state) async {
       if (!mounted) return;
      // Actualizăm starea generală
       setState(() { _connectionState = state; });

       // Gestionăm logica specifică fiecărei stări
       if (state == BluetoothConnectionState.connected) {
          setState(() {
             _connectedDevice = device;
             _status = 'Conectat, descopăr servicii...';
          });
          await _discoverServices(); // Descoperim serviciile
       } else if (state == BluetoothConnectionState.disconnected) {
          // Setăm stările interne la deconectare completă
          setState(() {
             _connectedDevice = null;
             _writeCharacteristic = null;
             // Verificăm dacă deconectarea a fost intenționată sau o eroare
             if (_status.contains('Conectare') || _status.contains('descopăr')) {
                 _status = 'Eroare conexiune/servicii';
             } else {
                 _status = 'Deconectat';
             }
          });
       } else { // connecting sau disconnecting
           setState(() {
              _status = '${state.toString().split('.').last.capitalize()}...';
           });
       }
    }, onError: (dynamic error) { // Adăugăm gestionare erori pe stream
         print("Eroare pe streamul de conexiune: $error");
         if (!mounted) return;
         setState(() {
            _status = 'Eroare conexiune stream';
            _connectionState = BluetoothConnectionState.disconnected;
            _connectedDevice = null;
            _writeCharacteristic = null;
         });
      }
    );


    // Încercarea efectivă de conectare
    try {
       await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 15),
       );
       // Nu mai setăm status aici, lăsăm listener-ul să o facă
    } on TimeoutException catch (_) {
        if (!mounted) return;
        print("Timeout la conectare");
        _showSnackbar("Timeout la conectare. Verificați imprimanta.");
         setState(() {
            _status = 'Timeout conectare';
            _connectionState = BluetoothConnectionState.disconnected; // Asigurăm starea corectă
         });
         await _connectionSubscription?.cancel(); // Oprește listenerul dacă a fost timeout
    } catch (e) {
        if (!mounted) return;
        print("Eroare la conectare: $e");
        _showSnackbar("Eroare la conectare: $e");
         setState(() {
            _status = 'Eroare conectare';
            _connectionState = BluetoothConnectionState.disconnected; // Asigurăm starea corectă
         });
          await _connectionSubscription?.cancel(); // Oprește listenerul dacă a fost eroare
    }
  }


  Future<void> _discoverServices() async {
    if (_connectedDevice == null || !mounted) return;

    setState(() { _status = 'Se caută serviciul de printare...'; });

     try {
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
       if (!mounted) return; 
      BluetoothCharacteristic? targetCharacteristic;
      BluetoothCharacteristic? fallbackCharacteristic; // Pentru prima cu write din servicii non-standard

      // UUID-urile de interes
      const String serviceToFind = "000018f0-0000-1000-8000-00805f9b34fb"; // Serviciul Serial Port
      const String characteristicToFind = "00002af1-0000-1000-8000-00805f9b34fb"; // Caracteristica Serial Port
      const List<String> ignoredServices = ["1800", "1801"]; // Ignorăm Generic Access & Attribute

      print("--- Căutare Caracteristică Printare ---");
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toLowerCase();
        print("Serviciu: $serviceUuid");

        // Ignorăm serviciile standard comune care nu sunt de interes
        if (ignoredServices.contains(serviceUuid.split('-').first)) { // Comparăm doar prima parte pentru UUID-uri scurte
           print("  -> Ignorat (serviciu standard).");
           continue;
        }

        for (BluetoothCharacteristic characteristic in service.characteristics) {
          String charUuid = characteristic.uuid.toString().toLowerCase();
           print("  Caracteristica: $charUuid - Proprietati: ${characteristic.properties}");
          bool hasWrite = characteristic.properties.write || characteristic.properties.writeWithoutResponse;

          if (!hasWrite) {
             print("    -> Ignorat (nu are write).");
             continue; // Trecem la următoarea dacă nu are proprietăți de scriere
          }

          // Verificăm dacă este caracteristica specifică pe care o căutăm (2af1 în serviciul 18f0)
          if (serviceUuid == serviceToFind && charUuid == characteristicToFind) {
             targetCharacteristic = characteristic;
             print("!!! Caracteristica țintă GĂSITĂ: $charUuid în serviciul $serviceUuid");
             break; // Am găsit exact ce căutam, ieșim din loop-ul caracteristicilor
          }

          // Dacă nu am găsit încă ținta și suntem într-un serviciu non-standard,
          // salvăm prima caracteristică cu write ca fallback
          if (targetCharacteristic == null && fallbackCharacteristic == null) {
              fallbackCharacteristic = characteristic;
              print("    -> Salvat ca fallback temporar (prima cu write din serviciu non-standard).");
          }
        }

        // Dacă am găsit caracteristica țintă, ieșim și din loop-ul serviciilor
        if (targetCharacteristic != null) {
           break;
        }
      }
       print("-------------------------------------");

      // Selectăm caracteristica finală: ținta dacă a fost găsită, altfel fallback-ul
      final BluetoothCharacteristic? finalCharacteristic = targetCharacteristic ?? fallbackCharacteristic;

      if (!mounted) return;

      if (finalCharacteristic != null) {
         print("Caracteristica de scriere finală selectată: ${finalCharacteristic.uuid}");
         setState(() {
            _writeCharacteristic = finalCharacteristic;
            _status = 'Imprimantă pregătită';
         });
      } else {
         print("EROARE: Nicio caracteristică de scriere potrivită nu a fost găsită!");
         _showSnackbar("Eroare: Nu s-a găsit caracteristica de scriere pe imprimantă.");
         setState(() { _status = 'Eroare: Caracteristică scriere lipsă'; });
      }
     } catch (e) {
       if (!mounted) return;
       print("Eroare la descoperirea serviciilor: $e");
       _showSnackbar("Eroare la descoperirea serviciilor: $e");
       setState(() { _status = 'Eroare descoperire servicii'; });
     }
  }

  Future<void> _disconnectDevice() async {
    await _connectionSubscription?.cancel(); // Oprim ascultarea stării înainte
    final deviceToDisconnect = _connectedDevice; // Copie locală
    if (deviceToDisconnect != null) {
       // Setăm starea UI imediat pentru feedback rapid
        if(mounted) {
            setState(() {
                _status = 'Deconectare...';
                _connectedDevice = null; // Ștergem referința
                _writeCharacteristic = null;
            });
        }
       try {
           print("Încercare deconectare de la: ${deviceToDisconnect.remoteId}");
           await deviceToDisconnect.disconnect();
           print("Deconectare reușită (comandă trimisă)");
       } catch (e) {
           print("Eroare la trimiterea comenzii de deconectare: $e");
           // Chiar dacă a apărut o eroare la comandă, UI-ul e deja setat ca deconectat
       }
    }
     // Asigurăm starea finală în UI, chiar dacă nu era nimic de deconectat
     if(mounted && _connectionState != BluetoothConnectionState.disconnected) {
        setState(() {
            _connectionState = BluetoothConnectionState.disconnected;
            _connectedDevice = null;
            _writeCharacteristic = null;
            _status = 'Deconectat';
        });
     }
  }


 Future<void> _printLabel() async {
    // << ADAUGAT: Verificăm dacă deja printăm
    if (_isPrinting) {
       print("Ignorare comandă nouă: Printare deja în curs.");
       return;
    }

    final textToPrint = _textController.text;
    if (textToPrint.isEmpty) {
      _showSnackbar('EROARE: Textul nu poate fi gol!');
      return;
    }
    if (_connectionState != BluetoothConnectionState.connected || _writeCharacteristic == null) {
       _showSnackbar('EROARE: Imprimanta nu este conectată sau pregătită.');
       return;
    }

    // << ADAUGAT: Marcăm începutul printării
    setState(() {
       _isPrinting = true;
       _status = 'Pregătire printare...';
    });

    try {
      // 1. Generează imaginea QR folosind widget-ul ascuns
      final qrImageData = await _captureQrCode(); // Nu mai trimitem textul, îl ia din controller
      if (qrImageData == null || !mounted) {
         _showSnackbar('EROARE: Nu s-a putut genera imaginea QR.');
         if(mounted) setState(() { _status = 'Eroare generare QR'; });
         return;
      }

       // 2. Converteste imaginea pentru ESC/POS
      final img.Image? qrImageDecoded = img.decodeImage(qrImageData);
      if (qrImageDecoded == null || !mounted) {
        _showSnackbar('EROARE: Nu s-a putut decoda imaginea QR.');
         if(mounted) setState(() { _status = 'Eroare decodare QR'; });
        return;
      }

      // --- ADAUGAT: Redimensionăm imaginea înainte --- 
      const int desiredQrWidth = 200; // Lățimea dorită în puncte (pixeli)
      final img.Image qrImageResized = img.copyResize(
           qrImageDecoded,
           width: desiredQrWidth,
           interpolation: img.Interpolation.average, // Sau .nearest dacă vrei pixeli clari
      );
      // --- SFARSIT ADAUGARE ---

      // 3. Generează comenzile ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      bytes += generator.setStyles(PosStyles(align: PosAlign.center));

      // Printează QR Code redimensionat
      print("Printare imagine QR redimensionată la lățime $desiredQrWidth...");
      // Eliminăm 'width' de aici, folosim imaginea deja redimensionată
      bytes += generator.image(qrImageResized, align: PosAlign.center);
      bytes += generator.feed(1); // Spațiu

      // Printează Textul
      print("Printare text: $textToPrint");
      bytes += generator.text(textToPrint, styles: PosStyles(align: PosAlign.center, height: PosTextSize.size1));
      bytes += generator.feed(2); // Spațiu final

      // Comanda Cut - decomentează dacă știi că imprimanta o suportă
      // bytes += generator.cut();

      if (!mounted) return;
      setState(() { _status = 'Se trimite la imprimantă...'; });

      // 4. Trimite comenzile prin Bluetooth în bucăți (chunking)
      // Determinăm metoda de scriere (cu sau fără răspuns)
      bool withoutResponse = _writeCharacteristic!.properties.writeWithoutResponse;
      int chunkSize = 100; // Începem cu o valoare conservatoare
      // TODO: Putem încerca să negociem MTU și să ajustăm chunkSize
      // try {
      //   int mtu = await _connectedDevice!.mtu.first; // Necesită ascultare stream
      //   chunkSize = mtu - 3; // Ajustăm pentru header-ul BLE
      // } catch (e) { print("Nu s-a putut obține MTU, folosim $chunkSize"); }

      print("Trimitere ${bytes.length} bytes în bucăți de $chunkSize (withoutResponse: $withoutResponse)...");

      for (int i = 0; i < bytes.length; i += chunkSize) {
        // Verificăm dacă mai suntem montați înainte de fiecare scriere
        if (!mounted || !_isPrinting) { // Verificăm și dacă _isPrinting nu a devenit false între timp (ex. eroare)
             print("Printare anulată în timpul trimiterii.");
             return; 
        }
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);
        try {
            await _writeCharacteristic!.write(chunk, withoutResponse: withoutResponse);
             print("Trimis chunk: ${chunk.length} bytes");
             // Pauză mică între scrieri, mai ales dacă e withoutResponse
             await Future.delayed(const Duration(milliseconds: 30));
        } catch (e) {
            print("Eroare la scrierea chunk-ului: $e");
             if (!mounted) return;
             _showSnackbar('Eroare la trimiterea datelor: $e');
             // Nu mai setăm status aici, se face în finally
             return; // Oprim printarea dacă un chunk eșuează
        }
      }

      // Dacă am ajuns aici, printarea s-a terminat (comenzile au fost trimise)
      if (!mounted) return;
      _showSnackbar('Printare finalizată cu succes!');
      // Statusul va fi resetat în finally

    } catch (e) {
       if (!mounted) return;
       print("Eroare în funcția _printLabel: $e");
       _showSnackbar('EROARE la printare: $e');
       // Statusul va fi setat în finally
    } finally {
       // << ADAUGAT: Blocul finally pentru a reseta starea indiferent de rezultat
       if (mounted) {
          setState(() {
             _isPrinting = false;
             // Resetăm statusul doar dacă nu a rămas o eroare specifică de la catch
             // Verificăm dacă statusul curent indică o eroare produsă în try-catch
             if (!_status.contains('Eroare')) {
                 // Dacă nu suntem conectați între timp, schimbăm statusul corespunzător
                 if (_connectionState == BluetoothConnectionState.connected && _writeCharacteristic != null) {
                    _status = 'Imprimantă pregătită';
                 } else {
                    _status = 'Deconectat'; // Sau starea reală a conexiunii
                 }
             } // Altfel, lăsăm mesajul de eroare setat în catch
          });
       }
    }
  }

  // Funcție pentru capturarea widget-ului QrImageView ascuns
  Future<Uint8List?> _captureQrCode() async {
     try {
        // Găsim obiectul de randare asociat cu GlobalKey
        final RenderRepaintBoundary? boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
           print("Eroare captură QR: RenderRepaintBoundary nu a fost găsit. Widget-ul este montat?");
           return null;
        }

        // Așteptăm ca posibilele actualizări de stare să fie procesate
        await Future.delayed(Duration(milliseconds: 50));

        // Verificăm din nou după delay
        if (!mounted || boundary.debugNeedsPaint) {
           print("Așteptare randare boundary...");
           // S-ar putea să fie nevoie de o strategie mai robustă aici dacă widget-ul nu e randat
           await Future.delayed(Duration(milliseconds: 100));
            if (!mounted || boundary.debugNeedsPaint) {
                 print("Eroare captură QR: Boundary încă necesită paint.");
                 return null;
            }
        }


        // Creăm imaginea din boundary
        // PixelRatio mai mare pentru calitate mai bună la scalare în generator.image
        final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose(); // Important: Eliberează memoria nativă a imaginii

        if (byteData != null) {
           return byteData.buffer.asUint8List();
        } else {
            print("Eroare captură QR: byteData este null.");
            return null;
        }
     } catch (e) {
        print("Excepție la capturarea QR: $e");
        return null;
     }
  }

 // Funcție ajutătoare pentru afișare Snackbar
 void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Șterge snackbar-ul anterior
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
 }

  @override
  Widget build(BuildContext context) {
    // Folosim un Stack pentru a putea plasa widget-ul QR în afara zonei vizibile
    // dar totuși montat în arborele de widget-uri pentru a putea fi capturat.
    return Scaffold(
       appBar: AppBar(
          title: const Text('Printare Etichete SK58'),
           actions: [
              if (_isScanning)
                 const Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                 ),
              if (_connectionState == BluetoothConnectionState.connected)
                 IconButton(
                    icon: const Icon(Icons.bluetooth_disabled),
                    tooltip: 'Deconectare',
                    onPressed: _disconnectDevice, // Folosim funcția de deconectare
                 ),
           ],
       ),
       bottomNavigationBar: SafeArea(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: ElevatedButton(
             onPressed: _connectionState == BluetoothConnectionState.connected && _writeCharacteristic != null && !_isPrinting
                 ? _printLabel
                 : null,
             child: Text(_isPrinting ? 'Printare în curs...' : 'Printează Eticheta'),
             style: ElevatedButton.styleFrom(
               backgroundColor: _isPrinting ? Colors.orange : Colors.redAccent,
               foregroundColor: Colors.white,
               disabledBackgroundColor: Colors.grey,
               padding: const EdgeInsets.symmetric(vertical: 15),
             ),
           ),
         ),
       ),
       body: Stack( // Stack pentru a suprapune QR-ul invizibil
         children: [
            // Partea vizibilă a interfeței
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                 crossAxisAlignment: CrossAxisAlignment.stretch,
                 children: <Widget>[
                    // ... Status, TextField, Buton Scanare, Lista Dispozitive ...
                     Text('Status: $_status'),
                     const SizedBox(height: 10),
                     TextField(
                        controller: _textController,
                        // Actualizează starea pentru a redesena QR-ul din Stack la fiecare modificare
                        onChanged: (value) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Text și Număr pentru QR/Etichetă',
                          border: OutlineInputBorder(),
                        ),
                     ),
                     const SizedBox(height: 20),
                     ElevatedButton(
                        onPressed: _isScanning || (_connectionState == BluetoothConnectionState.connecting) || _isPrinting ? null : _scanDevices,
                        child: Text(_isScanning ? 'Scanare în curs...' : 'Scanează Dispozitive Bluetooth'),
                     ),
                     const SizedBox(height: 10),
                     const Text('Dispozitive Găsite:', style: TextStyle(fontWeight: FontWeight.bold)),
                     Expanded(
                        child: _scanResults.isEmpty && !_isScanning
                           ? Center(child: Text(_status)) // Afișează statusul dacă lista e goală și nu scanăm
                           : ListView.builder(
                               itemCount: _scanResults.length,
                               itemBuilder: (context, index) {
                                 final result = _scanResults[index];
                                 bool isConnected = result.device.remoteId == _connectedDevice?.remoteId;
                                 bool isConnecting = result.device.remoteId == _selectedDevice?.remoteId && _connectionState == BluetoothConnectionState.connecting;
                                 return ListTile(
                                    enabled: !isConnecting, // Dezactivăm rândul în timpul conectării la el
                                    title: Text(result.device.platformName.isEmpty ? 'Nume necunoscut (${result.device.remoteId})' : result.device.platformName),
                                    subtitle: Text(result.device.remoteId.toString()),
                                    trailing: isConnecting
                                       ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                       : Icon(
                                           isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                                           color: isConnected ? Theme.of(context).primaryColor : null,
                                          ),
                                    onTap: isConnecting ? null : () => _connectDevice(result.device), // Nu permite click în timpul conectării
                                    selected: _selectedDevice == result.device && !isConnected, // Selectat doar dacă nu e deja conectat
                                    selectedTileColor: Colors.grey.withOpacity(0.2),
                                 );
                               },
                             ),
                     ),
                 ],
              ),
            ),

           // Widget-ul QR ascuns pentru captură. Este montat dar nu vizibil.
           Positioned(
              top: -5000, // Asigură că nu e vizibil
              left: 0,
              child: RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                     color: Colors.white, // Fundal alb OBLIGATORIU pentru qr_flutter -> imagine
                     // Folosim textul din controller sau un placeholder dacă e gol
                     child: QrImageView(
                        data: _textController.text.isNotEmpty ? _textController.text : "placeholder",
                        version: QrVersions.auto,
                        size: 300, // O dimensiune suficient de mare pentru calitate bună
                        gapless: false, // Lasă spațiu în jur, util pentru decodare imagine
                     ),
                  ),
              ),
           )
         ],
       ),
    );
  }
}

// Extensie pentru capitalizare (poate fi mutată într-un fișier utilitar)
extension StringExtension on String {
    String capitalize() {
      if (isEmpty) return "";
      return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
    }
} 