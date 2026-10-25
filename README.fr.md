# Sandy

<img src="Resources/AppIcon.png" alt="Sandy" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

Guide complet : [English](README.md) · [Русский](README.ru.md).
L’accès depuis un téléphone est encore prévu. Sandy est basé sur
[Cyclop](https://github.com/akalikbergenov/cyclop), sous licence MIT.

Une application macOS native qui transforme l’encoche du MacBook en espace de travail.
Survolez l’encoche pour ouvrir les commandes multimédias, une étagère de fichiers,
l’historique du presse-papiers, les extraits, le calendrier, la traduction,
la conversion de devises, le téléprompteur et les notes.

L’onglet **Agents** suit les sessions Claude Code et Codex prises en charge grâce
à l’utilitaire local `sandy-agent`. Il affiche les sessions simultanées, les
opérations en cours et les statistiques enregistrées par projet. Les notifications
de réponse prête, de saisie attendue et d’erreur sont facultatives. Activez le suivi
et les sources dans les réglages ; l’installation des hooks Claude passe uniquement
par le bouton dédié. Configuration et limites : [suivi des agents](docs/agent-monitor.md)
(en russe).

Sandy est maintenu par Abdirakhym. Le projet commence à la version **0.1.0** avec
un historique Git indépendant. Les attributions du code tiers figurent dans
`THIRD_PARTY_NOTICES.md`.

## Langues

L’interface est disponible en anglais, russe, kazakh, allemand, français, espagnol,
chinois simplifié et japonais. Choisissez la langue dans Réglages → Général → Langue :
le panneau change immédiatement. « Langue du système » suit les préférences de
macOS. Les demandes d’autorisation système changent de langue après le redémarrage de Sandy.
La langue de l’interface ne modifie pas la paire de langues de l’onglet « Traduire ».

## Raccourci clavier

Appuyez sur **Control + Option + Espace** pour ouvrir le panneau sur l’écran où
se trouve le pointeur. Répétez le raccourci, appuyez sur Esc ou cliquez dans une
autre application pour le fermer. Le panneau reste ouvert pendant l’utilisation
au clavier. Réglages → Général permet de choisir un autre raccourci ou de le
désactiver. Cette fonction ne nécessite pas l’autorisation d’accessibilité.

## Compiler et lancer

Nécessite macOS 15 ou version ultérieure et Swift 6. Les Xcode Command Line Tools
suffisent. Depuis le dossier du projet :

```sh
./Scripts/bundle.sh
open build/Sandy.app
```

La compilation locale utilise une signature ad hoc. La publication d’une version
signée avec Developer ID et notariée par Apple nécessite vos propres identifiants
Apple Developer ; voir [la signature](docs/signing.md) (en russe).

```sh
./Scripts/test.sh        # Vérifier les tests et les traductions
./Scripts/test-helper.sh # Vérifier l’utilitaire multimédia après compilation
./Scripts/dmg.sh         # Créer build/Sandy-0.1.0.dmg
```

La version est définie dans `Scripts/version`. Configurez votre propre dépôt
distant avant d’utiliser `Scripts/release.sh`.

## Données et autorisations

- Identifiant de l’application : `com.abdirakhym.sandy`.
- Réglages, extraits et notes : `~/Library/Application Support/Sandy`.
- Captures du presse-papiers : `~/Pictures/Sandy`.
- Le calendrier et le verrouillage du clavier demandent l’accès au calendrier
  et à l’accessibilité lors de l’utilisation des fonctions correspondantes.
- L’autorisation de notification des agents est demandée uniquement à leur activation.
  L’historique reste dans `~/Library/Application Support/Sandy/Agents/history.json` ;
  l’interface de suivi ne conserve ni les prompts ni les réponses.
- La traduction utilise le framework Translation de macOS et les packs de langues téléchargés.
- La conversion de devises récupère des taux de change publics. Le mécanisme de
  secours Spotify peut télécharger des pochettes. Les statistiques des agents
  restent sur ce Mac ; il n’y a ni télémétrie ni service de mise à jour automatique.

Sandy utilise ses propres réglages et son propre stockage. Les données d’une autre
application ne sont pas importées automatiquement. Détails : [SECURITY.md](SECURITY.md)
(en russe).

## Développement

Le code SwiftUI et AppKit se trouve dans `Sources/Sandy`, l’utilitaire multimédia
dans `Sources/SandyMediaHelper`. Les traductions et l’icône sont dans `Resources`,
les scripts de compilation et de création de paquets dans `Scripts`.

Avant de modifier le comportement, consultez [l’architecture](docs/architecture.md)
(en anglais), [le guide de contribution](CONTRIBUTING.md) et [la liste de vérification
avant publication](docs/release-checklist.md) (en russe). Now Playing utilise un
framework privé de macOS et un utilitaire Perl système : de futures versions de
macOS peuvent nécessiter des adaptations. L’application ne convient pas à une
distribution sur l’App Store.

## Licence

[MIT](LICENSE). Conservez la licence et les mentions relatives au code tiers lors
de la distribution des sources ou de l’application. Les documents du paquet
se trouvent dans `Sandy.app/Contents/Resources`.
