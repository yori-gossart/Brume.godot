# SYSTÈME D'INTERACTION — Fog Nomad Godot 0.2

## Le principe

**Interagir ne ralentit jamais le joueur.**

C'est la section 28 de la mission, et c'est la contrainte qui a dicté toute
l'architecture. En 0.1, le ramassage fonctionnait déjà en courant, mais il
était câblé en dur : le scanner du joueur reconnaissait un ramassable par
`has_method("can_collect")`. Cela ne survit pas à l'arrivée des portes, des
feux, des piliers et des coffres.

Mesure de référence, prise par `tests/world_systems_test.gd` :

```
PICKUP WHILE RUNNING    4,69 → 4,80 m/s (102 % conservés), dérive de cap 0,0000 rad
```

Le ramassage ne coûte rien parce qu'il ne **touche** rien : ni la vélocité,
ni la rotation, ni l'état de déplacement, et il n'y a aucun temps de
recharge. Le seul effet sur le joueur est un geste du haut du corps, filtré
hors des jambes par l'`AnimationTree`.

---

## Les deux moitiés d'un objet interactif

Un objet interactif a **deux corps distincts**, et les confondre est le bug
classique :

```
Porte
├── Leaf          AnimatableBody3D   layer WORLD_STATIC   ← la matière
│   └── CollisionShape3D                                    (le battant)
└── Interact      InteractableComponent (Area3D)          ← le capteur
    └── CollisionShape3D              layer INTERACTABLE    (la portée)
```

Le capteur ne bloque personne : aucun masque de déplacement ne contient
`INTERACTABLE`. La matière n'est jamais désactivée.

---

## `InteractableComponent`

`scripts/interaction/interactable_component.gd`

| Propriété | Rôle |
| --- | --- |
| `action` | le verbe : `TAKE` `OPEN` `CLOSE` `LIGHT` `EXTINGUISH` `INSPECT` `ACTIVATE` `USE` `INSERT` |
| `noun` | le complément : « Porte », « Bois », « Pilier » |
| `interact_range` | portée propre à l'objet (§73) |
| `interact_priority` | départage avant la distance |
| `enabled` | disponibilité brute |
| `requires_line_of_sight` | vérifier qu'aucun mur ne s'interpose |
| `condition_target` | objet consulté via `can_be_used_by(actor)` |
| `definition` | le `WorldObjectDefinition` associé |
| `state` | `READY`, `OPEN`, `LIT`, `TAKEN`… |

Le libellé du bouton est `prompt()` : `"OUVRIR — Porte"`.

> Note d'implémentation : la propriété s'appelle `interact_priority` et non
> `priority`, parce que `Area3D` possède déjà un membre `priority` en
> Godot 4.3 et que le redéfinir casse le chargement du script.

### Étendre le système

Trois façons, par ordre de simplicité :

1. **Poser un composant et écouter son signal.** C'est ce que font la porte,
   le feu et le pilier : ils créent un `InteractableComponent`, connectent
   `interacted` et réagissent.
2. **Hériter.** `Pickup extends InteractableComponent` et redéfinit
   `perform()` et `can_interact()`.
3. **Conditionner.** Donner un `condition_target` qui expose
   `can_be_used_by(actor)`. Le feu s'en sert pour ne pas proposer
   « ALLUMER » à quelqu'un qui n'a pas de bois.

---

## Le scanner : choisir la bonne cible

`scripts/interaction/interactor.gd`

La section 30 nomme le défaut à éviter : « je ramasse ce qu'il y a derrière
moi ». Le score d'un candidat est :

```
score = interact_priority × 10
      + (cap · direction_vers_l_objet) × forward_weight
      − distance
```

et un candidat est **éliminé** si :

* il est plus loin que sa propre `interact_range` ;
* il est à plus de `max_angle_deg` (110°) du cap — donc derrière ;
* `requires_line_of_sight` et un rayon sur `WORLD_STATIC` rencontre un mur ;
* `can_interact(acteur)` répond non.

Le « cap » est la **vitesse réelle** du joueur quand il bouge, et son
orientation quand il est à l'arrêt. En courant, on vise donc ce vers quoi on
court.

Un seul prompt est affiché à la fois (§72). Quand il n'y a rien à portée, le
bouton **disparaît** — plutôt que de rester grisé et inerte (§72).

### Ligne de vue

Vérifiée par `tests/world_systems_test.gd` :

```
LINE OF SIGHT BLOCKS REACH   debout dehors contre le mur, le pilier n'est pas proposé
```

Le rayon part de la poitrine (`eye_height`) et ne teste que `WORLD_STATIC` :
un autre personnage ou un volume d'eau n'empêche pas d'ouvrir une porte. Un
impact à moins de 45 cm de la cible est ignoré — c'est le corps solide de
l'objet lui-même, pas un obstacle.

---

## Les objets, en données

### `ItemDefinition` — `scripts/data/item_definition.gd`

`id`, `display_name`, `category`, `weight_kg`, `rarity`, `stack_limit`,
`icon`, `world_scene`, `interaction_text`, `usable`, `tags`.

Deux définitions existent : `assets/data/items/wood.tres` et
`crystal.tres`. Ajouter une ressource est un `.tres`, pas une branche de
`match`.

`stack_limit` et `usable` ne sont encore consommés par rien : le vrai sac et
la vraie gestion du poids sont pour la 0.3 (§74). Ils sont définis
maintenant pour ne pas avoir à ré-écrire les données ensuite. Le poids
transporté, lui, est déjà cumulé et affiché dans le HUD de debug.

### `WorldObjectDefinition` — `scripts/data/world_object_definition.gd`

`category` parmi `STATIC_SOLID`, `STATIC_INTERACTABLE`, `PICKUP`,
`DECORATIVE`, `CHARACTER`, `AMBIGUOUS` (§53), plus `solid`, `interactable`,
`surface_type`, `collision_profile`, `tags`.

`is_consistent()` vérifie que la catégorie et les drapeaux racontent la même
histoire. Un objet resté en `AMBIGUOUS` est un bug.

---

## Feu et cristal : deux technologies, pas une

La section 47 insiste : le cristal ne doit pas devenir « du feu magique ».
La séparation est faite par le **carburant** et non par une étiquette :

| | Feu de camp | Pilier ancien |
| --- | --- | --- |
| Accepte | `BOIS` (1) | `CRISTAL` (1) |
| Refuse | tout le reste, y compris le cristal | tout le reste, y compris le bois |
| Verbe | `ALLUMER` / `ÉTEINDRE` | `INSÉRER` |
| Réversible | oui | non |
| Destiné à | chaleur, repos, cuisine, répit | balises, énergie, Brume |

Le prompt du feu n'apparaît pas si vous n'avez pas de bois ; celui du pilier
n'apparaît pas si vous n'avez pas de cristal. On ne peut donc pas les
confondre à l'usage, ce qui est la seule définition qui compte.

---

## La porte, et pourquoi sa collision n'est jamais coupée

`scripts/world/door.gd`. États : `CLOSED` → `OPENING` → `OPEN` → `CLOSING`.

La solution évidente — couper le collider quand la porte est « ouverte » —
est refusée. Le battant est un `AnimatableBody3D` sur `WORLD_STATIC`
**pendant toute sa vie**. L'embrasure devient franchissable pour une seule
raison : le battant n'y est plus.

> **Piège trouvé pendant le développement, et il est silencieux.**
> La structure naturelle est un `Node3D` « charnière » avec le battant en
> enfant, et on fait tourner la charnière. Cela ne marche pas : un
> `AnimatableBody3D` en `sync_to_physics` suit **sa propre** transformation,
> pas celle de son parent. Le battant visuel pivote, le corps physique reste
> fermé, et la porte a l'air ouverte tout en restant solide en travers du
> passage. Le battant tourne donc lui-même, et la charnière est son origine.
> `tests/world_systems_test.gd` fait traverser le joueur dans les deux
> états ; c'est ce test qui a attrapé le problème.

Pendant `OPENING` et `CLOSING`, le composant est désactivé : pas
d'interaction en plein pivot.

---

## Interface

Un seul bouton d'interaction (§71), qui change de libellé selon l'objet
visé. Il n'y a jamais deux boutons d'action à l'écran.

```
PRENDRE — Bois        OUVRIR — Porte        ALLUMER — Feu        INSÉRER — Pilier
```

Le bouton `A` en haut à gauche ouvre l'écran d'apparence ; le bouton `i` en
haut à droite le panneau de mesures.
