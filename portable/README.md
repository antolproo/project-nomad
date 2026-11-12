# Domáca pevnosť OFFLINE – automatické prepínanie modelu podľa RAM

Izolovaný prenosný štartovač pre externý SSD na Windows a macOS; nemení existujúce moduly Kiwix, máp ani knižnice. **Nekopíruje ani nesťahuje modely.** Potrebuje už prítomné GGUF a lokálny llama.cpp server na disku.

- **RAM do 16 GiB vrátane:** najmenší vhodný GGUF (profil `small`).
- **RAM nad 16 GiB:** najväčší vhodný GGUF (profil `large`).
- Výber prebieha automaticky pri **každom spustení**, aj keď sú na disku viac než dva GGUF (pomocné projektory a embeddingy sa preskočia).
- Presné modely možno nechať preddefinované v `config/ai-model-small.txt` a `config/ai-model-large.txt`; štandardne sa nič nenastavuje.
- Vybraný model, profil a adresa servera sa ukladajú do `config/ai-active-model.txt`, `config/ai-active-profile.txt`, `config/ai-endpoint.txt` a premenných prostredia pre spustenú aplikáciu.
- Backend je prístupný len na `127.0.0.1:8099` a pred otvorením používateľského rozhrania sa čaká na jeho pripravenosť.
- Ak existuje pôvodná aplikácia `apps/windows/START.exe` alebo `apps/macos/START.app`, štartovač ju otvorí; inak otvorí vstavané lokálne rozhranie llama.cpp.

Tento modul patrí do koreňa obsahu SSD (`data/ai`, `apps/windows`, `apps/macos`, `config`). Bez skutočných súborov pôvodnej aplikácie sa **nedá overiť**, či jej existujúca záložka AI číta nový endpoint. Testy overujú samotné prepínanie a logiku štartu, nie používateľov konkrétny disk. 

Testovací override `DP_TEST_RAM_GIB` je úmyselne povolený výhradne v režime `-SelectOnly` / `--select-only` a nemôže ovplyvniť reálny štart.
