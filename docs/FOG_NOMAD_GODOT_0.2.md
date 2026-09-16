# FOG NOMAD — GODOT 0.2
## Art identity, physical world, interaction foundation

Cette version met fin au statut de benchmark. Elle ne cherche pas à être
belle : elle cherche à ce que **le monde soit enfin matériel**.

```
BASELINE     e719318  (tag baseline-0.1, 29/29 verts avant modification)
BRANCHE      fog-nomad-godot-0.2-art-physics
GODOT        4.3 stable            RENDERER   MOBILE (Forward Mobile)
LANGAGE      GDScript seul         ORIENTATION portrait 720 × 1280
SCÈNE PRINC. scenes/BenchmarkWorld.tscn
SCÈNE REVUE  scenes/testing/ArtPhysicsShowcase.tscn
```

---

## Ce qu'il faut savoir en premier

**Les dix packs Quaternius imposés n'ont pas pu être téléchargés.** La
passerelle réseau de cet environnement répond **403 au CONNECT** pour
`quaternius.com`, `quaternius.itch.io`, `itch.io`, `poly.pizza`,
`sketchfab.com`, `opengameart.org` et `kenney.nl`. Quaternius n'a pas de
dépôt GitHub officiel — 49 dépôts contenant « Quaternius » ont été
inspectés, tous des portages tiers.

Des miroirs GitHub existent et sont téléchargeables. Ils n'ont pas été
utilisés, parce que c'est votre propre règle : « vérifiée signifie lue chez
l'auteur, pas déduite d'un miroir […] y compris via un miroir qui les
annonce comme CC0 », et la section 4 de cette mission répète « toujours
revalider la licence officielle ». **C'est une décision, pas une fatalité** :
dites le mot et je prends un miroir précis.

Conséquence sur le plan de travail : la mission impose elle-même l'ordre
(§61) — portes 1 à 5 avant l'art. **Les portes 1 à 5 ne dépendent d'aucun
pack, et elles sont livrées en entier.** Tout le détail dans
`ASSETS_TO_DOWNLOAD.md`, y compris la liste exacte à déposer et où.

---

## Les cinq portes de physique

### Porte 1 — convention de couches
`scripts/physics_layers.gd`, huit couches nommées, miroir dans
`project.godot` pour que l'inspecteur les affiche par leur nom. Aucun
littéral de masque dans le code. Détail : `PHYSICS_CONVENTIONS.md`.

### Porte 2 — arbres et rochers solides
9 essences d'arbres et 5 de rochers, ~370 instances, **175 colliders**.
Troncs en cylindre, rochers en enveloppe convexe simplifiée, rien sur
l'herbe et les cailloux.

**Correction importante vis-à-vis de 0.1 :** la 0.1 désactivait les
colliders des arbres cachés en qualité LOW. C'était cohérent, et c'est
exactement ce que la section 65 interdit — un arbre ne devient pas
traversable parce qu'on baisse la qualité. En 0.2, LOW **ne touche plus rien
de solide** : il économise sur la décoration (broussailles, cailloux,
plantes aquatiques), dont rien n'a de collider. Le monde de collision est
identique aux deux niveaux, et l'audit tourne aux deux.

### Porte 3 — bâtiments, portes, ruines, tour, piliers, pont
Cabane avec **une vraie porte**, ruine explorable, tour, pilier ancien, pont
franchissable au-dessus de la rivière.

La porte est le morceau intéressant : **sa collision n'est jamais coupée**.
Le battant est un `AnimatableBody3D` sur `WORLD_STATIC` pendant toute sa
vie ; l'embrasure devient franchissable parce que le battant n'y est plus.

> Piège trouvé par le test, et silencieux : un `AnimatableBody3D` en
> `sync_to_physics` ne suit pas la rotation de son **parent**. La première
> version faisait pivoter une charnière `Node3D` — le battant visuel
> s'ouvrait et le corps physique restait fermé en travers du passage. La
> porte avait l'air ouverte et bloquait quand même.

La ruine est construite en **tronçons de mur avec trous** : un trou est
l'absence d'un segment, donc l'absence d'un collider. Ce qu'on voit et ce
qu'on traverse viennent de la même description — pas de gros collider
enveloppant qui bouche les passages visibles (§24).

### Porte 4 — interaction générique
`InteractableComponent` + `Interactor`, score sur distance, angle, priorité
et ligne de vue, un seul prompt. `ItemDefinition` et
`WorldObjectDefinition` en ressources. Détail :
`INTERACTION_SYSTEM.md`.

```
PICKUP WHILE RUNNING    4,69 → 4,80 m/s (102 % conservés), dérive 0,0000 rad
```

### Porte 5 — surfaces
`GRASS` `DIRT` `ROCK` `WOOD` `WATER_SHALLOW` `WATER_DEEP`, lues sur le
**collider** (métadonnée ou groupe), jamais sur la texture. Les six sont
observées par le test.

> **Bug réel trouvé par le pont.** La 0.1 déterminait l'état d'eau à partir
> de la profondeur au-dessous du joueur. Dès qu'il a existé quelque chose
> sur quoi se tenir au-dessus de l'eau, traverser le pont annonçait `SWIM`.
> L'état exige maintenant d'être **réellement dans l'eau**, pas seulement
> au-dessus.

---

## Identité visuelle

Quatre corps, quatre nomades reconnaissables, recoloration par bande de
teinte mesurée sur les atlas, palette de huit couleurs dont le vert n'est
plus le défaut. Écran d'apparence tactile, avec la rangée « cheveux »
grisée et légendée parce que ces modèles n'ont pas de cheveux séparables.
Forêt composée en peuplements, clairières, lisières et bords de chemin
plutôt que dispersée au hasard. Détail : `ART_DIRECTION_0.2.md`.

---

## Tests

| Suite | Contenu | Résultat |
| --- | --- | --- |
| `tools/benchmark_tests.gd` | non-régression 0.1 + identité des PNJ + qualité/collision | **30 / 30** |
| `tests/collision_world_test.gd` | 11 obstacles × 6 approches × 2 niveaux de qualité | **132 / 132** |
| `tests/world_systems_test.gd` | portes, surfaces, ramassage en course, ligne de vue, évitement PNJ/animaux, fuite devant la Brume | **17 / 17** |
| `tests/soak_test.gd` | 5 constructions × 3 min simulées, cycles terre/eau, fuites de nœuds | voir le rapport |

Le principe, repris de 0.1 et durci par la section 68 : **rien n'est validé
en lisant un nœud**. L'audit de collision ne demande pas si un arbre a un
`CollisionShape3D` ; il lance le `CharacterBody3D` dessus, en marche, en
course, à 30°, à 45°, en diagonale et en rasant, et demande au serveur
physique, image par image, si le corps s'est retrouvé **à l'intérieur** de
la géométrie.

```bash
godot --headless --path . --script tools/benchmark_tests.gd
godot --headless --path . --script tests/collision_world_test.gd
godot --headless --path . --script tests/world_systems_test.gd
godot --headless --path . --script tests/soak_test.gd
```

---

## Ce qui reste en placeholder

1. **Animaux** — `ANIMAL_ASSET_BLOCKED`. Deux espèces au comportement réel
   (IDLE/WALK/FLEE, navigation, fuite de la Brume) et aux proportions
   distinctes, mais les modèles sont des placeholders étiquetés en 3D.
2. **Monstre, gobelin, troll** — absents.
3. **Nage** — `SWIM_ANIMATION_PARTIAL`, toujours la posture provisoire.
4. **Coiffures et corps genrés** — en attente des Universal Base Characters.
5. **Cabane, tour, ruine, pont, feu** — géométrie Godot, pas des modèles.
6. **Navigation sur le pont** — le maillage de navigation est construit
   depuis le terrain, qui considère la rivière infranchissable ; les PNJ
   n'empruntent donc pas encore le pont. Le joueur, si.
7. **Performances sur appareil réel** — non mesurées.

## Performances

Comme en 0.1, cet environnement n'a pas de GPU et rend sur `llvmpipe`.
**Aucun chiffre de FPS d'ici n'est transférable.** Ce qui l'est :

| | 0.1 | 0.2 |
| --- | --- | --- |
| Instances dispersées | 344 | 372 |
| Colliders de végétation | 142 | 175 |
| Polygones de navigation | 14 974 | 14 848 |
| Construction du monde | ~510 ms | ~850 ms |
| PNJ / animaux | 1 / 1 | 4 / 2 |

**VALIDATION A55 : EN ATTENTE UTILISATEUR.**
