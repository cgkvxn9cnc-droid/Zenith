# Zenith

**Dépôt :** [github.com/cgkvxn9cnc-droid/zenith](https://github.com/cgkvxn9cnc-droid/zenith)  
**Cloner :** `git clone https://github.com/cgkvxn9cnc-droid/zenith.git`

Application **macOS** de flux photo locale : catalogue (SwiftData), développement **non destructif** inspiré des réglages pros (exposition, couleur, netteté, grain, etc.), histogramme sur l’aperçu, bandeau de miniatures et export par lot.

Interface **SwiftUI**, rendu des prévisualisations via **Core Image**, données persistées sur disque.

## Captures d’écran

*(Ajoutez ici une ou deux captures une fois le dépôt en ligne.)*

## Fonctionnalités (aperçu)

- **Bibliothèque** : collections hiérarchiques, vue par mois, import de clichés, étoiles et drapeaux.
- **Développement** : panneau type carte avec nombreux modules (balance des blancs, basique, H/S, niveaux, netteté, grain, vignetage, etc.) ; copier/coller des réglages ; préréglages enregistrés.
- **Aperçu** : zoom (avec limite de dézoom), comparaison avant/après.
- **Histogramme** : calcul sur la prévisualisation développée.
- **Chrome visuel** : colonnes latérales en effet verre (Liquid Glass sur les systèmes compatibles).
- **Collaboration** *(interface)* : chat latéral lorsque la collaboration est activée ; invitation via la feuille dédiée.
- **Fichiers** : import, export catalogue JSON de secours, dossier cloud via signet sécurisé, export par lot.

Les chaînes sont préparées pour **français** et **anglais** (`Localizable.xcstrings`).

## Prérequis

- **macOS** : version alignée sur la cible du projet (**macOS 26.4** dans `Zenith.xcodeproj` au moment de la rédaction — à ajuster si vous supportez une version antérieure).
- **Xcode** récent avec Swift 6 / SwiftUI / SwiftData.

## Compilation

1. Cloner le dépôt (`git clone https://github.com/cgkvxn9cnc-droid/zenith.git`).
2. Ouvrir `Zenith/Zenith.xcodeproj` dans Xcode.
3. Sélectionner le schéma **Zenith** et la destination **My Mac**.
4. **Product → Run** (⌘R).

## Tests

Dans le terminal, depuis le dossier contenant le `.xcodeproj` :

```bash
xcodebuild -scheme Zenith -destination 'platform=macOS' test
```

## Structure du dépôt

| Élément | Rôle |
|--------|------|
| `Zenith/Zenith/` | Code source de l’app (vues, modèles, services, thème). |
| `Zenith/ZenithTests/` | Tests unitaires (ex. encodage des réglages). |
| `Zenith/ZenithUITests/` | Tests d’interface. |
| `Zenith/Zenith.xcodeproj` | Projet Xcode. |

## Contribution

Les **issues** et **pull requests** sont les bienvenues. Merci de décrire le contexte (version de macOS, build Xcode) et, si possible, d’ajouter un test ou un scénario de reproduction.

## Licence

Le projet est publié sous la **licence MIT** — voir le fichier [`LICENSE`](LICENSE).

---

*Projet initié par Romain Cobigo.*
