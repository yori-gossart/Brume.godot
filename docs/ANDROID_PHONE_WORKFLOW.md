# OUVRIR LE BENCHMARK SUR TÉLÉPHONE ANDROID

Ce guide est écrit pour être suivi **sans rien connaître au développement**.
Tout se passe sur le téléphone. Aucun ordinateur n'est nécessaire.

Testé pour : **Samsung Galaxy A55 / Android**.

---

## Ce dont vous avez besoin

1. Le fichier **`fog-nomad-godot-benchmark-0.1.zip`**
2. L'application **Godot Editor** (version 4.3 ou plus récente)
   → Google Play Store, chercher « Godot Engine ».
   Prendre l'éditeur **standard**, pas la version « .NET » / « Mono ».

Environ **40 Mo** d'espace libre.

---

## Les 7 étapes

### 1. Télécharger le ZIP
Téléchargez `fog-nomad-godot-benchmark-0.1.zip` sur le téléphone.
Il arrive normalement dans **Téléchargements**.

**Ne le décompressez pas.** Godot le fait lui-même.

### 2. Ouvrir Godot
Lancez l'application **Godot**. Vous arrivez sur la liste des projets
(vide la première fois).

> L'éditeur est plus confortable **en paysage**, téléphone tourné.
> Le jeu, lui, se lancera en portrait : c'est voulu.

### 3. Appuyer sur « Import » / « Importer »
Bouton en haut de la liste des projets.

### 4. Choisir le ZIP
Naviguez jusqu'à **Téléchargements** et sélectionnez
`fog-nomad-godot-benchmark-0.1.zip`.

Godot propose un dossier de destination — laissez celui qu'il propose.
Puis **Import & Edit** / « Importer et éditer ».

### 5. Attendre l'import
Godot décompresse et convertit les modèles 3D et les textures.

> **La première ouverture prend une à trois minutes** sur un A55, et
> l'écran peut sembler figé. C'est normal : il importe deux personnages
> animés et une trentaine de modèles. Les ouvertures suivantes sont
> immédiates.

Si une fenêtre demande de **réimporter** ou de **convertir le projet**,
acceptez.

### 6. Lancer
Appuyez sur le bouton **▶ (Play)**, en haut à droite de l'éditeur.

Rien d'autre à régler : la scène principale est déjà configurée sur
`BenchmarkWorld.tscn`.

> Le tout premier lancement compile les shaders et peut saccader pendant
> quelques secondes. **Relancez une fois** avant de juger les performances :
> la deuxième exécution est représentative.

### 7. Jouer

| Où | Quoi |
| --- | --- |
| **Pouce gauche, en bas** | joystick — se déplacer. Il se recentre là où vous posez le pouce. |
| **COURIR**, en bas à droite | maintenir pour courir |
| **RAMASSER**, au-dessus de COURIR | apparaît quand une ressource est à portée |
| **N'importe où ailleurs** | glisser pour tourner la caméra |
| **i**, en haut à droite | affiche/masque le panneau de mesures |
| **HIGH / LOW**, à gauche du **i** | bascule la qualité graphique |

Aucun clavier n'est nécessaire.

---

## Ce qu'il faut regarder pendant le test

1. **Les FPS** (panneau `i`). Objectif 60, cible 45+, minimum acceptable 30.
   Le panneau affiche aussi le minimum et la moyenne sur les 12 dernières
   secondes — c'est ce chiffre-là qui compte, pas l'instantané.
2. **Courez dans un arbre, un rocher, la cabane.** Vous devez être arrêté.
3. **Courez en appuyant sur RAMASSER sans lâcher le joystick.** Vous devez
   ramasser sans ralentir ni changer de direction.
4. **Entrez dans la rivière.** Le déplacement doit ralentir (panneau : `WATER`),
   puis passer en `SWIM` quand c'est assez profond.
5. **Marchez vers le nord, vers la Brume.** Regardez le contact avec le sol,
   la silhouette du haut, le mouvement interne.
6. **Basculez HIGH → LOW** et regardez les FPS ET l'image changer.
7. **Le NPC** (personnage massif, près de la cabane) et **l'animal**
   (placeholder étiqueté) doivent se déplacer tout seuls.

---

## Si quelque chose ne va pas

**« Le projet ne s'importe pas »**
→ Vérifiez que vous avez bien pris l'éditeur Godot standard (pas .NET) et
qu'il est en version **4.3 ou plus récente**. Le projet est écrit pour 4.3 ;
une version plus ancienne ne l'ouvrira pas.

**« Écran noir au lancement »**
→ Attendez : la première compilation de shaders peut prendre 10 à 20 s.

**« Ça rame »**
→ Passez en **LOW** (bouton à gauche du `i`). Notez les deux chiffres,
HIGH et LOW : la comparaison fait partie du benchmark.

**« Je tombe à travers le sol »**
→ Cela ne devrait pas arriver ; notez l'endroit et ce que vous faisiez.

**« Je ne trouve pas la Brume »**
→ Elle est au **nord**. Le panneau `i` affiche en permanence la distance
(`brume  XX m ahead`). Marchez dans la direction qui fait baisser ce nombre.

---

## Modifier quelque chose depuis le téléphone

Le projet est fait pour ça. Les réglages les plus utiles sont des valeurs
nommées en haut des fichiers, pas des constantes enterrées :

| Pour changer | Ouvrir | Chercher |
| --- | --- | --- |
| vitesse de marche / course | `scripts/player/player_controller.gd` | `walk_speed`, `run_speed` |
| distance / hauteur de caméra | `scripts/player/player_camera.gd` | `distance`, `height` |
| densité et couleur de la Brume | `scripts/fog/fog_wall.gd` | `_make_layer` |
| quels arbres, combien, où | `scripts/world/scatter.gd` | tableau `SPECIES` en haut |
| forme du terrain | `scripts/terrain_data.gd` | `height_at` |
| taille des boutons tactiles | `scripts/ui/mobile_hud.gd` | `stick_radius_ratio` |

Le joueur, le NPC et l'animal sont aussi sélectionnables dans l'arbre de la
scène : leurs réglages apparaissent dans l'inspecteur.
