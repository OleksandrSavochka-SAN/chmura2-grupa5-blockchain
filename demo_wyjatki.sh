#!/usr/bin/env bash
# =====================================================================
# demo_wyjatki.sh - DRUGA część pokazu: sytuacje wyjątkowe w sieci
# Hyperledger Fabric 2.5.16, 4 organizacje, chaincode basic.
#
# Można uruchomić PO ./demo_4org.sh (z tym samym numerem przesyłki)
# albo OSOBNO na świeżej sieci - wtedy skrypt sam zakłada przesyłkę:
#   ./demo_wyjatki.sh                  # PRZESYLKA-001
#   ./demo_wyjatki.sh PRZESYLKA-002    # gdy demo było z innym numerem
#
# Krok 1: reguły kontraktu - duplikat numeru i nieistniejąca przesyłka
#         -> odmowa przy podpisywaniu, nic nie trafia do bloku
# Krok 2: za mało podpisów (2 z 4) -> transakcja NIEWAŻNA
#         (ENDORSEMENT_POLICY_FAILURE), stan bez zmian
# Krok 3: większość, ale bez Org1 (Org2, Org3, Org4) -> VALID
# Krok 4: awaria węzła Org4 -> sieć działa dalej (3 z 4),
#         po powrocie Org4 sama dociąga brakujący blok
# Krok 5: losowanie, które firmy podpisują (1, 2, 3 lub 4) -> sieć
#         sama decyduje według polityki MAJORITY (można powtarzać)
#
# Jeśli skrypt zostanie przerwany (błąd, Ctrl+C), peer Org4 jest
# automatycznie uruchamiany z powrotem.
# Skrypt NIE wyświetla kluczy ani zawartości katalogu organizations/.
# =====================================================================

ID="${1:-PRZESYLKA-001}"
CHANNEL="mychannel"
CC="basic"
L=5   # liczba kroków

B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
naglowek() { echo; echo "${B}${C}=== $1 ===${N}"; }
opis()     { echo "${Y}$1${N}"; }
pauza()    { echo; read -rp "${B}[Enter] - dalej${N} "; }
blad()     { echo; echo "${R}${B}BŁĄD:${N} ${R}$1${N}"; exit 1; }

# --- bezpieczeństwo: Org4 zawsze wraca, nawet po przerwaniu --------------
ORG4_ZATRZYMANY=0
przywroc_org4() {
  if [ "$ORG4_ZATRZYMANY" -eq 1 ]; then
    docker start peer0.org4.example.com >/dev/null 2>&1
    ORG4_ZATRZYMANY=0
    echo "${Y}(peer0.org4 uruchomiony z powrotem)${N}"
  fi
}
trap przywroc_org4 EXIT
trap 'exit 130' INT

[ -d organizations ] && [ -f network.sh ] \
  || blad "uruchom skrypt w katalogu fabric-samples/test-network."

export PATH="${PWD}/../bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/../config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_CA="${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PORTY=(0 7051 9051 11051 13051)
ca_peera() { echo "${PWD}/organizations/peerOrganizations/org$1.example.com/peers/peer0.org$1.example.com/tls/ca.crt"; }

jako_org() {
  export CORE_PEER_LOCALMSPID="Org$1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$(ca_peera "$1")"
  export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/org$1.example.com/users/Admin@org$1.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:${PORTY[$1]}"
}

# invoke_przez "1 2" '{json}' - podpisują TYLKO podane organizacje;
# wysyła administrator pierwszej z nich. Wynik: OUT, RC, WYNIK (valid|odmowa)
invoke_przez() {
  local orgi="$1" json="$2" args=() lista="" pierwsza=""
  for o in $orgi; do
    [ -z "$pierwsza" ] && pierwsza="$o"
    args+=(--peerAddresses "localhost:${PORTY[$o]}" --tlsRootCertFiles "$(ca_peera "$o")")
    lista="${lista}Org$o "
  done
  jako_org "$pierwsza"
  echo "${C}\$ peer chaincode invoke ... (podpisy: ${lista% }) -c '$json'${N}"
  OUT=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --tls --cafile "$ORDERER_CA" -C "$CHANNEL" -n "$CC" "${args[@]}" \
    --waitForEvent -c "$json" 2>&1); RC=$?
  echo "$OUT" | grep -E "committed with status|invoke successful|Error" | head -n 4
  if [ "$RC" -eq 0 ] && ! echo "$OUT" | grep -q "ENDORSEMENT_POLICY_FAILURE"; then
    WYNIK=valid
  else
    WYNIK=odmowa
  fi
}

odmowa_ok() {   # oczekujemy odmowy
  if [ "$WYNIK" = odmowa ]; then
    echo "${R}${B}ODMOWA:${N}${R} $1${N}"
  else
    echo "${Y}Uwaga: transakcja nieoczekiwanie przeszła.${N}"
  fi
}

valid_ok() {    # oczekujemy sukcesu
  [ "$WYNIK" = valid ] || blad "transakcja nie przeszła, a powinna."
  echo "${G}OK: $1${N}"
}

odczyt() {
  jako_org "$1"
  echo "${C}\$ peer chaincode query (peer0.org$1) ReadAsset $ID | jq -c${N}"
  timeout 20 peer chaincode query -C "$CHANNEL" -n "$CC" -c "{\"Args\":[\"ReadAsset\",\"$ID\"]}" | jq -c \
    || blad "odczyt z peer0.org$1 się nie powiódł."
}

aktualizacja() {   # JSON UpdateAsset z nowym statusem
  echo "{\"function\":\"UpdateAsset\",\"Args\":[\"$ID\",\"$1\",\"12\",\"FirmaB\",\"500\"]}"
}

# --- sprawdzenie środowiska ---------------------------------------------
command -v peer >/dev/null || blad "brak programu peer (sprawdź ../bin)."
command -v jq   >/dev/null || blad "brak programu jq."
command -v shuf >/dev/null || blad "brak programu shuf (coreutils)."
for c in orderer.example.com peer0.org1.example.com peer0.org2.example.com peer0.org3.example.com peer0.org4.example.com; do
  docker ps --format '{{.Names}}' | grep -q "^$c$" || blad "nie działa $c - sieć nie jest kompletna."
done
jako_org 1
peer lifecycle chaincode querycommitted -C "$CHANNEL" -n "$CC" >/dev/null 2>&1 \
  || blad "chaincode '$CC' nie jest wdrożony. Najpierw postaw sieć (instrukcja, sekcje 6 i 8)."
ISTNIEJE=0
peer chaincode query -C "$CHANNEL" -n "$CC" -c "{\"Args\":[\"AssetExists\",\"$ID\"]}" 2>/dev/null | grep -q true \
  && ISTNIEJE=1

clear
echo "${B}Część 2: sytuacje wyjątkowe - przesyłka $ID${N}"
echo "Co się dzieje, gdy ktoś łamie reguły, firmy się nie zgadzają albo węzeł ulega awarii?"

# --- przesyłka: z demo_4org.sh albo zakładana tutaj -----------------------
if [ "$ISTNIEJE" -eq 0 ]; then
  echo
  opis "Przesyłki $ID nie ma jeszcze w księdze - zakładamy ją (stan jak po demo_4org.sh: w_transporcie, FirmaB)."
  invoke_przez "1 2 3" "{\"function\":\"CreateAsset\",\"Args\":[\"$ID\",\"w_transporcie\",\"12\",\"FirmaB\",\"500\"]}"
  valid_ok "przesyłka założona (podpisy 3 z 4)."
fi
echo
opis "Stan na start (odczyt z Org1):"
odczyt 1
pauza

# --- 1. reguły kontraktu -------------------------------------------------
naglowek "Krok 1/$L: Reguły kontraktu - błędne zdarzenia"
opis "a) Ktoś próbuje nadać przesyłkę o numerze, który już istnieje:"
invoke_przez "1 2 3" "{\"function\":\"CreateAsset\",\"Args\":[\"$ID\",\"nadana\",\"99\",\"FirmaX\",\"1\"]}"
odmowa_ok "kontrakt odrzucił duplikat - nic nie zapisano."
echo
opis "b) Ktoś zgłasza zmianę statusu przesyłki, której nie ma w księdze:"
invoke_przez "1 2 3" "{\"function\":\"UpdateAsset\",\"Args\":[\"PRZESYLKA-NIEZNANA\",\"dostarczona\",\"1\",\"FirmaX\",\"1\"]}"
odmowa_ok "kontrakt odrzucił zdarzenie dla nieznanej przesyłki."
pauza

# --- 2. za mało podpisów -------------------------------------------------
naglowek "Krok 2/$L: Tylko 2 z 4 firm podpisują zmianę"
opis "Org3 i Org4 nie podpisują (nie zgadzają się). Polityka MAJORITY wymaga 3 z 4."
invoke_przez "1 2" "$(aktualizacja odprawiona_celnie)"
odmowa_ok "transakcja w bloku, ale oznaczona jako NIEWAŻNA - stan się nie zmienił."
echo
opis "Stan u Org1 i Org4 - bez zmian:"
odczyt 1
odczyt 4
pauza

# --- 3. większość bez Org1 -----------------------------------------------
naglowek "Krok 3/$L: Ta sama zmiana - podpisują Org2, Org3 i Org4"
opis "Liczy się większość, a nie konkretna firma - Org1 tym razem nie podpisuje."
invoke_przez "2 3 4" "$(aktualizacja odprawiona_celnie)"
valid_ok "3 z 4 podpisów - transakcja ważna (VALID)."
odczyt 1
pauza

# --- 4. awaria węzła -----------------------------------------------------
naglowek "Krok 4/$L: Awaria węzła Org4"
opis "Zatrzymujemy peer0.org4 (symulacja awarii serwera jednej firmy)."
docker stop -t 5 peer0.org4.example.com >/dev/null || blad "nie udało się zatrzymać peer0.org4."
ORG4_ZATRZYMANY=1
docker ps -a --filter "name=^peer0.org4.example.com$" --format 'table {{.Names}}\t{{.Status}}'
echo
opis "Pozostałe 3 firmy dalej pracują - zmiana statusu z podpisami Org1, Org2, Org3:"
invoke_przez "1 2 3" "$(aktualizacja w_doreczeniu)"
valid_ok "sieć działa mimo awarii jednej firmy."
odczyt 1
pauza
opis "Org4 wraca do pracy - jej węzeł sam pobiera brakujące bloki."
docker start peer0.org4.example.com >/dev/null || blad "nie udało się uruchomić peer0.org4."
ORG4_ZATRZYMANY=0
jako_org 4
echo -n "Czekamy, aż Org4 nadrobi zaległości "
for i in $(seq 1 20); do
  peer chaincode query -C "$CHANNEL" -n "$CC" -c "{\"Args\":[\"ReadAsset\",\"$ID\"]}" 2>/dev/null \
    | grep -q w_doreczeniu && break
  echo -n "."; sleep 3
done
echo
odczyt 4
echo "${G}Org4 po powrocie ma aktualny stan - nic nie zginęło.${N}"
pauza

# --- 5. losowanie ---------------------------------------------------------
naglowek "Krok 5/$L: Losujemy, które firmy podpiszą zmianę"
opis "Skrypt losuje 1, 2, 3 lub 4 firmy. O wyniku decyduje sieć, nie skrypt: 3 lub więcej = VALID, mniej = odmowa."
while true; do
  ILE=$(( RANDOM % 4 + 1 ))
  ORGI=$(shuf -i 1-4 -n "$ILE" | sort -n | tr '\n' ' ')
  echo
  echo "${B}Wylosowano: podpisują$(for o in $ORGI; do echo -n " Org$o"; done) ($ILE z 4)${N}"
  if [ "$ILE" -ge 3 ]; then opis "Oczekiwany wynik według polityki: VALID"
  else opis "Oczekiwany wynik według polityki: ODMOWA"; fi
  invoke_przez "$ORGI" "$(aktualizacja dostarczona)"
  if [ "$WYNIK" = valid ]; then
    echo "${G}Wynik sieci: VALID - zmiana zapisana.${N}"
  else
    echo "${R}${B}Wynik sieci: ODMOWA${N}${R} - zmiana nie została zapisana.${N}"
  fi
  if { [ "$ILE" -ge 3 ] && [ "$WYNIK" = valid ]; } || { [ "$ILE" -lt 3 ] && [ "$WYNIK" = odmowa ]; }; then
    echo "${G}Zgodnie z polityką MAJORITY.${N}"
  else
    echo "${Y}Uwaga: wynik niezgodny z oczekiwanym.${N}"
  fi
  odczyt 3
  echo
  read -rp "${B}Losować jeszcze raz? [t/N]${N} " odp
  [[ "$odp" =~ ^[tT] ]] || break
done

echo
echo "${B}Koniec części 2.${N} Po prezentacji: ./network.sh down  oraz  docker volume rm compose_peer0.org4.example.com"
