# Instrucțiuni detaliate pentru SK58 Printer

## UUID-uri specifice și identificatori importanți

**Serviciul de printare SK58:**
- UUID serviciu: `000018f0-0000-1000-8000-00805f9b34fb` (mai pe scurt: `18f0`)
- UUID caracteristică pentru scriere: `00002af1-0000-1000-8000-00805f9b34fb` (mai pe scurt: `2af1`)

**Servicii generice Bluetooth de ignorat:**
- `1800` (Generic Access)
- `1801` (Generic Attribute)

## Algoritm pentru identificarea și conectarea la imprimantă

1. Scanează dispozitivele Bluetooth
2. Conectează-te la dispozitivul dorit (SK58)
3. Descoperă serviciile disponibile
4. Caută serviciul cu UUID `18f0`
5. Ignoră serviciile cu UUID-uri care încep cu `1800` sau `1801`
6. Caută caracteristica cu UUID `2af1` în cadrul serviciului `18f0`
7. Verifică că această caracteristică are proprietatea `write` sau `writeWithoutResponse`
8. Dacă nu e găsită caracteristica specifică, folosește ca și fallback prima caracteristică cu proprietatea `write` din orice alt serviciu

## Generarea și procesarea imaginii QR

**Metoda de generare a imaginii:**
1. Folosim un widget `QrImageView` ascuns (în afara ecranului), înfășurat într-un `RepaintBoundary` cu GlobalKey
2. Widget-ul este actualizat automat când se modifică textul
3. Folosim `RenderRepaintBoundary.toImage()` pentru a captura widget-ul ca imagine
4. Imaginea este convertită în bytes folosind formatul PNG pentru păstrarea calității

**Parametrii optimi pentru generarea QR:**
- **Widget QR ascuns:**
  - Container: fără dimensiuni fixe (se adaptează la QrImageView)
  - QrImageView size: 300px (dimensiunea în widget-ul ascuns)
  - Background: OBLIGATORIU alb (`Colors.white`)
  - Foreground: OBLIGATORIU negru (`Colors.black`)
  - gapless: `false` (cu gap pentru mai bună lizibilitate)

- **Captura imaginii:**
  - pixelRatio: 3.0 (pentru detalii fine, importante pentru imprimantă)
  - delay înainte de captură: 50-100ms (pentru a asigura randarea completă)
  - format: PNG (păstrează calitatea fără compresie)

**Procesarea imaginii pentru printare:**
- Redimensionare: 200px width (înălțimea se ajustează automat)
- Interpolare: `img.Interpolation.average` (cel mai bun raport calitate/viteză)
- Fără alte procesări (cum ar fi threshold, binarizare etc.) - lasă librăria ESC/POS să se ocupe

## Configurarea optimă pentru printare

**Ordinea printării (CRITICĂ):**
1. Reset imprimantă
2. Printează ÎNTÂI imaginea QR
3. Apoi printează textul
4. Feed la final

**Dimensiuni QR:**
- Captură QR: 300px (dimensiunea în widget-ul ascuns)
- Redimensionare pentru printare: 200px
- Mod interpolare recomandat: `Interpolation.average`

**Transmitere date:**
- Chunk size: 100 bytes
- Delay între pachete: 30ms
- Verifică dacă caracteristica suportă `writeWithoutResponse` și folosește metoda potrivită

**Timing și performanță:**
- Timp total estimat pentru generare imagine QR: ~150-200ms
- Timp total estimat pentru transmitere date: ~100-300ms pentru fiecare 100 bytes
- Reducerea dimensiunii QR la sub 200px scade calitatea dar crește viteza
- Mărirea dimensiunii QR peste 200px crește calitatea dar poate cauza probleme de printare

## Comenzi de evitat

- `cut()` - a cauzat feed excesiv și probleme de printare
- Comenzi RAW pentru imprimantă care nu sunt validate

## Structură cod optimă pentru printare

```dart
// 1. Generează imaginea QR cu mărime 300px
final qrImageData = await _captureQrCode();
final img.Image? qrImageDecoded = img.decodeImage(qrImageData);

// 2. Redimensionează pentru printare
const int desiredQrWidth = 200;
final img.Image qrImageResized = img.copyResize(
    qrImageDecoded,
    width: desiredQrWidth,
    interpolation: img.Interpolation.average,
);

// 3. Generează comenzile ESC/POS
final profile = await CapabilityProfile.load();
final generator = Generator(PaperSize.mm58, profile);
List<int> bytes = [];

// 4. Resetează imprimanta
bytes += generator.reset();
bytes += generator.setStyles(PosStyles(align: PosAlign.center));

// 5. ÎNTÂI imaginea QR, apoi text (ORDINEA E FOARTE IMPORTANTĂ!)
bytes += generator.image(qrImageResized, align: PosAlign.center);
bytes += generator.feed(1); // Spațiu între QR și text

// 6. Printează textul
bytes += generator.text(textToPrint, styles: PosStyles(align: PosAlign.center));
bytes += generator.feed(2); // Spațiu final, max 2 linii!

// 7. Transmite datele în bucăți
bool withoutResponse = caracteristica.suportăWriteWithoutResponse;
int chunkSize = 100;
for (int i = 0; i < bytes.length; i += chunkSize) {
    int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
    List<int> chunk = bytes.sublist(i, end);
    await writeToCharacteristic(chunk, withoutResponse);
    await Future.delayed(const Duration(milliseconds: 30));
}
```

## Implementarea widget-ului QR ascuns

```dart
// În metoda build() a widget-ului
@override
Widget build(BuildContext context) {
  return Stack(
    children: [
      // UI principal vizibil aici...
      
      // Widget-ul QR ascuns pentru captură
      Positioned(
        top: -5000, // Poziționare în afara ecranului
        left: 0,
        child: RepaintBoundary(
          key: _qrKey, // GlobalKey pentru capturare
          child: Container(
            color: Colors.white, // OBLIGATORIU fundal alb
            child: QrImageView(
              data: _textController.text.isNotEmpty ? _textController.text : "placeholder",
              version: QrVersions.auto,
              size: 300, // Dimensiune mare pentru calitate
              gapless: false, // Cu gap pentru lizibilitate
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
        ),
      ),
    ],
  );
}

// Metoda de captură a QR-ului
Future<Uint8List?> _captureQrCode() async {
  try {
    final RenderRepaintBoundary? boundary = 
        _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    
    // Așteaptă randarea completă
    await Future.delayed(Duration(milliseconds: 50));
    
    // Capturează cu pixelRatio mare pentru calitate
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose(); // Eliberează memoria
    
    return byteData?.buffer.asUint8List();
  } catch (e) {
    print("Eroare la captură QR: $e");
    return null;
  }
}
```

## Portare la alte librării (universal_ble)

Când implementezi cu universal_ble sau altă librărie, asigură-te că:

1. Respecți UUID-urile de serviciu și caracteristică de mai sus
2. Ignori serviciile standard listate ca fiind de ignorat
3. Menții aceeași ordine: ÎNTÂI imagine QR, apoi text
4. Folosești aceleași dimensiuni pentru QR (200px)
5. Implementezi transmiterea în bucăți cu delay-uri similare (30ms)
6. Nu incluzi comanda cut() sau alte comenzi care pot cauza probleme

## Observații comportament imprimantă

- Imprimanta intră uneori în mod de text în loc de mod grafic pentru QR, rezultând în afișare incorectă
- Feed excesiv apare dacă se folosesc anumite comenzi cum ar fi cut() sau feed prea mare
- Anumite comenzi RAW pot cauza comportament imprevizibil
- Imprimanta se comportă cel mai bine atunci când ordinea QR -> Text este respectată 

## Compatibilitate cu alte imprimante similare

**Hardcodarea UUID-urilor:**

Da, poți hardcoda UUID-urile serviciului și caracteristicii pentru imprimante similare. Aceste UUID-uri sunt standardizate pentru imprimantele din familia SK58/SK80:

```dart
// UUID-uri hardcodate pentru SK58 și imprimante similare
final String PRINTER_SERVICE_UUID = "000018f0-0000-1000-8000-00805f9b34fb";
final String PRINTER_CHARACTERISTIC_UUID = "00002af1-0000-1000-8000-00805f9b34fb";
```

**Compatibilitate între modele:**

- **SK58/SK80/SK100:** Aceleași UUID-uri pentru serviciu/caracteristică (18f0/2af1)
- **Alte imprimante termice Bluetooth:** Multe folosesc aceleași UUID-uri, fiind bazate pe același chip Bluetooth
- **Alte mărci:** Pot avea UUID-uri diferite, dar frecvent folosesc aceeași implementare standard

**Recomandare pentru aplicații care lucrează cu multiple modele:**

1. Hardcodează UUID-urile cunoscute pentru SK58
2. Păstrează algoritmul de fallback pentru a căuta prima caracteristică cu proprietatea write
3. Adaugă un sistem de override pentru a permite utilizatorului să configureze manual UUID-urile

**Exemplu de implementare robustă:**

```dart
// UUID-uri predefinite pentru modelele cunoscute
Map<String, Map<String, String>> knownPrinterUUIDs = {
  "SK58": {
    "service": "000018f0-0000-1000-8000-00805f9b34fb",
    "characteristic": "00002af1-0000-1000-8000-00805f9b34fb"
  },
  "SK80": {
    "service": "000018f0-0000-1000-8000-00805f9b34fb",
    "characteristic": "00002af1-0000-1000-8000-00805f9b34fb"
  },
  // Alte modele pot fi adăugate aici
};

// Funcție pentru obținerea UUID-urilor, cu fallback la valorile SK58
Map<String, String> getPrinterUUIDs(String? model) {
  return knownPrinterUUIDs[model] ?? knownPrinterUUIDs["SK58"]!;
}
``` 