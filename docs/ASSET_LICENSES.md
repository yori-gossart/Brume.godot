# FOG NOMAD — GODOT BENCHMARK 0.1 — LICENCES DES ASSETS

Règle du projet, reprise telle quelle de Fog Nomad 0.7.2 (three.js) :
**un asset dont la licence n'a pas été vérifiée n'entre pas.**
Vérifiée signifie lue chez l'auteur, pas déduite d'un miroir ni d'un article.

Tous les assets externes de ce dépôt viennent du dépôt GitHub **de leur
auteur**, et le fichier de licence livré avec le pack est conservé à côté des
fichiers. Ce sont exactement les mêmes packs que la version three.js : les
fichiers ont été **copiés depuis `Game/assets/`** et leurs preuves de licence
sont donc déjà établies dans `ASSET_LICENSES.md` de ce dépôt-là.

---

## 1. Modèles 3D — KayKit, par Kay Lousberg

| | |
| --- | --- |
| Auteur | Kay Lousberg — www.kaylousberg.com |
| Licence | **CC0 1.0 Universal** (domaine public) |
| Texte de licence | http://creativecommons.org/publicdomain/zero/1.0/ |
| Usage commercial | **autorisé explicitement** par le fichier de licence du pack |
| Attribution | non obligatoire — faite ici quand même |

### 1.1 KayKit — Adventurers Character Pack 1.0

| | |
| --- | --- |
| Source | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |
| Page de l'auteur | https://kaylousberg.itch.io/kaykit-adventurers |
| Licence livrée | `assets/characters/KayKit-Adventurers-LICENSE.txt` |

| Fichier ici | Fichier three.js | Fichier KayKit d'origine | Rôle |
| --- | --- | --- | --- |
| `assets/characters/player_hooded_scout.glb` | `nomade_capuche.glb` | `Characters/gltf/Rogue_Hooded.glb` | **joueur** — petit éclaireur à capuche verte |
| `assets/characters/npc_sturdy.glb` | `nomade_robuste.glb` | `Characters/gltf/Barbarian.glb` | **NPC** — silhouette nettement plus massive |

**Modifications des fichiers : aucune.** Ils sont binairement identiques aux
originaux KayKit, seulement renommés.

Les armes livrées avec ces modèles (arbalètes, couteau, haches, bouclier,
chope) sont **masquées à l'exécution**, dans
`LocomotionRig.hide_weapons()` — exactement comme `assetmanager.mjs` le fait
côté three.js. Fog Nomad n'a ni ennemi ni combat. Le faire à l'exécution
plutôt que dans le fichier garde la provenance vérifiable octet par octet :

```bash
cmp Game/assets/characters/nomade_capuche.glb \
    assets/characters/player_hooded_scout.glb   # doit être silencieux
```

Deux personnages seulement ont été copiés (sur les quatre disponibles) :
le benchmark n'a besoin que d'un joueur et d'un NPC visiblement différent,
et chaque `.glb` pèse 3,6 Mo.

### 1.2 KayKit — Halloween Bits 1.0

| | |
| --- | --- |
| Source | https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 |
| Page de l'auteur | https://kaylousberg.itch.io/halloween-bits |
| Licence livrée | `assets/environment/structures/KayKit-Halloween-LICENSE.txt` |
| Atlas partagé | `halloweenbits_texture.png` (1024², commun à tous les modèles) |
| Modifications | **aucune** |

19 modèles repris sur les 63 du pack, à l'échelle réelle :

`tree_pine_orange_large` · `tree_pine_orange_medium` · `tree_pine_yellow_large` ·
`tree_dead_large` · `tree_dead_medium` · `pillar` · `post_lantern` ·
`lantern_standing` · `fence` · `fence_broken` · `fence_pillar` · `floor_dirt` ·
`floor_dirt_small` · `bench` · `path_A`…`path_D` · `arch`

Le nom « Halloween » du pack ne se lit dans aucun des modèles retenus.

### 1.3 KayKit — Medieval Hexagon Pack 1.0

| | |
| --- | --- |
| Source | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 |
| Page de l'auteur | https://kaylousberg.itch.io/kaykit-medieval-hexagon |
| Licence livrée | `assets/environment/nature/KayKit-Hexagon-LICENSE.txt` |
| Atlas partagé | `hexagons_medieval.png` (1024², commun à tous les modèles) |
| Modifications | **aucune** |

14 modèles repris, uniquement du sous-dossier `decoration/nature/` :

`tree_single_A` · `tree_single_B` · `trees_A_medium` · `trees_B_medium` ·
`rock_single_A`…`rock_single_E` · `waterlily_A` · `waterlily_B` ·
`waterplant_A`…`waterplant_C`

⚠️ **Note d'échelle importante.** Ces modèles sont authorés à l'échelle des
tuiles hexagonales du pack (un arbre fait ~1,2 unité de haut, un rocher
~0,3). Ils sont **remis à l'échelle au moment de la dispersion**
(`scripts/world/scatter.gd`, champ `scale` de chaque espèce), pas dans les
fichiers. Les modèles Halloween, eux, sont déjà à l'échelle réelle (un pin
fait 7,5 m) et sont utilisés à l'échelle 1.

---

## 2. Ce qui n'est PAS un asset externe

Tout le reste est écrit dans ce dépôt et n'a donc pas de question de licence :

| Élément | D'où il vient |
| --- | --- |
| Terrain (maillage, relief, collision) | formule dans `scripts/terrain_data.gd`, maillé par `terrain_builder.gd` |
| Surface d'eau | maillée par `water_body.gd`, profondeur réelle cuite par sommet |
| Cabane d'éclaireur | primitives Godot assemblées par `scout_cabin.gd` |
| Tour-balise | primitives Godot assemblées par `beacon_tower.gd` |
| Brume (rideaux, nappes, volutes) | maillages générés par `fog_wall.gd` + `shaders/fog_*.gdshader` |
| Ressources BOIS / CRISTAL | primitives, `pickup.gd` |
| Animal | primitives, `animal_placeholder.gd` — **voir §3** |
| Bruit (terrain, brume, eau) | `NoiseTexture2D` générée par Godot, `assets/materials/noise_*.tres` |
| Interface tactile | dessinée en `_draw()`, `scripts/ui/mobile_hud.gd` — aucune texture |
| Maillage de navigation | construit par `nav_builder.gd` |

---

## 3. ANIMAL_ASSET_BLOCKED

**Aucun animal n'a pu être ajouté, et l'animal du benchmark est un
placeholder explicitement étiqueté comme tel dans la scène.**

Ce qui a été cherché et ce qui a été trouvé :

* Les trois packs que Fog Nomad possède déjà (Adventurers, Halloween Bits,
  Medieval Hexagon) **ne contiennent aucun animal**, d'aucune sorte.
* Le compte GitHub de l'auteur (`KayKit-Game-Assets`) a été listé
  entièrement : 10 dépôts — personnages, squelettes, donjon, ville,
  restaurant, mobilier, base spatiale, hexagones, prototypage, Halloween.
  **Aucun pack d'animaux.**
* Les sources CC0 habituelles pour des animaux animés — Quaternius,
  Kenney, poly.pizza, OpenGameArt, itch.io — **sont hors d'atteinte** depuis
  cet environnement (politique réseau). Leur licence n'a donc pas pu être
  lue chez l'auteur, et conformément à la règle du projet **rien n'en a été
  pris**, y compris via un miroir qui les annonce comme CC0.

Conformément à la section 28 du cahier des charges, aucune heure n'a été
passée à fabriquer un faux animal convaincant en primitives. Le placeholder
est un quadrupède articulé sommaire qui existe pour prouver **le
comportement** — IDLE → WALK → FLEE, navigation, fuite déclenchée par le
joueur ou par la Brume — et pour rendre le trou du pipeline d'assets
**visible plutôt que masqué**. Il porte une étiquette 3D
`PLACEHOLDER / ANIMAL_ASSET_BLOCKED` lisible en jeu.

**Ce qui manque est un asset, pas un système.** Le jour où un animal CC0
vérifiable entre dans le projet, seul le maillage change.

---

## 4. Audio

Aucun fichier audio. `assets/audio/` est vide. Le son de Fog Nomad est
entièrement synthétisé côté three.js (`audio.mjs`) et n'a pas été porté :
il ne fait pas partie de ce que ce benchmark compare.

---

## 5. Moteur

Godot Engine — **MIT**, https://godotengine.org — non redistribué ici.
Le projet contient uniquement des fichiers source ; l'utilisateur fournit
son propre binaire Godot.

Aucune GDExtension, aucun plugin d'éditeur, aucune bibliothèque tierce.
`EXTERNAL DEPENDENCIES : néant.`
