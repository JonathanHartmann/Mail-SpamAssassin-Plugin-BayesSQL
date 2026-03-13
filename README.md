# Mail-SpamAssassin-Plugin-BayesSQL
SpamAssassin plugin for Plesk that provides a centralized SQL Bayes database for all mailboxes and marks high-score mails with a custom header for MTA-based quarantine routing.


Ein SpamAssassin-Plugin für Mailserver mit Spamassassin das eine **zentrale SQL-Bayes-Datenbank** für alle Mailboxen bereitstellt und Mails mit hohem Score automatisch mit einem Header markiert.

---

## Inhaltsverzeichnis

- [Funktionen](#funktionen)
- [Voraussetzungen](#voraussetzungen)
- [Dateistruktur](#dateistruktur)
- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Autolearning](#autolearning)
- [HighSpam-Header](#highspam-header)
- [Betrieb & Monitoring](#betrieb--monitoring)
- [Bayes-DB aufbauen](#bayes-db-aufbauen)
- [Bekannte Eigenheiten](#bekannte-eigenheiten)

---

## Funktionen

| Funktion | Beschreibung |
|---|---|
| **Zentrale Bayes-DB** | Alle Mailboxen teilen eine gemeinsame SQL-Bayes-Datenbank statt individueller DBM-Dateien |
| **HighSpam-Header** | Mails ab einem konfigurierbaren Score erhalten den Header `X-Spam-ECHighSpam: YES; score=X.XX` |
| **Autolearning** | Mails werden automatisch als Spam oder Ham in die Bayes-DB eingelernt (Schwellen konfigurierbar) |

---

## Voraussetzungen

- SpamAssassin >= 3.4.2
- Plesk mit Postfix + spamd
- MySQL/MariaDB Datenbank
- Perl-Module: `Mail::SpamAssassin`, `DBI`, `DBD::mysql`

### Datenbank vorbereiten

```sql
CREATE DATABASE spamassassin_bayes CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER 'bayes_dbuser'@'localhost' IDENTIFIED BY 'DEIN_PASSWORT';
GRANT ALL PRIVILEGES ON spamassassin_bayes.* TO 'bayes_dbuser'@'localhost';
FLUSH PRIVILEGES;
```

Tabellen werden automatisch von SpamAssassin beim ersten Start angelegt.

---

## Dateistruktur

```
/etc/spamassassin/
├── ZZ_BayesSQL.pm        ← Plugin-Code
|── ec_bayes.env          ← Credentials & Konfiguration
├── zz_bayes_sql.pre      ← Plugin laden
└── ZZ_BayesSQL.cf        ← Header-Direktive & Schwellwerte
```

---

## Installation

### 1. Plugin herunterladen

### 2. Datenbankverbindung in der .env anpassen, sowie für den Start in der ZZ_BayesSQL.cf die Variable "bayes_auto_learn 0" setzen

### 3. Dateien kopieren und im Spamassassin Verzeichnis ablegen

### 4. Syntax prüfen & Dienst neu starten

```bash
perl -c /etc/mail/spamassassin/ZZ_BayesSQL.pm
spamassassin --lint 2>&1 | grep -i "error\|ZZ_Bayes"
systemctl restart spamassassin
```

---

## Konfiguration



### Wichtiger Hinweis zu Autolearn-Schwellen

Der tatsächliche Autolearn-Score kann vom angezeigten Score abweichen. Zum Debuggen:

```bash
spamassassin -D -t < /pfad/zur/mail.eml 2>&1 | grep -i "computed score for autolearn"
```

---

## Autolearning

### Phase 1 – Manueller Aufbau (empfohlen)

Bevor Autolearning aktiviert wird, sollte eine solide Basis manuell eingelernt werden:

```bash
# Spam einlernen:
sa-learn --spam /var/qmail/mailnames/DOMAIN/NORMALER_USER/Maildir/.Spam/cur
sa-learn --spam /var/qmail/mailnames/DOMAIN/NORMALER_USER/Maildir/.Spam/new

# Ham aus einem Postfach einlernen:
sa-learn --ham /var/qmail/mailnames/DOMAIN/NORMALER_USER/Maildir/cur/

# DB synchronisieren:
sa-learn --sync

# Stand prüfen – Minimum: 200 Spam + 200 Ham:
sa-learn --dump magic | grep -E "nspam|nham"
```

### Phase 2 – Autolearning aktivieren

Erst wenn die DB ausreichend trainiert ist und der Betrieb beobachtet wurde:

```cf
# ZZ_BayesSQL.cf anpassen:
bayes_auto_learn 1
bayes_auto_learn_threshold_nonspam 2.8
bayes_auto_learn_threshold_spam   12.0
```

```bash
systemctl restart spamassassin
```

### Graubereich

Mails deren Autolearn-Score zwischen Ham- und Spam-Schwelle liegt werden nicht eingelernt (`autolearn=no`). Dies ist gewolltes Verhalten:

```
Score <= 2.8   → autolearn=ham
Score >= 12.0  → autolearn=spam
Score 2.8–12.0 → autolearn=no (Graubereich)
```

---

## HighSpam-Header

Ab dem konfigurierten `EC_HIGHSPAM_THRESHOLD` (Standard: 15.0) wird folgender Header gesetzt:

```
X-Spam-ECHighSpam: YES; score=101.64
```

Dieser Header kann vom MTA (Postfix) für eine automatische Umleitung in ein Quarantäne-Postfach genutzt werden:

```bash
# /etc/postfix/header_checks:
/^X-Spam-ECHighSpam: YES/    REDIRECT quarantaene@domain.de
```

```bash
postmap /etc/postfix/header_checks
postfix reload
```

---

## Betrieb & Monitoring

### Plugin-Status prüfen

```bash
spamassassin --lint -D 2>&1 | grep "ZZ_Bayes"
```

### Live-Log beobachten

```bash
journalctl -u spamassassin -f | grep -i "autolearn\|bayes\|ZZ_Bayes"
```

### Bayes-DB Stand

```bash
sa-learn --dump magic | grep -E "nspam|nham"
```




## Bayes-DB aufbauen

SpamAssassin benötigt mindestens **200 Spam- und 200 Ham-Mails** bevor Bayes-Scoring aktiv wird. Solange diese Schwelle nicht erreicht ist erscheint:

```
bayes: not available for scanning, only X spam(s) in bayes DB < 200
```

### Empfohlener Aufbau

```bash
# Aktuellen Stand prüfen:
sa-learn --dump magic | grep -E "nspam|nham"

# Spam aus dediziertem Spam-Eingangspostfach:
sa-learn --spam /var/qmail/mailnames/domain.de/central.quarantine/Maildir/cur/

# Sync:
sa-learn --sync
```

---




### Bekannte Eigenheiten


#### `autolearn=no` trotz niedrigem Score

SpamAssassin rechnet für Autolearning Netzwerk-basierte Regeln (URIBL, RBL, Bayes) aus dem Score heraus. Der angezeigte Score und der Autolearn-Score können daher stark voneinander abweichen. Den tatsächlichen Autolearn-Score ermitteln:

```bash
spamassassin -D -t < mail.eml 2>&1 | grep "computed score for autolearn"
```

#### `autolearn=unavailable` statt `autolearn=no`

Erscheint wenn die Bayes-DB noch nicht die Mindestanzahl von 200 Spam- und 200 Ham-Mails erreicht hat. Sobald diese Schwelle überschritten ist, verschwindet die Meldung automatisch.

---

