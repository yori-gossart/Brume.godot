# ASSET MANIFEST — Fog Nomad Godot 0.2

Un fichier par ligne. Pas de « Quaternius CC0 » global : la section 4 de la
mission demande une traçabilité par fichier, et c'est ce qu'il y a ici.

> **Les dix packs Quaternius imposés ne figurent pas dans ce manifeste parce
> qu'aucun n'a pu être téléchargé.** Voir `ASSETS_TO_DOWNLOAD.md` : la
> passerelle réseau répond 403 au CONNECT pour `quaternius.com`,
> `quaternius.itch.io`, `itch.io`, `poly.pizza`, `sketchfab.com`,
> `opengameart.org` et `kenney.nl`, et Quaternius n'a pas de dépôt GitHub
> officiel. Les assets ci-dessous sont ceux dont la licence **a** pu être
> lue chez l'auteur.

## Provenance commune

| | |
| --- | --- |
| Auteur | Kay Lousberg — www.kaylousberg.com |
| Licence | **CC0 1.0 Universal** (domaine public) |
| Texte | http://creativecommons.org/publicdomain/zero/1.0/ |
| Usage commercial | autorisé explicitement par le fichier de licence livré |
| Vérification | dépôts GitHub de l'auteur (`KayKit-Game-Assets`) |
| Fichiers de licence | livrés à côté des modèles, voir la dernière section |

Tous les fichiers listés sont **binairement identiques** aux originaux
KayKit, seulement renommés. Vérifiable :

```bash
cmp <pack-original>/<fichier> assets/<...>/<fichier>
```

## 1. Personnages — KayKit Adventurers Character Pack 1.0

Source : https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0

| Fichier dans le dépôt | Original KayKit | Rôle dans Fog Nomad | Modifications |
| --- | --- | --- | --- |
| `assets/characters/player_hooded_scout.glb` | `Characters/gltf/Rogue_Hooded.glb` | **Joueur** (corps « Éclaireur ») et **PNJ 1 — Éclaireur** | aucune sur le fichier ; armes masquées à l'exécution ; tenue recolorée par bandes de teinte |
| `assets/characters/npc_sturdy.glb` | `Characters/gltf/Barbarian.glb` | corps « Robuste » — **PNJ 3 — Artisan** | idem |
| `assets/characters/npc_tall.glb` | `Characters/gltf/Mage.glb` | corps « Longiligne » — **PNJ 4 — Ancien** | idem |
| `assets/characters/npc_burdened.glb` | `Characters/gltf/Knight.glb` | corps « Équipé » — **PNJ 2 — Voyageur** | idem |

Les textures `*_texture.png` à côté de ces `.glb` sont **extraites
automatiquement par l'importeur glTF de Godot** au premier import ; elles ne
sont pas des fichiers d'auteur distincts.

Licence livrée : `assets/characters/KayKit-Adventurers-LICENSE.txt`

## 2. Nature — KayKit Medieval Hexagon Pack 1.0

Source : https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0

Sous-dossier repris : `decoration/nature/` uniquement.

> ⚠️ Ces modèles sont authorés à l'échelle des tuiles hexagonales du pack
> (un arbre fait ~1,2 unité). Ils sont **remis à l'échelle à la dispersion**
> (`scripts/world/scatter.gd`, champ `scale`), jamais dans les fichiers.

| Fichier | Usage dans Fog Nomad |
| --- | --- |
| `KayKit-Hexagon-LICENSE.txt` | fichier de licence livré avec le pack |
| `hexagons_medieval.png` | atlas partagé de tous les modèles ci-dessus |
| `rock_single_A.gltf` | caillou — décoratif, sans collision |
| `rock_single_B.gltf` | petite pierre — décoratif, sans collision |
| `rock_single_C.gltf` | gros rocher B — collision enveloppe convexe |
| `rock_single_D.gltf` | rocher moyen — collision enveloppe convexe |
| `rock_single_E.gltf` | gros rocher A — collision enveloppe convexe |
| `tree_single_A.gltf` | arbre feuillu A (bosquets) — collision de tronc |
| `tree_single_B.gltf` | arbre feuillu B (lisières) + arbres de bord de chemin — collision de tronc |
| `trees_A_medium.gltf` | buisson de sous-bois — décoratif, sans collision |
| `trees_B_medium.gltf` | buisson de lisière — décoratif, sans collision |
| `waterlily_A.gltf` | nénuphar — décoratif |
| `waterlily_B.gltf` | nénuphar — décoratif |
| `waterplant_A.gltf` | plante aquatique — décoratif |
| `waterplant_B.gltf` | roseau — décoratif |
| `waterplant_C.gltf` | roseau — décoratif |

## 3. Structures et conifères — KayKit Halloween Bits 1.0

Source : https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0

Ces modèles sont à l'échelle réelle (un conifère fait 7,5 m) et sont
utilisés à l'échelle 1. Le nom « Halloween » du pack ne se lit dans aucun
des modèles retenus.

| Fichier | Usage dans Fog Nomad |
| --- | --- |
| `KayKit-Halloween-LICENSE.txt` | fichier de licence livré avec le pack |
| `arch.gltf` | réserve — non placé en 0.2 |
| `bench.gltf` | banc du camp — décoratif |
| `fence.gltf` | clôture de la cour de la cabane — décoratif |
| `fence_broken.gltf` | clôture brisée de la cour — décoratif |
| `fence_pillar.gltf` | réserve — non placé en 0.2 |
| `floor_dirt.gltf` | réserve — non placé en 0.2 |
| `floor_dirt_small.gltf` | réserve — non placé en 0.2 |
| `halloweenbits_texture.png` | atlas partagé de tous les modèles ci-dessus |
| `lantern_standing.gltf` | réserve — non placé en 0.2 |
| `path_A.gltf` | dalles usées du chemin — décoratif |
| `path_B.gltf` | dalles usées du chemin — décoratif |
| `path_C.gltf` | dalles usées du chemin — décoratif |
| `path_D.gltf` | dalles usées du chemin — décoratif |
| `pillar.gltf` | réserve (détail de ruine) — non placé en 0.2 |
| `post_lantern.gltf` | lanternes jalonnant le chemin + lumière ponctuelle |
| `tree_dead_large.gltf` | arbre mort isolé — collision de tronc |
| `tree_dead_medium.gltf` | arbre mort de lisière — collision de tronc |
| `tree_pine_orange_large.gltf` | conifère orange grand (bosquets) — collision de tronc |
| `tree_pine_orange_medium.gltf` | conifère orange moyen (bosquets) — collision de tronc |
| `tree_pine_yellow_large.gltf` | conifère jaune (lisières) — collision de tronc |

## 4. Ce qui n'est pas un asset d'auteur

Construit en géométrie Godot par script, donc sans question de licence :

| Élément | Script |
| --- | --- |
| Terrain, relief, collision | `scripts/world/terrain_builder.gd` + `scripts/terrain_data.gd` |
| Surface d'eau | `scripts/world/water_body.gd` |
| Cabane d'éclaireur | `scripts/world/scout_cabin.gd` |
| Tour-balise | `scripts/world/beacon_tower.gd` |
| **Ruine** | `scripts/world/ruin.gd` |
| **Porte** | `scripts/world/door.gd` |
| **Pont** | `scripts/world/bridge.gd` |
| **Feu de camp** | `scripts/world/campfire.gd` |
| **Pilier ancien** | `scripts/world/stone_pillar.gd` |
| Ressources BOIS / CRISTAL | `scripts/world/pickup.gd` + `assets/data/items/*.tres` |
| Animaux (placeholders) | `scripts/animals/animal_placeholder.gd` + `animal_species.gd` |
| Brume | `scripts/fog/fog_wall.gd` + `shaders/fog_*.gdshader` |
| Bruit procédural | `assets/materials/noise_*.tres` (NoiseTexture2D de Godot) |
| Interface tactile et écran d'apparence | dessinés en `_draw()`, sans texture |

La section 42 de la mission autorise explicitement ce repli pour les ruines
lorsque le pack imposé est indisponible ; la section 67 interdit de recréer
en primitives un **asset d'auteur** manquant, ce qui n'a pas été fait — un
mur, une porte et un tablier de pont sont de l'architecture de niveau, pas
des modèles d'auteur. Aucun arbre, rocher, animal ni personnage n'a été
fabriqué en primitives pour remplacer un pack absent ; les animaux restent
des placeholders **étiquetés comme tels dans la scène**.

## 5. Fichiers de licence présents dans le dépôt

| Fichier | Couvre |
| --- | --- |
| `assets/characters/KayKit-Adventurers-LICENSE.txt` | les 4 personnages |
| `assets/environment/nature/KayKit-Hexagon-LICENSE.txt` | la nature |
| `assets/environment/structures/KayKit-Halloween-LICENSE.txt` | les structures et conifères |

## 6. Dépendances externes

**Aucune.** Pas de GDExtension, pas de plugin d'éditeur, pas de binaire, pas
d'outil au runtime, pas d'asset payant. Le moteur (Godot, MIT) n'est pas
redistribué : l'utilisateur fournit le sien.
