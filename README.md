# Looki pour Mac

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)
![Tests](https://img.shields.io/badge/tests-39%2F39-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

Application macOS native (SwiftUI) pour revoir, rechercher et archiver les
moments capturés par une caméra Looki L1, via l'API ouverte de Looki
(lecture seule). Outil personnel d'un seul développeur, publié par souci de
transparence — pas un produit avec support.

## Fonctionnalités

| Section | Contenu |
|---|---|
| **Calendrier** | Mois avec les jours marqués dès qu'ils contiennent des moments. |
| **Journée** | Timeline des moments : heure, titre, lieu, vignette, type de média. |
| **Détail** | Lecture de la vidéo ou de la photo du moment, description complète, adresse. |
| **Recherche** | Recherche sémantique dans tous les souvenirs, avec pagination. |
| **Archive** | « Archiver ce jour » télécharge les médias et écrit `journal.md` + `moments.json` dans `AAAA/MM/JJ/`. |
| **Réglages** | Clé API dans le trousseau, test de connexion, dossier d'archive, purge du cache. |

## Installation

Télécharger `LookiMac-<version>.dmg` depuis la page Releases, glisser l'app
dans Applications. DMG signé Developer ID et notarisé.

## Prérequis

- macOS 26 ou plus récent.
- Une clé API Looki : web.looki.ai › API Keys (elle ne s'affiche qu'une fois).

## Compiler depuis les sources

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LookiMac.xcodeproj -scheme LookiMac -configuration Debug build
cd LookiKit && swift test
```

## Release

```bash
SKIP_NOTARIZE=1 ./Scripts/release.sh 0.1.0   # dry run : build + signature + DMG
./Scripts/release.sh 0.1.0                   # + notarisation Apple + staple
```

## Arborescence

```
LookiKit/     package Swift : client API, modèles, cache, journal Markdown, archiveur (testé)
LookiMac/     app SwiftUI : fenêtre trois colonnes, réglages, trousseau, archive
Scripts/      release.sh — build, signature, notarisation, DMG
docs/         spec et plan d'implémentation
```

## Confidentialité

La clé API vit dans le trousseau macOS. Les métadonnées et vignettes sont
mises en cache dans le conteneur de l'app ; les liens vidéo signés ne sont
jamais écrits sur disque. L'archive est écrite uniquement dans le dossier que
vous choisissez. Aucune autre connexion réseau que `open.looki.ai` et les URL
de médias qu'il renvoie.

## Roadmap

- [x] v0.1 — calendrier, timeline, détail, recherche, archive, DMG signé
- [ ] Mises à jour Sparkle
- [ ] Cible CLI réutilisant LookiKit
- [ ] Index local pour recherche hors ligne

## Licence

MIT.
