# Pokaz: sieć Hyperledger Fabric w chmurze Azure

Wybrane technologie chmurowe, Zadanie 5: Blockchain w chmurze, część D (pokaz na żywo).

Sieć permissioned Hyperledger Fabric dla konsorcjum czterech firm logistycznych:
organizacje Org1–Org4 (każda z własnym peerem i kopią księgi), orderer (Raft),
kanał `mychannel` i smart kontrakt `asset-transfer-basic` (Go). Pokaz: zapis,
przekazanie i zmiana statusu przesyłki oraz odczyt tego samego stanu z węzłów
pozostałych organizacji. Tylko sieć testowa, bez kryptowalut i bez danych osobowych.

## Pliki

| Plik | Opis |
|---|---|
| `demo_4org.sh` | skrypt pokazu na żywo (6 kroków z pauzą po każdym) |
| `Instrukcja_Hyperledger_Fabric_Azure.pdf` | instrukcja laboratoryjna krok po kroku |

## Środowisko

- Azure for Students, VM Standard_B2s_v2 (2 vCPU, 8 GiB RAM), Ubuntu Server 24.04 LTS
- Hyperledger Fabric 2.5.16, Fabric CA 1.5.17, `fabric-samples/test-network`
- Polityka endorsementu MAJORITY: podpisy 3 z 4 organizacji

## Uruchomienie

1. Przygotowanie VM i sieci z 4 organizacjami: sekcje 2–8 instrukcji.
2. Skopiowanie skryptu do `~/fabric/fabric-samples/test-network` i uruchomienie:

```bash
sed -i 's/\r$//' demo_4org.sh
chmod +x demo_4org.sh
./demo_4org.sh                  # domyślnie PRZESYLKA-001
./demo_4org.sh PRZESYLKA-002    # gdy przesyłka 001 już istnieje
```

3. Po pracy: sprzątanie sieci i zatrzymanie VM (sekcja 10 instrukcji).

## Bezpieczeństwo

W repozytorium nie ma kluczy SSH, katalogu `organizations/` (klucze prywatne
organizacji), adresów IP ani identyfikatorów subskrypcji. Dostęp SSH do VM
jest ograniczony regułą sieciową do jednego adresu IP.
