# NOMADSLAND™ — GODOT 0.2.1
## MOVEMENT, COLLISION & GAME FEEL FIX

> Cette phase n'est **pas** un art pass. Objectif unique : **se déplacer dans
> NOMADSLAND doit commencer à être agréable.**
>
> ⚠️ Les vitesses ci-dessous ont été **réajustées en 0.2.1b** après le test
> réel sur Galaxy A55 : WALK 3.4 → 3.8 et RUN 5.5 → 5.8, SPRINT inchangé.
> Voir [`GODOT_0.2.1b_MOBILE_TUNING.md`](GODOT_0.2.1b_MOBILE_TUNING.md).

```
================================
BASELINE

BASELINE COMMIT :  17e9417a19b2b08ffac5a8f795eb72634c9dbb4f
BRANCHE 0.2 :      fog-nomad-godot-0.2-art-physics
BRANCHE 0.2.1 :    fog-nomad-godot-0.2.1-movement-bugfix
GODOT :            4.3 stable
RENDERER :         MOBILE (Forward Mobile)
TESTS 0.2 AVANT :  194/194 verts (30 + 144 + 17 + 3), relancés avant
                   la première ligne modifiée
================================
```

---

## 1. AVANT / APRÈS — LES CHIFFRES

Toutes les valeurs « après » vivent dans **un seul fichier** :
`scripts/player/player_movement_config.gd`, exposé comme ressource éditable
`scenes/player/PlayerMovement.tres` (section 36). Aucun script ne redéfinit
une vitesse.

### Vitesses

| | 0.2 | 0.2.1 | mesuré sur 5 s |
|---|---|---|---|
| marche | 1.5 m/s | **3.4 m/s** | 16.7 m → 3.34 m/s |
| course | 4.8 m/s | **5.5 m/s** | 27.4 m → 5.48 m/s |
| sprint | — (n'existait pas) | **7.5 m/s** | 36.2 m → 7.25 m/s |
| nage | 1.55 m/s | **2.6 m/s** | |
| nage rapide | 2.25 m/s | **3.3 m/s** | pic mesuré 3.30 m/s |

En 5 secondes, la 0.2 parcourait **7.5 m** en marche et **24 m** en course.
La 0.2.1 parcourt **16.7 m** et **36.2 m**. Sur une carte de 140 m, c'est la
différence entre traverser en une minute et traverser en vingt secondes.

Les paliers sont **analogiques** (section 3) : l'amplitude du stick est la
fraction du plafond demandée, et le plafond est WALK sans le bouton, RUN
avec, montant continûment jusqu'à SPRINT quand le pouce atteint le bord.
Il n'existe **aucun seuil** où la vitesse saute ; les noms de paliers sont
relus *depuis* la vitesse obtenue, pour le HUD et les tests.

### Accélération, décélération, rotation

| | 0.2 | 0.2.1 |
|---|---|---|
| accélération sol | 16 | **22** |
| décélération sol | 20 | **28** |
| accélération en l'air | 3.5 | **11** |
| accélération dans l'eau | 7.0 | **9.0** |
| rotation | 11 rad/s fixe | **17 → 8.5 rad/s**, interpolée avec la vitesse |
| pénalité de pente | 0.62 | **0.40** |
| bonus de descente | ×1.18 | **×1.10** |

La rotation interpolée est le point de la section 5 : un seul taux ne peut
pas être à la fois un demi-tour sur place instantané et un virage à 7.5 m/s
qui a du poids.

Le bonus de descente est passé de 1.18 à 1.10 pour une raison mesurable :
7.5 × 1.18 = 8.85 m/s, au-delà du plafond honnête de lecture du clip de
course (8.28 m/s). Un sprint en descente aurait écrêté la cadence, donc
glissé des pieds. 1.10 plafonne le pire cas à 8.25 m/s.

### Saut — il n'en existait aucun en 0.2

| | 0.2.1 | mesuré |
|---|---|---|
| hauteur | 1.25 m | **1.20 m** |
| temps jusqu'à l'apex | 0.40 s | **0.367 s** |
| durée totale en l'air | — | **0.717 s** |
| gravité en montée | 15.63 m/s² (dérivée) | |
| gravité en descente | 22.66 m/s² (×1.45) | |
| saut tapé (relâché tôt) | ×0.42 | **0.58 m = 48 % du saut plein** |
| coyote time | 0.12 s | fenêtre vérifiée à 80 ms oui / 400 ms non |
| tampon d'entrée | 0.12 s | vérifié à 0.55 m du sol oui / 1.9 m non |

La hauteur et l'apex sont les **entrées** ; la vitesse d'impulsion et la
gravité en sont les conséquences (`v0 = 2h/t`, `g = 2h/t²`). L'écart entre
1.25 et 1.20 mesuré est la discrétisation d'Euler semi-implicite à 60 Hz,
pas un réglage qui dérive.

La descente est 45 % plus lourde que la montée. C'est le truc le moins cher
du platformer : une parabole symétrique flotte, une chute plus lourde a de
l'intention. Cela ne change pas la hauteur du saut.

### Contact au sol

| | 0.2 | 0.2.1 |
|---|---|---|
| hauteur de marche franchie | **0** | **0.30 m** |
| pente maximale | 52° | 52° (inchangé, désormais dans la config) |
| accroche au sol | 0.45 | 0.40 |

### Caméra

| | 0.2 | 0.2.1 |
|---|---|---|
| distance | 7.4 m fixe | **6.9 → 8.3 m** selon la vitesse |
| champ de vision | défaut | **70° → 82°** selon la vitesse |
| hauteur de visée | 2.0 | 1.95, ×1.08 au sprint |
| suivi | 9.0 | **12.0**, vertical amorti à 0.55 |
| réalignement auto | 0.9 | **1.7** |

---

## 2. BUGS DE COLLISION CORRIGÉS

Aucun de ces bugs n'a été trouvé en lisant du code. Chacun a été trouvé en
envoyant le vrai `CharacterBody3D` dedans, ou en interrogeant le serveur
physique point par point (`tools/probe_openings.gd`).

### 2.1 La fenêtre de la ruine n'existait pas

`ruin.gd` construisait le mur ouest **plein** (`_wall_run(..., [], ...)`)
puis empilait par-dessus les deux blocs de `_window()` — l'allège et le
linteau. Résultat : pas de fenêtre du tout, un mur doublé, invisible et
inutilement solide. La section 21 demande que le collider et l'image soient
la même description de la même chose ; ici ils n'avaient même pas la même
forme.

**Corrigé** : le mur laisse un trou pleine hauteur à l'emplacement de la
fenêtre, et `_window()` le rebouche sous l'allège et au-dessus du linteau.
On voit à travers, on ne passe pas — et le collider dit exactement ça.

### 2.2 La brèche sud de la ruine était visible et inatteignable

Le dallage de la ruine dépasse le sol de ~0.38 m du côté aval. Une arête de
pierre propre qui **ressemble à une marche** et se comportait comme un
trottoir infranchissable. On voyait la brèche dans le mur sud, on ne pouvait
pas y entrer. C'est exactement l'interdit de la section 18.

**Corrigé** : deux assises basses (un stylobate) autour du dallage, qui
transforment une lèvre de 0.38 m en trois marches de ~0.16 m, toutes dans la
hauteur de pas du joueur. C'est aussi ce qu'une ruine de ce type aurait
réellement sous elle.

### 2.3 La rampe d'accès du pont finissait dans la rivière

`bridge.gd` échantillonnait le terrain **au bout du tablier** et faisait
descendre la rampe jusqu'à cette hauteur. À ce gué, le tablier surplombe
l'eau de quatre mètres : la rampe côté ouest descendait donc dans la
rivière et s'arrêtait là, la berge encore devant et un tiers de mètre plus
haut. Et elle était faite de **cinq caisses plates** — un escalier, pas une
rampe, dont chaque marche accrochait un personnage qui marche.

**Corrigé** : la rampe **marche vers l'extérieur** jusqu'à ce que le sol
remonte croiser une ligne descendant du tablier, et est construite en **une
seule dalle inclinée** : une surface continue, sans joint, qui atterrit sur
du vrai sol. Traversée mesurée : 0.02 m de la berge opposée, en sprint,
0 frame sous le tablier, jamais l'état SWIM.

### 2.4 Rien n'était franchissable

Godot n'a pas de step-up : un trottoir de 12 cm arrête un personnage net.
C'est la première cause de « le monde est fait de colle ».

**Corrigé** : sonde en trois temps (monter de 30 cm, avancer, redescendre),
entièrement en `test_move()` puis `move_and_collide()` — jamais une écriture
de `position`. Si l'une des trois réponses est non, l'obstacle est un vrai
mur et le joueur reste bloqué : c'est l'autre moitié de la section 18.

Deux pièges rencontrés en l'écrivant, tous deux trouvés par les tests :

- **lire la vitesse après `move_and_slide()`** donne « tu ne vas nulle
  part », qui est la réponse et pas la question. La sonde utilise maintenant
  l'intention capturée avant le déplacement — et la rend au joueur après une
  marche franchie, pour qu'un trottoir ne coûte pas tout son élan.
- **comparer seulement distance parcourue et distance demandée** déclenche
  sur une pente : glisser sur 30° ne rend que 75 % de la distance
  horizontale demandée, donc la sonde s'armait à chaque frame et devenait un
  cliquet qui remontait la montagne. Le déclencheur est désormais
  `is_on_wall()`, la réponse du moteur lui-même à « j'ai heurté quelque
  chose de plus raide que `floor_max_angle` », plus le test de distance en
  second. Et l'atterrissage doit être **praticable** : la sonde refuse de
  poser le joueur sur une face plus raide que la pente maximale, sinon
  n'importe quelle falaise devient un escalier et la section 16 ne veut plus
  rien dire.

### 2.5 Le garde-corps du pont

Deux exigences opposées se rencontrent ici, et c'est le sujet : **courir**
dans une rambarde de 0.95 m ne doit pas mettre à l'eau (sinon c'est une
collision incohérente), mais **sauter** par-dessus doit marcher, parce
qu'elle arrive à la poitrine et que le joueur franchit 1.25 m. Interdire le
saut serait un plafond invisible au-dessus d'une rambarde basse : le même
bug dans l'autre sens. Les deux cas sont testés séparément.

### 2.6 On peut désormais monter sur les gros rochers

Changement de comportement à documenter, pas un bug corrigé.

`rock_big_A` est à moitié enfoncé dans un versant à 40°, et son flanc mesure
entre 40° et 50° — sous la limite de 52° du personnage. En 0.2, marcher
dessus à 1.5 m/s avec une pénalité de pente de 0.62 ne montait quasiment
pas, et l'audit concluait « arrêté ». En 0.2.1, à 3.4 m/s et avec une
pénalité de 0.40, le joueur monte de 1.25 m en deux secondes et se retrouve
debout dessus.

Mesuré (`slope_angle` relevé image par image) : **0 franchissement de marche
utilisé**. Ce n'est donc pas la sonde de step-up qui grimpe ; c'est
`move_and_slide` sur une pente praticable. La 0.2 n'était simplement pas
assez rapide pour arriver en haut dans la fenêtre du test.

Décision : **on laisse**. Un mur invisible sur une face de pierre où l'on
se tient debout est précisément l'incohérence que la section 18 interdit, et
ce n'est en rien un passage à travers le rocher — la requête ponctuelle par
image le confirme indépendamment, 0 image à l'intérieur. L'audit distingue
maintenant « CLIMBED » de « ended inside the proxy radius » et compte le
premier comme un succès, en le disant dans sa note.

### 2.7 Les éboulis de la ruine

Le pan est effondré du mur est laisse des éboulis de ~0.5 m. Selon le
niveau du terrain à l'extérieur, ils passent au pas (là où le sol remonte)
ou au saut partout ailleurs. Les deux sont testés, et les deux vérifient
surtout qu'on ne finit **jamais à l'intérieur** de la géométrie.

---

## 3. INTERFACE — LE BOUTON SAUTER

Le pouce gauche tient le stick ; les deux boutons sont donc pour le pouce
droit, et **un seul pouce ne peut pas maintenir COURIR et taper SAUTER**.
Quelque chose devait céder (section 29).

Ce qui cède est le **mode d'appui** de COURIR, pas sa position : une **tape**
le verrouille (une seconde tape, ou l'arrêt du joueur pendant une demi-
seconde, le relâche), tandis qu'un **maintien** fonctionne exactement comme
en 0.2. Le pouce tape COURIR une fois, puis vit sur SAUTER — qui est pour
cette raison le gros bouton sous le pouce au repos. Un bouton verrouillé est
dessiné différemment d'un bouton maintenu, sinon le joueur ne comprend pas
pourquoi il sprinte.

Actions InputMap ajoutées (section 7) : `jump`, `interact`, `sprint`, avec
clavier **et** manette, pour que le développement au clavier et une
éventuelle page de re-mapping aient un nom à écrire.

**Saut et interaction** (section 27) : une interaction n'annule jamais un
saut et un saut n'annule jamais une interaction, mais on n'actionne pas un
mécanisme les pieds en l'air. Les portes, les feux et les leviers sont
retirés des candidats tant que le joueur n'est pas au sol — retirés, donc
le bouton n'est jamais proposé pour quelque chose qui ne ferait rien. Les
ramassages, eux, restent disponibles : attraper du bois en franchissant un
muret est légitime.

---

## 4. ANIMATION

Le principe de la section 34 est intact et a été **appliqué à l'envers de
ce qu'on pourrait croire** : l'animation suit le personnage, jamais
l'inverse. À 3.4 m/s, le palier WALK n'est plus une marche : le rig joue
honnêtement `Running_A` ralenti à 0.88×, parce que `Walking_A` à 4.4×
serait un dessin animé. À 7.5 m/s, `Running_A` à 1.95×, sous le plafond de
2.15×. Le stick à mi-course (1.5 m/s) joue toujours `Walking_A`.

Le test de glissement de pieds a donc été **restructuré, pas assoupli** : il
échantillonne trois points de la course du stick et juge chacun au plancher
du clip que le rig a **réellement** choisi, demandé au rig et non deviné
d'après la vitesse.

| échantillon | clip | glissement | plancher du clip |
|---|---|---|---|
| stick à mi-course (1.48 m/s) | `Walking_A` | 24 % | 28 % |
| palier WALK (3.30 m/s) | `Running_A` | 38 % | 47 % |
| sprint (7.35 m/s) | `Running_A` | 44 % | 47 % |

Le saut utilise de **vrais clips** : KayKit Adventurers livre `Jump_Start`,
`Jump_Idle` et `Jump_Land`, pilotés directement par les états d'air.
Contrairement à la nage, ce n'est pas provisoire.

---

## 5. HUD DE DEBUG (section 35)

`STATE` (milieu + état d'air + palier), `SPEED / TARGET_SPEED`,
`VERTICAL_VELOCITY`, `GROUNDED`, `fall`, `COYOTE`, `BUFFER`, nombre de
sauts, `SLOPE_ANGLE`, marches franchies, profondeur d'eau, `SURFACE`,
`INTERACT`. La paire qui compte est SPEED à côté de TARGET : une cible que
la vitesse n'atteint jamais désigne l'accélération, pas la vitesse de
pointe.

---

## 6. CE QUI N'EST PAS FAIT

Honnêtement, et par choix :

- **Pas de vault.** La section 17 demande la *structure*, pas la
  fonctionnalité. La sonde de franchissement est factorisée
  (`_probe_traverse(dir, rise, reach)`) précisément pour qu'un vault soit
  la même sonde avec une montée plus haute, une portée plus longue et une
  animation qui l'autorise. Aucun code mort n'a été ajouté pour autant.
- **Animation de nage toujours provisoire.** Aucun clip de nage dans le
  pack ; le modèle est basculé à plat et le cycle de marche sert de
  battement. Inchangé depuis la 0.2.
- **Animal toujours PLACEHOLDER** (`ANIMAL_ASSET_BLOCKED`). Hors périmètre
  de la 0.2.1 (section 45).
- **Aucune mesure de performance.** Cet environnement rend en logiciel
  (llvmpipe) et n'a pas de GPU ; aucun FPS mesuré ici n'est transposable.
  La section 79 de la 0.2 l'interdisait déjà. **La validation finale sera
  faite par l'utilisateur sur Samsung Galaxy A55.**
- Pas de ledge grab, pas de wall-run, pas de glissade, pas de double saut.
- Le contrôle aérien est généreux (11 m/s²). C'est un choix de confort ; il
  se baisse d'une ligne dans la config si le saut paraît trop dirigeable.

**Le plus gros manque de ressenti restant, à mon avis** : il n'y a **aucun
son** et aucun retour d'impact. Les vitesses sont bonnes maintenant, le saut
a une courbe, mais courir à 7,5 m/s en silence absolu et atterrir d'un mètre
vingt sans un bruit ni une secousse de caméra retire la moitié de ce qui
fait qu'un déplacement « se sent ». Tout est déjà en place pour y remédier :
`surface_changed` dit sur quoi on marche, `landed(fall_distance)` dit de
combien on est tombé, et le rig connaît la cadence exacte du pas. Il manque
les échantillons et trois lignes de branchement — c'est du travail 0.3, pas
de la 0.2.1, mais c'est ce que je changerais en premier.

---

## 7. RÉGLAGE FUTUR

Tout se règle dans `scenes/player/PlayerMovement.tres` depuis l'inspecteur,
sur le téléphone, sans toucher au code. Les valeurs y sont volontairement
absentes : la ressource n'override rien, donc les défauts lisibles de
`player_movement_config.gd` restent la source, et **toute modification faite
depuis le téléphone apparaît comme une ligne dans le diff.**

`PlayerMovementConfig.out_of_spec()` compare chaque valeur aux fourchettes
que le brief impose, et la suite de tests l'appelle : une édition
malheureuse depuis un inspecteur est attrapée par un test, pas par le
ressenti.

Ordres de grandeur si le déplacement doit encore bouger :

| ressenti | levier |
|---|---|
| « ça patine au démarrage » | `ground_accel` ↑ |
| « ça glisse à l'arrêt » | `ground_decel` ↑ |
| « le virage est une godille » | `turn_speed_fast` ↑ |
| « le saut flotte » | `fall_gravity_multiplier` ↑ |
| « le saut est mou » | `jump_apex_time` ↓ (la hauteur ne bouge pas) |
| « je m'accroche partout » | `step_height` ↑ (plafond du brief : 0.35) |
| « le sprint ne se sent pas » | `sprint_fov` ↑ sur la caméra |

---

## 8. TESTS

| suite | avant (0.2) | après (0.2.1) |
|---|---|---|
| `tools/benchmark_tests.gd` | 30 / 0 échec | 31 / 0 échec |
| `tests/collision_world_test.gd` | 144 / 0 échec | 144 / 0 échec |
| `tests/world_systems_test.gd` | 17 / 0 échec | 17 / 0 échec |
| `tests/soak_test.gd` | 3 / 0 échec | 3 / 0 échec |
| `tests/movement_test.gd` | — | **45 / 0 échec** |

Aucun test de la 0.2 n'a été supprimé (section 49). Trois choses ont été
**modifiées**, et chacune pour une raison explicable :

1. `NO FOOT SLIDING` : la 0.2 supposait que le palier « marche » jouait le
   clip de marche. Ce n'est plus vrai à 3.4 m/s, et le brief l'exige
   (section 34). Le test échantillonne maintenant trois vitesses et
   interroge le rig sur le clip réellement choisi — plus strict, pas moins.
2. Les vitesses de référence des tests de ramassage et de patauge sont
   relatives (`player.walk_speed × 1.4`), donc elles ont suivi les nouvelles
   valeurs sans édition.
3. L'audit de collision choisit ses points de départ autrement. Trois
   corrections, toutes déclenchées par de vraies fausses alertes :
   - le départ se pose sur **ce qui est réellement là** (assises de la
     ruine, semelle de la cabane) et non sur la hauteur du terrain, sinon
     il commence *dans* la pierre et le joueur ne bouge pas ;
   - la vérification de dégagement tire **deux rayons** : poitrine sur
     toute la distance, et 0.45 m sur le premier mètre trente. Un départ
     coincé derrière un bloc effondré produisait un « never moved » qui
     appartenait au bloc, pas à la cible. Le rayon bas est court exprès :
     il n'a qu'à repérer un départ bloqué, et exiger plusieurs mètres de
     sous-bois dégagé faisait perdre à l'audit cinq des six approches de
     `broadleaf_A` pour rien ;
   - « CLIMBED » n'est plus « ended inside the proxy radius » (voir 2.6).

   Résultat net : **144 essais, 0 échec, 0 élan ignoré** — contre 2 élans
   ignorés en 0.2. La couverture est donc meilleure qu'avant, pas moindre :
   12 obstacles × 6 approches × 2 niveaux de qualité, tous exécutés.

Les 144 essais de l'audit de collision passent désormais au **sprint** et
non plus à l'ancienne course : les six approches par obstacle utilisent le
bouton COURIR avec le stick à fond, soit 7.5 m/s. La section 25 — « pas de
tunneling à SPRINT_SPEED » — est donc couverte par l'audit existant, sur
12 obstacles × 6 approches × 2 niveaux de qualité.
