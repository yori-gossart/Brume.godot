# CONVENTIONS DE PHYSIQUE — Fog Nomad Godot 0.2

Source de vérité : **`scripts/physics_layers.gd`** (`class_name Layers`).
Le bloc `[layer_names]` de `project.godot` en est le miroir, pour que les
cases à cocher de l'inspecteur soient nommées et non numérotées — y compris
dans l'éditeur Android.

**Aucun littéral de masque ne doit apparaître dans un script.** On écrit
`Layers.WORLD_STATIC`, jamais `1`. Les `.tscn` contiennent des nombres parce
que le format de scène l'impose ; la table ci-dessous est leur traduction.

---

## Les huit couches

| Bit | Valeur | Nom | Contenu |
| --- | --- | --- | --- |
| 1 | 1 | `WORLD_STATIC` | terrain, troncs, gros rochers, murs, poutres, piliers, tour, ruines, tablier de pont, **porte fermée** |
| 2 | 2 | `PLAYER` | le `CharacterBody3D` du joueur |
| 3 | 4 | `NPC` | humains non joueurs |
| 4 | 8 | `ANIMAL` | animaux et créatures |
| 5 | 16 | `INTERACTABLE` | volumes de détection d'interaction (porte, feu, pilier, coffre) |
| 6 | 32 | `PICKUP` | ramassables |
| 7 | 64 | `WATER` | volumes d'eau |
| 8 | 128 | `HAZARD_FOG` | la Brume |

## Matrice

| Corps | `collision_layer` | `collision_mask` |
| --- | --- | --- |
| Terrain, arbres, rochers, bâtiments, ruines, tour, pont | `WORLD_STATIC` | `0` |
| Porte **fermée** | `WORLD_STATIC` | `0` |
| Porte **ouverte** | `0` | `0` |
| Joueur | `PLAYER` | `WORLD_STATIC` |
| PNJ | `NPC` | `WORLD_STATIC` |
| Animal | `ANIMAL` | `WORLD_STATIC` |
| Capteur d'interaction du joueur | `0` | `INTERACTABLE \| PICKUP` |
| `InteractableComponent` (Area3D) | `INTERACTABLE` | `0` |
| Ramassable (Area3D) | `PICKUP` | `0` |
| Volume d'eau (Area3D) | `WATER` | `PLAYER \| NPC \| ANIMAL` |
| Brume (Area3D) | `HAZARD_FOG` | `PLAYER \| NPC \| ANIMAL` |
| `SpringArm3D` de la caméra | — | `WORLD_STATIC` |

---

## Les cinq règles

### 1. Solide = `WORLD_STATIC`, et rien d'autre

Si le joueur regarde un objet et pense qu'il ne peut pas le traverser, cet
objet a un corps sur `WORLD_STATIC`. C'est la règle §17 de la mission, et
c'est la seule couche que les masques de déplacement des personnages
contiennent.

Corollaire : un objet qui n'est **pas** sur `WORLD_STATIC` ne peut
structurellement pas bloquer qui que ce soit. C'est voulu — un ramassable ou
un volume d'interaction ne doit jamais arrêter personne.

### 2. Capteur ≠ obstacle

Un objet interactif a **deux** corps distincts :

* un `StaticBody3D` sur `WORLD_STATIC` pour sa matière (le battant, le socle) ;
* une `Area3D` sur `INTERACTABLE` pour sa portée de détection.

Les confondre donne soit une porte qu'on traverse, soit une bulle invisible
de trois mètres contre laquelle on bute.

### 3. Les personnages ne se heurtent pas physiquement

`CHARACTER_MASK` ne contient que `WORLD_STATIC`. Un PNJ n'est pas un mur.

Ce n'est pas un oubli, c'est la réponse au §60 : deux `CharacterBody3D` qui
se poussent mutuellement finissent coincés dans une embrasure de porte et n'en
sortent jamais. La séparation est faite par **évitement souple** —
`scripts/characters/soft_body_avoidance.gd` — qui écarte latéralement sans
jamais annuler la vitesse, et qui se désactive si la situation ne se résout
pas. Le joueur ne traverse donc pas un PNJ « comme un fantôme » : il est
dévié.

### 4. Les collisions ne dépendent PAS du niveau de qualité

`HIGH` et `LOW` changent ce qui est **dessiné**, jamais ce qui est **solide**
(§65). Un arbre ne devient pas traversable parce qu'on a baissé la qualité.

En 0.1 la végétation cachée voyait ses formes désactivées en même temps ;
c'était cohérent mais c'est précisément ce que le §65 interdit. En 0.2 les
colliders des arbres et des rochers **restent actifs en permanence** et seul
le rendu varie. `tests/collision_world_test.gd` le vérifie aux deux niveaux.

### 5. Rendu et physique sont séparés

La végétation est dessinée en `MultiMeshInstance3D` (un draw call par
espèce) et collisionnée par un `StaticBody3D` distinct portant plusieurs
`CollisionShape3D`. Il n'y a **pas** un corps par instance (§62, §63), et il
n'y a **aucun** collider sur l'herbe, les fleurs, les petits cailloux et les
débris (§17, exception explicite).

---

## Ce qui est solide et ce qui ne l'est pas

| Catégorie (§53) | Collision | Interaction | Exemple ici |
| --- | --- | --- | --- |
| `STATIC_SOLID` | oui | non | tronc, gros rocher, mur, pilier |
| `STATIC_INTERACTABLE` | oui | oui | porte, feu de camp, pilier à cristal |
| `PICKUP` | non | oui | bois, cristal |
| `DECORATIVE` | non | non | herbe, fleur, nénuphar, caillou |
| `CHARACTER` | oui (monde seul) | selon le cas | joueur, PNJ, animal |

Chaque objet du monde déclare sa catégorie dans son `WorldObjectDefinition`
(`scripts/data/world_object_definition.gd`). Aucun objet n'est laissé dans
une catégorie ambiguë ; `tests/collision_world_test.gd` échoue s'il en trouve
un.

## Formes de collision : ce qu'on utilise

| Objet | Forme | Pourquoi |
| --- | --- | --- |
| Tronc d'arbre | `CylinderShape3D` vertical | on contourne le tronc, pas le feuillage |
| Gros rocher | `ConvexPolygonShape3D` simplifiée | épouse la silhouette sans coûter un trimesh |
| Mur, plancher, poutre | `BoxShape3D` | exact et gratuit |
| Pilier, fût | `CylinderShape3D` | idem |
| Battant de porte | `BoxShape3D` porté par la charnière | suit la rotation réelle du battant |
| Terrain | `ConcavePolygonShape3D` | mêmes triangles que le maillage visible |
| Personnage | `CapsuleShape3D` | glisse le long des obstacles |

Jamais de collision triangle par triangle sur un modèle d'auteur (§19, §21).
Le terrain est la seule exception, et c'est justifié : sa forme *est* la
surface jouable, et l'approximer produirait des pieds qui flottent.


---

# 0.2.1 — DÉPLACEMENT, SAUT, FRANCHISSEMENT

Ces conventions s'ajoutent aux précédentes ; rien au-dessus n'a changé.

## Les nombres vivent à un seul endroit

`scripts/player/player_movement_config.gd` est **la** source des vitesses,
accélérations, rotations, du saut, de la hauteur de pas et des seuils d'eau
du joueur. Le contrôleur, la caméra, l'interface tactile et les suites de
tests la lisent ; **aucun d'eux n'en redéfinit une valeur**.

Le contrôleur expose encore `walk_speed`, `run_speed`, `sprint_speed`,
`swim_speed`, `step_height`, `jump_height` — mais en **lecture seule**, comme
accesseurs qui renvoient la valeur de la config. Ce sont des raccourcis pour
les appelants ; ce ne sont pas des copies, et ils ne peuvent pas diverger.

`scenes/player/PlayerMovement.tres` est l'instance éditable dans
l'inspecteur. Elle n'override volontairement rien, pour que les défauts
lisibles du script restent la référence et qu'un réglage fait depuis le
téléphone soit **une ligne dans le diff**.

`PlayerMovementConfig.out_of_spec()` valide chaque valeur contre les
fourchettes du brief et `tests/movement_test.gd` l'appelle : une valeur
aberrante est attrapée par un test.

## Le saut est dérivé, pas réglé

On choisit la **hauteur** et le **temps jusqu'à l'apex**. L'impulsion et la
gravité en sont les conséquences :

```
v0 = 2 * hauteur / apex
g  = 2 * hauteur / apex²
```

La gravité de descente est `g × fall_gravity_multiplier` (1.45). Régler une
gravité puis chercher une impulsion donne des sauts lunaires.

Le joueur **n'utilise pas** `physics/3d/default_gravity` : les PNJ et les
animaux si (18.0 m/s²), et c'est voulu — leur chute n'a pas à suivre le
réglage du saut du joueur.

## Franchir : `test_move` d'abord, `move_and_collide` ensuite

`PlayerController._probe_traverse(dir, rise, reach)` fait, dans cet ordre :

1. `test_move` vers le haut de `rise` — y a-t-il la place ?
2. `test_move` vers l'avant de `reach` depuis là-haut — le passage est-il
   libre ?
3. `test_move` vers le bas — y a-t-il de quoi se poser, **et sa normale
   est-elle plus douce que `max_slope_deg`** ?

Seulement si les trois répondent oui, trois `move_and_collide()` exécutent
le mouvement. **Jamais d'écriture de `position`.** Si l'une répond non,
l'obstacle est un mur et le joueur reste bloqué devant.

Deux gardes sont obligatoires et ont chacune été ajoutées après un bug réel :

- le déclencheur est `is_on_wall()`, pas une comparaison de distance seule :
  glisser sur une pente rend moins de distance horizontale que demandé, donc
  un test de distance nu arme la sonde à chaque frame et transforme une
  falaise en escalier ;
- la normale d'atterrissage doit être praticable, sinon la sonde contourne
  `floor_max_angle` par le haut.

L'intention de vitesse est capturée **avant** `move_and_slide()` et rendue
après une marche franchie : lue après, elle vaut zéro contre le mur.

## Un vault réutilisera la même sonde

`_probe_traverse` prend la montée et la portée en paramètres exactement pour
ça. La 0.2.1 n'implémente pas de vault (section 17 demande la structure, pas
la fonctionnalité) et n'a pas ajouté de code mort pour le préfigurer.

## Les ouvertures sont l'absence de collider

Règle déjà posée en 0.2 pour les murs à trous, et **vérifiée** en 0.2.1 :
une fenêtre doit être un trou dans la course de mur, rebouché sous l'allège
et au-dessus du linteau. Empiler les blocs d'une fenêtre sur un mur plein
donne un mur doublé et aucune fenêtre — c'était le cas du mur ouest de la
ruine jusqu'ici.

`tools/probe_openings.gd` imprime, mur par mur, où les colliders ont
réellement des trous, au genou et à la poitrine. C'est le premier outil à
sortir quand « ça bloque et je ne vois pas quoi ».

## Un bâtiment posé sur une pente a une lèvre

Un dallage horizontal sur un terrain incliné dépasse du sol côté aval. Une
arête de pierre de 0.38 m ressemble à une marche et n'en est pas une. La
règle : **toute transition sol → bâtiment doit tenir dans `step_height`**,
au besoin en ajoutant des assises basses qui découpent la lèvre. C'est ce
que fait le stylobate de la ruine.


## 0.2.1b — un angle de manche se mesure contre l'axe qu'on utilise

Le couloir de direction du joystick (`scripts/ui/stick_shaping.gd`) ne
suppose **jamais** où est l'avant : l'appelant lui passe son axe et tout est
calculé relativement à lui.

La raison est qu'il y a trois conventions dans ce projet et qu'elles ne
coïncident pas :

| espace | avant |
|---|---|
| écran (le widget) | −Y — Y croît vers le bas |
| entrée (`move_input`) | +Y — `_wish_direction()` le multiplie par le forward de la caméra |
| monde | `Vector3(-sin(yaw), 0, -cos(yaw))` |

Un angle écrit en dur contre la mauvaise des trois donne un correctif qui a
l'air de fonctionner jusqu'à ce que le joueur se retourne. La règle : **tout
seuil angulaire sur une entrée est relatif à un axe passé en paramètre, et
se vérifie contre la trajectoire réelle du corps**, jamais contre la valeur
du widget qui l'a produit.
