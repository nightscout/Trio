# Handleiding: zondagse Trio-update

Deze handleiding is voor de beheerder die de wekelijkse update controleert of
een conflict herstelt. De normale zondagupdate is automatisch. Gebruik de
opdrachten onder **Handmatig herstellen** alleen als de automatische oplossing
stopt.

## De drie actieve apps

| Branch | Soort | App in TestFlight | Bron |
|---|---|---|---|
| `main` | gewone (vanilla) stabiele Trio | **Trio Main** | `upstream/main` |
| `dev` | gewone (vanilla) ontwikkel-Trio | **Trio Dev** | `upstream/dev` |
| `upgrade/trio-1.0` | aangepaste OSC-versie | **Trio** | `upstream/main` plus eigen cliniccode |

`archive/main-pre-vanilla` is alleen een oud archief. Update of bouw deze
branch niet.

## Wat gebeurt er elke zondag?

De GitHub Actions-workflow **Sunday Sync All Tracks** staat in
[`sunday_sync_all_tracks.yml`](../.github/workflows/sunday_sync_all_tracks.yml).
Hij start elke zondag om **06:43 UTC**:

- in de Nederlandse wintertijd om **07:43 CET**;
- in de Nederlandse zomertijd om **08:43 CEST**.

De workflow controleert alle drie de actieve branches:

1. `main` wordt bijgewerkt vanaf Nightscout `main`;
2. `dev` wordt bijgewerkt vanaf Nightscout `dev`;
3. `upgrade/trio-1.0` wordt opnieuw boven op Nightscout `main` gezet.

Alleen als een branch echt is veranderd, start daarna automatisch de workflow
**4. Build Trio** voor die branch. Daar is geen vast tweede tijdstip voor:
de build begint nadat **Sunday Sync All Tracks** klaar is met bijwerken.

## Controleren of alles goed ging

1. Open de fork `cornegabriels599/Trio` op GitHub.
2. Open **Actions**.
3. Open de nieuwste run van **Sunday Sync All Tracks**.
4. Controleer de samenvatting:
   - bijgewerkte branches zijn gepusht;
   - een branch zonder nieuwe commits meldt dat geen update nodig was;
   - er zijn geen rode foutmeldingen of niet-opgeloste conflicten.
5. Open daarna **4. Build Trio**. Voor elke gewijzigde branch hoort een run te
   staan. Een ongewijzigde branch krijgt terecht geen build.
6. Controleer na een geslaagde build in App Store Connect → **TestFlight** de
   juiste app: **Trio Main**, **Trio Dev** of **Trio**.

Een groene Sunday Sync zonder nieuwe upstream-commits hoeft dus geen nieuwe
TestFlight-build op te leveren.

## Wat gebeurt er bij een conflict?

De workflow stopt de onveilige update:

- een vanilla conflict wordt niet gepusht;
- een custom rebaseconflict wordt afgebroken;
- `upgrade/trio-1.0` blijft dan op GitHub ongewijzigd;
- in de run-samenvatting en het log staat de conflictlijst;
- als GitHub Issues aanstaat, wordt ook het issue
  `Sunday rebase failed: upgrade/trio-1.0 onto nightscout/Trio main`
  gemaakt of bijgewerkt en aan de repository-eigenaar toegewezen.

De toewijzing helpt GitHub om de eigenaar te waarschuwen, maar een e-mail
wordt alleen verstuurd als de GitHub-notificatie-instellingen van de eigenaar
dat toestaan.

Andere branches die wel veilig zijn bijgewerkt, kunnen nog gewoon worden
gebouwd.

### Cursor Automation: Zondagconflict herstellen

De actieve Cursor Automation heet **Zondagconflict herstellen**. De juiste
trigger is:

- **Checks completed in Trio**
- **On Any Completion**
- **On Branch `main`**

De automation kijkt daarna zelf of de afgeronde check werkelijk bij
**Sunday Sync All Tracks** hoort en of er een relevant conflict is. Andere
afgeronde checks worden genegeerd. Gebruik niet **On PRs**: de zondagworkflow
draait op de branch en hoeft geen pull request te hebben.

De automation mag een conflict onderzoeken en een herstel voorbereiden. Een
mens moet nog steeds controleren dat de gekozen oplossing de clinicfuncties en
appidentiteiten bewaart.

## Eerst stoppen en hulp vragen

Ga niet verder en vraag een ontwikkelaar om hulp als:

- de lokale werkmap of cloud workspace eigen, niet-opgeslagen product-WIP
  bevat;
- niet duidelijk is van wie nieuwe commits of wijzigingen zijn;
- het conflict cliniclogica, pomp-/sensorwerking, signing of appidentiteiten
  verandert;
- `LibreTransmitter` of `MedtrumKit` onverwacht naar een andere commit wijst;
- tests mislukken;
- de rebase of merge na herstel niet volledig schoon is;
- `origin/upgrade/trio-1.0` veranderde nadat u hem ophaalde;
- u niet zeker weet welke versie behouden moet blijven.

Wis, stash, commit of push product-WIP niet alleen om de zondagupdate te laten
werken. Gebruik een nieuwe schone clone of schone cloud workspace. Zo blijft
het werk van anderen beschermd.

## Handmatig herstellen: custom OSC-branch

Dit deel geldt alleen voor `upgrade/trio-1.0`.

### 1. Vereisten

- Werk in een **schone, aparte workspace** zonder product-WIP.
- Controleer dat de remotes bestaan:

```bash
git remote -v
git status --short
```

`origin` moet naar `cornegabriels599/Trio` wijzen en `upstream` naar
`nightscout/Trio`. `git status --short` moet niets tonen. Stop als dat niet zo
is.

### 2. Begin exact bij de GitHub-versie

> **Let op — destructief:** `git reset --hard` wist lokale wijzigingen en
> lokale commits op deze branch. Doe dit alleen in de gecontroleerde, schone
> workspace uit stap 1.

```bash
git fetch --prune origin
git fetch --prune upstream
git switch upgrade/trio-1.0
git reset --hard origin/upgrade/trio-1.0
git submodule update --init --recursive
git status --short
```

De laatste opdracht moet niets tonen.

### 3. Voer de rebase uit

```bash
git rebase upstream/main
```

Bij ieder conflict:

1. open het bestand en begrijp zowel de Nightscout-wijziging als de
   OSC-wijziging;
2. kies bewust wat behouden of gecombineerd moet worden;
3. verwijder de conflicttekens;
4. ga verder:

```bash
git add <opgelost-bestand>
git rebase --continue
```

Herhaal dit tot Git meldt dat de rebase klaar is. Gebruik bij twijfel:

```bash
git rebase --abort
```

Daarmee keert u terug naar de situatie vóór de rebase en kunt u hulp vragen.

### 4. Controleer wat behouden moet blijven

Controleer minimaal:

- de OpenSourceClinic-code en configuratie;
- [`.github/app-flavors.yml`](../.github/app-flavors.yml): custom blijft
  **Trio**, `main` blijft **Trio Main** en `dev` blijft **Trio Dev**;
- de Sunday Sync- en Build Trio-workflows en scripts;
- de vastgezette commits van `LibreTransmitter` en `MedtrumKit`;
- dat er geen conflicttekens of onverwachte verwijderingen over zijn.

Handige controles:

```bash
git status
git diff --check upstream/main...HEAD
git diff --submodule=log upstream/main...HEAD
git log --oneline --decorate --max-count=20
```

Voer passende tests uit voor alle geraakte productcode. Laat bij twijfel een
ontwikkelaar de testkeuze bepalen. Controleer workflow- en shellwijzigingen
altijd met:

```bash
bash -n .github/scripts/sunday_sync_all_tracks.sh
actionlint .github/workflows/sunday_sync_all_tracks.yml
actionlint .github/workflows/build_trio.yml
```

`actionlint` moet vooraf geïnstalleerd zijn. Stop bij iedere fout.

### 5. Alleen na alle controles pushen

Haal vlak vóór de push opnieuw de remote op:

```bash
git fetch origin upgrade/trio-1.0
git status
```

Controleer dat de remote niet onverwacht door iemand anders is gewijzigd.

> **Let op — herschrijft remote geschiedenis:** de volgende opdracht is alleen
> toegestaan voor `upgrade/trio-1.0`, na een volledig schone rebase en alle
> controles hierboven. Gebruik nooit gewone `--force`.

```bash
git push --force-with-lease origin upgrade/trio-1.0
```

Als de lease de push weigert: **niet opnieuw forceren**. Iemand anders heeft
de branch veranderd. Stop en beoordeel de nieuwe remote-versie.

### 6. Nieuwe app bouwen

1. Open GitHub → **Actions** → **4. Build Trio**.
2. Kies branch `upgrade/trio-1.0`.
3. Kies **Run workflow**.
4. Controleer de run en daarna de app **Trio** in TestFlight.

## Handmatig herstellen: vanilla `main` of `dev`

Voor vanilla geldt een andere veiligheidsregel: gebruik een gewone merge en
een normale push. Gebruik **nooit** rebase, `--force` of
`--force-with-lease`.

Begin ook hier alleen in een schone, aparte workspace.

Voor `main`:

```bash
git fetch --prune origin
git fetch --prune upstream
git switch main
git reset --hard origin/main
git merge upstream/main
# los conflicten bewust op, daarna:
git add <opgeloste-bestanden>
git commit
git push origin main
```

Voor `dev`:

```bash
git fetch --prune origin
git fetch --prune upstream
git switch dev
git reset --hard origin/dev
git merge upstream/dev
# los conflicten bewust op, daarna:
git add <opgeloste-bestanden>
git commit
git push origin dev
```

> **Let op — destructief:** ook deze twee `git reset --hard`-opdrachten zijn
> alleen veilig in een vooraf gecontroleerde, schone workspace.

Controleer vóór de push dat de flavor-overlay en appidentiteit van de branch
behouden zijn. Start daarna **4. Build Trio** voor precies de herstelde branch.

## Korte probleemoplossing

### De automation reageert niet

Controleer de trigger. Die moet **Checks completed in Trio → On Any
Completion → On Branch `main`** zijn. **On PRs** is hier onjuist.

### De automation start bij een andere check

Dat kan door **On Any Completion**. De instructies horen niet-relevante checks
te herkennen en zonder wijzigingen te stoppen.

### Er was eerder een “prefill parse”-fout

Die fout kon tijdens het invullen of maken van de automation optreden. Na een
geslaagde inrichting is hij niet relevant voor de zondagse uitvoering.
Controleer dan alleen de opgeslagen trigger en instructies.

### Geen Build Trio-run zichtbaar

Een ongewijzigde branch krijgt geen build. Is de branch wel gewijzigd, open
dan de Sunday Sync-run en controleer de job **Build updated TestFlight
tracks** en de `GH_PAT`-melding.

### Geen conflictissue zichtbaar

Kijk altijd eerst in de run-samenvatting en het joblog. Als Issues in de
repository uitstaan, kan de workflow geen issue maken en geeft hij alleen een
warning.

## Woordenlijst

- **upstream**: de officiële bron, hier `nightscout/Trio`.
- **origin**: de eigen fork, hier `cornegabriels599/Trio`.
- **rebase**: eigen commits opnieuw plaatsen boven op de nieuwste officiële
  commits. Dit herschrijft de geschiedenis.
- **conflict**: Git kan twee wijzigingen niet veilig zelf combineren. Een
  mens moet kiezen wat behouden blijft.
- **TestFlight**: Apple-dienst waarmee een nieuwe appversie eerst door testers
  kan worden geïnstalleerd.
