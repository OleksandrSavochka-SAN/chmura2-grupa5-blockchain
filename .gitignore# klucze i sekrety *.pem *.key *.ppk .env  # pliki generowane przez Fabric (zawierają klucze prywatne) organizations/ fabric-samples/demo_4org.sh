#!/usr/bin/env bash
# =====================================================================
# demo_4org.sh - pokaz na żywo: Hyperledger Fabric, sieć z 4 organizacjami
# (konsorcjum logistyczne: zapis, odczyt, przekazanie, zmiana statusu,
# odczyt z Org2, Org3 i Org4).
#
# Wersje: Hyperledger Fabric 2.5.16, Fabric CA 1.5.17
# fabric-samples: https://github.com/hyperledger/fabric-samples
#
# Wymaga sieci z 4 organizacjami i wdrożonego chaincode'u (PRZED pokazem,
# według instrukcji laboratoryjnej):
#   ./network.sh down
#   ./network.sh up createChannel
#   ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go
#   dodanie Org3 i Org4 (addOrg3, addOrg4) oraz instalacja chaincode'u na ich peerach
#
# Użycie (w katalogu fabric-samples/test-network):
#   ./demo_4org.sh                       # przesyłka PRZESYLKA-001
#   ./demo_4org.sh PRZESYLKA-002         # inny numer, gdy 001 już istnieje
#
# Polityka endorsementu: większość organizacji (3 z 4). Skrypt zbiera
# podpisy od Org1, Org2 i Org3.
# Skrypt NIE wyświetla kluczy ani zawartości katalogu organizations/.
# =====================================================================

ID="${1:-PRZESYLKA-001}"
CHANNEL="mychannel"
CC="basic"
LICZBA_KROKOW=6

# --- kolory i pomocnicze funkcje ---------------------------------------
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
naglowek() { echo; echo "${B}${C}=== $1 ===${N}"; }
opis()     { echo "${Y}$1${N}"; }
pauza()    { echo; read -rp "${B}[Enter] - dalej${N} "; }
blad()     { echo; echo "${R}${B}BŁĄD:${N} ${R}$1${N}"; exit 1; }

# --- sprawdzenie środowiska ---------------------------------------------
[ -d organizations ] && [ -f network.sh ] \
  || blad "uruchom skrypt w katalogu fabric-samples/test-network (oraz po ./network.sh up)."

# --- zmienne środowiskowe ----------------------------------------------
export PATH="${PWD}/../bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/../config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_CA="${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PORTY=(0 7051 9051 11051 13051)   # port peera: Org1..Org4
ca_peera() { echo "${PWD}/organizations/peerOrganizations/org$1.example.com/peers/peer0.org$1.example.com/tls/ca.crt"; }

jako_org() {   # ustawia środowisko administratora organizacji $1
  export CORE_PEER_LOCALMSPID="Org$1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$(ca_peera "$1")"
  export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/org$1.example.com/users/Admin@org$1.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:${PORTY[$1]}"
}

# invoke: zmienia stan księgi; podpisy od peerów Org1, Org2 i Org3 (3 z 4),
# potem orderer; --waitForEvent czeka, aż blok zostanie zapisany.
# Na ekranie: linie "committed with status (VALID)" z każdego z 3 peerów.
invoke() {
  echo "${C}\$ peer chaincode invoke ... (podpisy: Org1, Org2, Org3) -c '$1'${N}"
  local out rc
  out=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --tls --cafile "$ORDERER_CA" -C "$CHANNEL" -n "$CC" \
    --peerAddresses localhost:7051  --tlsRootCertFiles "$(ca_peera 1)" \
    --peerAddresses localhost:9051  --tlsRootCertFiles "$(ca_peera 2)" \
    --peerAddresses localhost:11051 --tlsRootCertFiles "$(ca_peera 3)" \
    --waitForEvent -c "$1" 2>&1); rc=$?
  echo "$out" | grep -E "VALID|invoke successful|Error|error"
  [ "$rc" -eq 0 ] || blad "transakcja się nie powiodła (sprawdź, czy sieć działa: docker ps)."
  echo "${G}OK: transakcja podpisana przez 3 z 4 organizacji i zapisana w bloku.${N}"
}

odczyt() {   # query: tylko odczyt, z peera ustawionego w CORE_PEER_ADDRESS
  echo "${C}\$ peer chaincode query -C $CHANNEL -n $CC -c '{\"Args\":[\"ReadAsset\",\"$ID\"]}' | jq${N}"
  peer chaincode query -C "$CHANNEL" -n "$CC" -c "{\"Args\":[\"ReadAsset\",\"$ID\"]}" | jq \
    || blad "odczyt się nie powiódł."
}

command -v peer >/dev/null || blad "brak programu peer (sprawdź ../bin)."
command -v jq   >/dev/null || blad "brak programu jq (sudo apt install -y jq)."

for c in orderer.example.com peer0.org1.example.com peer0.org2.example.com peer0.org3.example.com peer0.org4.example.com; do
  docker ps --format '{{.Names}}' | grep -q "^$c$" \
    || blad "nie działa $c. Postaw sieć według instrukcji (sieć 2 org., deployCC, addOrg3, addOrg4, chaincode na Org3/Org4)."
done
jako_org 1
peer lifecycle chaincode querycommitted -C "$CHANNEL" -n "$CC" >/dev/null 2>&1 \
  || blad "chaincode '$CC' nie jest wdrożony. Uruchom ./network.sh deployCC."
if peer chaincode query -C "$CHANNEL" -n "$CC" -c "{\"Args\":[\"AssetExists\",\"$ID\"]}" 2>/dev/null | grep -q true; then
  blad "przesyłka $ID już istnieje w księdze. Uruchom np.: ./demo_4org.sh PRZESYLKA-002"
fi

clear
echo "${B}Pokaz: Hyperledger Fabric 2.5.16 - przesyłka $ID, konsorcjum 4 firm${N}"
echo "Kanał: $CHANNEL, chaincode: $CC (asset-transfer-basic, Go)"
pauza

# --- 1. sieć ------------------------------------------------------------
naglowek "Krok 1/$LICZBA_KROKOW: Sieć - 4 organizacje, każda z własnym węzłem, i orderer"
opis "Każda firma ma własny peer i własną kopię księgi; orderer ustala kolejność transakcji."
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "NAMES|peer0|orderer"
pauza

# --- 2. chaincode -------------------------------------------------------
naglowek "Krok 2/$LICZBA_KROKOW: Smart kontrakt zatwierdzony przez organizacje"
opis "Chaincode działa na kanale, gdy zatwierdzi go większość organizacji. Sprawdzamy, które to zrobiły (Approvals)."
peer lifecycle chaincode querycommitted -C "$CHANNEL" -n "$CC"
pauza

# --- 3. zapis + odczyt --------------------------------------------------
naglowek "Krok 3/$LICZBA_KROKOW: FirmaA nadaje przesyłkę (zapis + odczyt)"
opis "Pola: Color = status, Size = waga (kg), Owner = firma, AppraisedValue = wartość. Bez danych osobowych."
invoke "{\"function\":\"CreateAsset\",\"Args\":[\"$ID\",\"nadana\",\"12\",\"FirmaA\",\"500\"]}"
echo
odczyt
pauza

# --- 4. przekazanie -----------------------------------------------------
naglowek "Krok 4/$LICZBA_KROKOW: Przekazanie przesyłki przewoźnikowi FirmaB"
opis "Nowa transakcja w łańcuchu - poprzedni stan zostaje w historii."
invoke "{\"function\":\"TransferAsset\",\"Args\":[\"$ID\",\"FirmaB\"]}"
pauza

# --- 5. zmiana statusu + odczyt ----------------------------------------
naglowek "Krok 5/$LICZBA_KROKOW: FirmaB zmienia status na 'w_transporcie'"
invoke "{\"function\":\"UpdateAsset\",\"Args\":[\"$ID\",\"w_transporcie\",\"12\",\"FirmaB\",\"500\"]}"
echo
odczyt
pauza

# --- 6. odczyt z pozostałych organizacji -------------------------------
naglowek "Krok 6/$LICZBA_KROKOW: Ten sam odczyt z węzłów Org2, Org3 i Org4"
opis "Pytamy kolejno peery trzech pozostałych firm, każdy jako administrator swojej organizacji."
for o in 2 3 4; do
  jako_org "$o"
  echo; echo "${B}--- peer0.org$o (localhost:${PORTY[$o]}), ${CORE_PEER_LOCALMSPID} ---${N}"
  odczyt
done
echo "${G}Wynik identyczny w każdej organizacji: każda firma ma zgodną kopię księgi.${N}"

echo
echo "${B}Koniec pokazu.${N} Po prezentacji: ./network.sh down  oraz  docker ps -a"
