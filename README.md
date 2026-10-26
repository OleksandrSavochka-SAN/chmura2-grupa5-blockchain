# Pokaz: sieć Hyperledger Fabric w chmurze Azure

Wybrane technologie chmurowe, Zadanie 5: Blockchain w chmurze, część D (pokaz na żywo).

Sieć permissioned Hyperledger Fabric dla konsorcjum czterech firm logistycznych:
organizacje Org1–Org4 (każda z własnym peerem i kopią księgi), orderer (Raft),
kanał `mychannel` i smart kontrakt `asset-transfer-basic` (Go). Pokaz: zapis,
przekazanie i zmiana statusu przesyłki oraz odczyt tego samego stanu z węzłów
pozostałych organizacji. Opcjonalnie: sytuacje wyjątkowe (odrzucenie transakcji,
awaria węzła). Tylko sieć testowa, bez kryptowalut i bez danych osobowych.

## Pliki

| Plik | Opis |
|---|---|
| `demo_4org.sh` | skrypt pokazu na żywo (6 kroków z pauzą po każdym) |
| `demo_wyjatki.sh` | opcjonalna część 2 pokazu: sytuacje wyjątkowe (odrzucenie transakcji, awaria węzła, losowy dobór podpisujących firm) |
| `Instrukcja_Hyperledger_Fabric_Azure.pdf` | instrukcja laboratoryjna krok po kroku |

## Środowisko

- Azure for Students, VM Standard_B2s_v2 (2 vCPU, 8 GiB RAM), Ubuntu Server 24.04 LTS
- Hyperledger Fabric 2.5.16, Fabric CA 1.5.17, `fabric-samples/test-network`
- Polityka endorsementu MAJORITY: podpisy 3 z 4 organizacji

## Uruchomienie

1. Przygotowanie VM i sieci z 4 organizacjami: sekcje 2–8 instrukcji.
2. Skopiowanie skryptów do `~/fabric/fabric-samples/test-network` i przygotowanie:

```bash
sed -i 's/\r$//' demo_4org.sh demo_wyjatki.sh
chmod +x demo_4org.sh demo_wyjatki.sh
```

### Część 1: zapis i odczyt transakcji

```bash
./demo_4org.sh                  # domyślnie PRZESYLKA-001
./demo_4org.sh PRZESYLKA-002    # gdy przesyłka 001 już istnieje
```

Kroki: sieć (4 peery i orderer), zatwierdzony smart kontrakt, nadanie przesyłki
(zapis i odczyt), przekazanie przewoźnikowi FirmaB, zmiana statusu na
`w_transporcie`, odczyt tego samego stanu z węzłów Org2, Org3 i Org4.

### Część 2 (opcjonalna): sytuacje wyjątkowe

```bash
./demo_wyjatki.sh                 # PRZESYLKA-001
./demo_wyjatki.sh PRZESYLKA-002   # inny numer przesyłki
```

Uruchamiany po `demo_4org.sh` z tym samym numerem przesyłki albo osobno na
świeżej sieci (wtedy sam zakłada przesyłkę). Kroki:

1. Reguły kontraktu: duplikat numeru i zmiana nieistniejącej przesyłki są odrzucane.
2. Podpisy tylko 2 z 4 firm: transakcja nieważna (`ENDORSEMENT_POLICY_FAILURE`), stan bez zmian.
3. Podpisy Org2, Org3 i Org4: transakcja ważna, liczy się większość, a nie konkretna firma.
4. Awaria węzła Org4: pozostałe 3 firmy pracują dalej, po powrocie Org4 dociąga brakujące bloki.
5. Losowanie 1–4 podpisujących firm: sieć sama decyduje według polityki MAJORITY (3 z 4).

Jeśli skrypt zostanie przerwany w kroku 4, sam uruchamia peer Org4 z powrotem.

### Po pracy

Sprzątanie sieci i zatrzymanie VM (sekcja 10 instrukcji):

```bash
./network.sh down
docker volume rm compose_peer0.org4.example.com
docker container prune -f
docker volume prune -f
```

Następnie w portalu Azure: VM → Zatrzymaj (stan „Zatrzymana (bez alokacji)”).

## Bezpieczeństwo

W repozytorium nie ma kluczy SSH, katalogu `organizations/` (klucze prywatne
organizacji), adresów IP ani identyfikatorów subskrypcji. Skrypty zawierają tylko
ścieżki do certyfikatów i nie wypisują kluczy. Dostęp SSH do VM jest ograniczony
regułą sieciową do jednego adresu IP.
