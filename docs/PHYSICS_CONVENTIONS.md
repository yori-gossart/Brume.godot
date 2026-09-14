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
