# Trio-branches en updates

Dit document beschrijft de actuele inrichting van de fork
`cornegabriels599/Trio`. Het is bedoeld voor beheerders en coaches. De
branchnaam bepaalt zowel de broncode als de Apple-appidentiteit; wissel die
identiteiten nooit tussen branches.

## Overzicht
```text
nightscout/Trio main ──> main                 ──> Trio Main
                    └──> upgrade/trio-1.0     ──> Trio (OSC/custom)
nightscout/Trio dev  ──> dev                  ──> Trio Dev

archive/main-pre-vanilla = alleen historische back-up
```

- `main` en `dev` volgen vanilla Nightscout Trio met alleen de kleine
  CI/flavor-overlay die nodig is om drie aparte apps te bouwen.
- `upgrade/trio-1.0` bevat de OpenSourceClinic-versie, eigen Libre- en
  Medtrum-aanpassingen en simulator-/trainingstooling.
- `archive/main-pre-vanilla` wordt niet bijgewerkt en nooit gebouwd.
- De huidige GitHub-defaultbranch is `main`. Alleen de workflowversie op de
  defaultbranch krijgt een GitHub-cronstart.

## Branches en appidentiteiten
In onderstaande identifiers betekent `TEAMID` de Apple Development Team ID.
De bron van deze mapping is
[`.github/app-flavors.yml`](../.github/app-flavors.yml). De workflow zet
`$(DEVELOPMENT_TEAM)` tijdens de build om naar de echte Team ID.

### `upgrade/trio-1.0` — OSC/custom

- Upstream: `nightscout/Trio` branch `main`.
- Updatestrategie: de eigen commits worden op de nieuwste upstream `main`
  gerebased.
- Inhoud: OpenSourceClinic, eigen Libre/Medtrum-functionaliteit en
  simulator-/trainingstooling.
- Appnaam op het toestel: **Trio**.
- Bundle ID: `org.nightscout.TEAMID.trio`.
- App Group: `group.org.nightscout.TEAMID.trio.trio-app-group`.
- URL scheme: `Trio`.
- App Store Connect/TestFlight: de bestaande app **Trio** met dit bestaande
  bundle ID. Maak hiervoor geen tweede ASC-app.

### `main` — vanilla stabiel

- Upstream: `nightscout/Trio` branch `main`.
- Updatestrategie: fast-forward; als de flavor-overlay dat blokkeert, een
  gewone merge. Nooit rebase/force-push.
- Appnaam op het toestel: **Trio Main**.
- Bundle ID: `org.nightscout.TEAMID.trio.main`.
- App Group: `group.org.nightscout.TEAMID.trio.main.trio-app-group`.
- URL scheme: `TrioMain`.
- App Store Connect/TestFlight: aparte app **Trio Main**, gekoppeld aan
  `…trio.main`.

### `dev` — vanilla ontwikkeling

- Upstream: `nightscout/Trio` branch `dev`.
- Updatestrategie: fast-forward; als de flavor-overlay dat blokkeert, een
  gewone merge. Nooit rebase/force-push.
- Appnaam op het toestel: **Trio Dev**.
- Bundle ID: `org.nightscout.TEAMID.trio.dev`.
- App Group: `group.org.nightscout.TEAMID.trio.dev.trio-app-group`.
- URL scheme: `TrioDev`.
- App Store Connect/TestFlight: aparte app **Trio Dev**, gekoppeld aan
  `…trio.dev`.

### `archive/main-pre-vanilla` — archief

- Upstream: geen; dit is een bevroren historische back-up.
- Appnaam, bundle ID, App Group en URL scheme: alleen historisch, niet als
  actieve identiteit beheren.
- App Store Connect/TestFlight: geen build of upload vanuit deze branch.
- Start hierop geen `4. Build Trio`, `2. Add Identifiers` of Sunday Sync.

## Automatische zondagupdate
De workflow heet **Sunday Sync All Tracks** en staat in
[`.github/workflows/sunday_sync_all_tracks.yml`](../.github/workflows/sunday_sync_all_tracks.yml).
De implementatie staat in
[`.github/scripts/sunday_sync_all_tracks.sh`](../.github/scripts/sunday_sync_all_tracks.sh).

De cron is `43 6 * * 0`: zondag om **06:43 UTC**. Nederlandse lokale tijd is
daardoor normaal **07:43 in wintertijd (CET)** en **08:43 in zomertijd
(CEST)**. GitHub-cron blijft UTC; de omschakeldatum kan dus de ervaren lokale
tijd veranderen.

Exacte volgorde:

1. De job valideert `GH_PAT`, checkt de defaultbranch uit met submodules en
   haalt `origin/main`, `origin/dev`, `origin/upgrade/trio-1.0` en upstream
   `main`/`dev` op.
2. Voor `main` vergelijkt het script of upstream `main` al een ancestor is.
   Zo ja: niets doen. Zo nee: fast-forward, of een gewone merge wanneer de
   lokale flavor-overlay een fast-forward verhindert.
3. Voor `dev` gebeurt hetzelfde tegen upstream `dev`.
4. Op beide vanilla branches wordt de benodigde CI/flavor-overlay zo nodig
   hersteld. De push is altijd normaal, nooit force.
5. Voor `upgrade/trio-1.0` controleert het script of upstream `main` al is
   opgenomen. Zo niet, dan initialiseert het eerst alle submodules en rebased
   het de custom commits op upstream `main`.
6. Alleen na een volledig schone rebase én controle op verplichte
   clinic-/overlaybestanden volgt
   `git push --force-with-lease`. De lease gebruikt de vooraf opgehaalde
   remote-SHA, zodat gelijktijdig nieuw werk niet wordt overschreven.
7. De workflow start **4. Build Trio** alleen voor tracks waarvan de branch
   werkelijk veranderde. Een track zonder nieuwe upstream-commits wordt niet
   gebouwd.

Bij conflicten:

- Een mislukte vanilla merge wordt afgebroken; die branch wordt niet gepusht
  of als bijgewerkt gebouwd. Niet-opgeloste bestanden staan in de joblog.
- Een mislukte custom rebase wordt afgebroken; `upgrade/trio-1.0` blijft
  remote ongewijzigd en krijgt geen custom build.
- Voor een custom conflict probeert de workflow een issue met titel
  `Sunday rebase failed: upgrade/trio-1.0 onto nightscout/Trio main` te maken
  of bij te werken.
- Zijn GitHub Issues uitgeschakeld, dan verschijnt alleen een workflowwarning
  plus de conflictlijst in log en job summary. De update wordt ook dan niet
  geforceerd.
- Reeds succesvol gewijzigde andere tracks kunnen nog wel hun eigen build
  krijgen; een fout op één track maakt hun push niet ongedaan.

## Workflows handmatig starten
### Sunday Sync All Tracks

1. Open GitHub **Actions → Sunday Sync All Tracks**.
2. Kies bij voorkeur `main` (de defaultbranch) en **Run workflow**.
3. Deze ene run controleert en verwerkt alle drie actieve tracks.
4. Controleer de job summary en eventuele warnings/conflicten.

Een handmatige dispatch gebruikt de workflowfile van de geselecteerde branch.
Houd daarom
`.github/workflows/sunday_sync_all_tracks.yml` en het bijbehorende script
gelijk op `main`, `dev` en `upgrade/trio-1.0`.

### 4. Build Trio

Workflow:
[`.github/workflows/build_trio.yml`](../.github/workflows/build_trio.yml).

1. Open **Actions → 4. Build Trio**.
2. Selecteer exact één van `upgrade/trio-1.0`, `main` of `dev`.
3. Start de run. De workflow bouwt alleen de geselecteerde branch en
   synchroniseert Nightscout niet.

Gebruik voor het archief geen build. Controleer vóór starten dat branch,
appnaam en verwachte TestFlight-app bij elkaar horen.

### 2. Add Identifiers

Workflow:
[`.github/workflows/add_identifiers.yml`](../.github/workflows/add_identifiers.yml).

- Alleen gebruiken bij eerste inrichting van `main` en `dev`, of bij gericht
  herstel van identifiers/provisioning.
- Niet routinematig uitvoeren en niet opnieuw op `upgrade/trio-1.0`, tenzij
  de bestaande Trio-identifiers gerepareerd moeten worden.
- De workflow past eerst de branchflavor toe en maakt/actualiseert daarna via
  Fastlane de app-, Watch App-, Watch Complication- en Live Activity-IDs.

## Apple, signing en TestFlight
Elke actieve branch is één afzonderlijke iOS-app in App Store Connect. De
bundle ID is de sleutel waarmee Fastlane de juiste TestFlight-buildnummering,
identifiers en provisioningprofielen vindt.

- Richt voor `main` en `dev` ieder een eigen ASC-app, App Group en interne
  TestFlight-groep in.
- Koppel de App Group van die track aan de hoofdapp, Watch App en Watch
  Complication. De Live Activity gebruikt geen App Group.
- Schakel **Time Sensitive Notifications** in op de hoofdapp-identifier van
  elke track.
- `4. Build Trio` vraagt via Match de App Store-profielen op voor hoofdapp,
  Watch App, Watch Complication en Live Activity en uploadt de IPA naar de
  ASC-app die bij het bundle ID hoort.
- Een display name of URL scheme alleen maakt geen aparte ASC-app; het bundle
  ID doet dat.

De eenmalige Apple-stappen staan uitgebreider in
[`DeveloperDocs/three_trio_apps_apple_checklist.md`](three_trio_apps_apple_checklist.md)
en [`fastlane/testflight.md`](../fastlane/testflight.md).

## Veiligheids- en onderhoudsregels

- Merge nooit de appidentiteit van de ene actieve branch in de andere.
  `main` blijft Trio Main, `dev` blijft Trio Dev en de custom branch blijft
  Trio.
- Force-push nooit `main` of `dev`.
- Op `upgrade/trio-1.0` is alleen de beschreven schone rebase met
  `--force-with-lease` toegestaan. Controleer daarna dat cliniccode en
  flavor-overlay behouden zijn.
- Behandel `LibreTransmitter` en `MedtrumKit` als vastgepinde submodules.
  Een gitlink-SHA is onderdeel van de superprojectcommit; update of merge
  zo'n pin niet blind. Initialiseer submodules vóór een rebase en beoordeel
  upstreamwijzigingen tegenover de lokale Libre/Medtrum-aanpassingen.
- Bouw nooit `archive/main-pre-vanilla` en neem die branch niet op in sync.
- Test na workflowwijzigingen minimaal YAML-parsing en bij voorkeur
  `actionlint`; test shellscripts met `bash -n`. Controleer daarnaast de
  branchmapping met `.github/scripts/apply_app_flavor.sh`.
- Commit documentatie of workflowwijzigingen apart van lokale product-WIP.

## Huidige aandachtspunten (5 oktober 2026)

- Defaultbranch van de fork: `main`; Issues zijn momenteel uitgeschakeld.
  Een custom rebaseconflict levert daarom een warning/log op, geen issue.
- [PR #3](https://github.com/cornegabriels599/Trio/pull/3),
  **Upgrade fork customizations to Trio 1.0**, is open van
  `upgrade/trio-1.0` naar `main`. GitHub rapporteert momenteel
  **MERGEABLE/CLEAN**, zonder checks. Die status is tijdelijk en zegt niet dat
  de branchrollen mogen worden samengevoegd; het mergen zou de afgescheiden
  vanilla/custom-identiteiten doorbreken.
- Remote-tips bij de controle vóór deze documentatiecommit: `main`
  `674ed912e`, `dev` `1c118582b`, custom `ba9dde1a5` en archief `78f7ecf81`.
- Er staat lokale, niet-gecommitte OpenSourceClinic/simulator-WIP in de
  werkmap. Die wijzigingen zijn niet automatisch onderdeel van
  `origin/upgrade/trio-1.0` en mogen niet als remote-functionaliteit worden
  beschreven totdat ze apart zijn gecommit en gepusht.
- Omdat alleen de defaultbranch door cron wordt gestart, moet bij een
  toekomstige defaultbranchwijziging eerst worden gecontroleerd dat daar de
  actuele Sunday-workflow en het script aanwezig zijn.

## Herstel bij een zondagconflict

1. Lees de conflictlijst in de job summary/log (of het aangemaakte issue).
2. Zorg dat lokale product-WIP veilig apart staat; begin met een schone
   werkmap.
3. Voor de custom branch:

   ```bash
   git fetch origin upstream
   git switch upgrade/trio-1.0
   git reset --hard origin/upgrade/trio-1.0
   git submodule update --init --recursive
   git rebase upstream/main
   # los elk conflict bewust op
   git add <opgeloste-bestanden>
   git rebase --continue
   ```

4. Controleer cliniccode, flavorbestanden en de LibreTransmitter/MedtrumKit
   pins; voer passende tests plus `bash -n`/`actionlint` uit.
5. Push pas na een schone rebase:
   `git push --force-with-lease origin upgrade/trio-1.0`.
6. Start daarna **4. Build Trio** op `upgrade/trio-1.0`.
7. Los een vanilla conflict op met een gewone merge vanaf upstream en een
   normale push; rebase of force-push `main`/`dev` nooit.
