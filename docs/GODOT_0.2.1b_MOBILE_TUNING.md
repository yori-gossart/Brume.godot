# NOMADSLAND™ — GODOT 0.2.1b
## MOBILE MOVEMENT TUNING

> Micro-patch. La 0.2.1 est validée sur Galaxy A55 ; il restait deux
> réglages. Rien d'autre n'est touché : ni le saut, ni les collisions, ni
> l'eau, ni les interactions, ni la physique du monde, ni les géométries, ni
> les animations, ni l'architecture data-driven.

```
BASE     : da13085   (0.2.1, validée sur A55)
BRANCHE  : fog-nomad-godot-0.2.1b-mobile-tuning
GODOT    : 4.3 stable — renderer MOBILE — GDScript uniquement
```

---

## 1. VITESSES

| | 0.2.1 | 0.2.1b | mesuré sur 5 s |
|---|---|---|---|
| WALK | 3.4 m/s | **3.8 m/s** | 18.6 m → 3.73 m/s (pointe 3.81) |
| RUN | 5.5 m/s | **5.8 m/s** | 27.9 m → 5.59 m/s (pointe 5.77) |
| SPRINT | 7.5 m/s | **7.5 m/s** (inchangé) | 36.2 m → 7.25 m/s (pointe 7.55) |

Accélération (22 m/s²) et décélération (28 m/s²) **inchangées**. Aucune
nécessité technique ne s'est présentée : les deux paliers touchés sont
atteints en 0.17 s et 0.26 s départ arrêté, ce qui reste sous le seuil où
l'on sent un délai.

L'écart entre la consigne et la mesure sur 5 s est la rampe d'accélération
au départ plus la pénalité de pente du terrain réel — ce sont des moyennes
départ arrêté, pas des vitesses de pointe, et les pointes ci-dessus sont à
1 % de la consigne. Le palier RUN se mesure à l'amplitude de stick qui le
désigne (0.85), où la rampe continue demande 5.73 m/s et non 5.80.

**Effet de bord à connaître, sur l'animation.** Deux choses bougent avec le
palier WALK, et une seule est une bonne nouvelle.

`Running_A` est authored à 3.85 m/s, donc le palier WALK est maintenant joué
à **0.97×** — la cadence la plus proche de 1 de tout le jeu de locomotion.
En revanche le glissement de pieds mesuré au palier WALK **monte** de 38 % à
**46 %**, pour un plafond de test de 47 % qui n'a pas été déplacé. Ce n'est
pas la cadence : les planchers des clips ont été **re-mesurés** pour
l'occasion avec `tools/calibrate_stride.gd`, aux vitesses réellement
demandées, et ils sont plats —

| clip | vitesse | plancher mesuré |
|---|---|---|
| `Walking_A` | 1.25 m/s | 23.1 % |
| `Running_A` | 3.8 m/s | **35.4 %** |
| `Running_A` | 5.0 m/s | 35.2 % |
| `Running_A` | 7.5 m/s | 37.6 % |

Le rig vit donc à ~10 points au-dessus de l'idéal aux deux paliers rapides
(46 % à 3,7 m/s, 44 % à 7,35 m/s) — le même écart qu'en 0.2.1, pas une
régression. Ce qui a changé, c'est que l'échantillon du palier WALK couvre
maintenant quinze mètres de terrain vallonné en deux secondes au lieu de
treize, et l'inclinaison que le contrôleur applique au modèle sur une pente
fait bouger les pieds indépendamment du clip.

**À surveiller** : 46 contre 47, c'est un point de marge. Le seuil n'a pas
été relevé — le relever après avoir vu la mesure serait ajuster le test au
résultat. Si cette ligne passe au rouge un jour, la cause est là et non dans
une régression d'animation.

Une tentative de mesurer sur « le couloir le plus plat de la carte » plutôt
qu'au point fixe historique a été essayée et **abandonnée** : plat au sens de
la hauteur du terrain n'est pas dégagé au sens des arbres, et un élan qui
frôle un tronc rapporte la collision comme du glissement (54 %). Le point de
mesure reste celui de la 0.1, pour que les chiffres restent comparables
entre versions.

Les trois valeurs vivent toujours au même endroit,
`scripts/player/player_movement_config.gd` (section 36 de la 0.2.1). Les
bornes de `out_of_spec()` ont suivi : WALK 3.2–4.0, RUN 5.2–6.2.

---

## 2. FORWARD STEERING CORRIDOR

### Le problème, tel que constaté sur le téléphone

Un stick virtuel n'a **ni cran à midi ni ressort de rappel**. « Tout droit »
est un angle exact sur 360, qu'un pouce posé sur du verre ne tient pas. En
cherchant à courir droit devant, une dérive de trois ou quatre degrés
suffisait à courber la trajectoire.

### Le correctif

Un corridor autour de l'axe avant, dans lequel la composante latérale
accidentelle est retirée, suivi d'une bande courte où elle revient
progressivement.

| | |
|---|---|
| corridor | **±15°**, soit **30° de large** |
| transition | **9°** de plus de chaque côté (15° → 24°) |
| au-delà de 24° | **rien n'est touché** |
| interpolation | `smoothstep` |
| moitié arrière du stick | **jamais touchée** |

Au-delà de 24°, la direction analogique est rendue telle quelle : virage
serré, diagonale, déplacement latéral et marche arrière conservent toute
leur amplitude. Ce n'est **pas** un contrôleur 8 directions ; c'est une
correction de tremblement sur un huitième de la rose des vents.

### L'axe est un paramètre, jamais une constante

C'est le piège que le brief signale, et il est réel : le stick travaille en
espace écran (Y vers le bas), le contrôleur en espace d'entrée où +Y est
« loin de la caméra », et le monde en mètres. **Trois conventions.** Un angle
écrit en dur contre la mauvaise des trois donne un correctif qui a l'air de
marcher jusqu'à ce que le joueur se retourne.

`StickShaping` ne suppose donc jamais où est l'avant : l'appelant lui passe
son axe, et tout est calculé relativement à lui. `MobileHud.FORWARD_AXIS`
déclare celui du widget, et **le test le vérifie contre la direction que le
`CharacterBody3D` prend réellement**, pas contre la constante.

### L'intensité est préservée exactement

Annuler la composante latérale d'un vecteur unitaire laisse un vecteur plus
court : à 10° de l'axe, c'est 1,5 % de vitesse en moins. Le corridor aurait
donc ralenti le joueur en silence. Le vecteur corrigé est renormalisé à la
longueur reçue : **le corridor change une direction et rien d'autre.**

### Où il s'applique, et où il ne s'applique pas

Dans `MobileHud._drag_stick()`, c'est-à-dire sur le pouce, et nulle part
ailleurs. C'est une propriété d'un doigt sur du verre, pas du personnage :
un clavier, une manette ou un test qui écrit `move_input` directement n'est
pas corrigé, et ne doit pas l'être.

---

## 3. MULTITOUCH

Inchangé et re-vérifié : stick + SAUTER, stick + COURIR, stick +
interaction, et un second pouce qui n'interrompt pas le premier. Le test
ajouté vérifie en plus que le corridor **reste appliqué** pendant qu'un
second doigt agit.

---

## 4. TESTS AJOUTÉS

Onze vérifications, dans `tests/movement_test.gd`. Cinq portent sur la
fonction de mise en forme (balayage à 0,5° puis 0,125°), six sur le corps
physique piloté par de **vraies touches** dans le vrai dispatcheur.

| | attendu | mesuré |
|---|---|---|
| A — axe avant exact | 0 latéral | corps à **−0.00°** |
| B — dérives ±8° | corrigées | corps à **−0.00°** et **−0.00°** |
| B' — résidu dans tout le corridor | 0 | **0.0000°** |
| C — bord du corridor | pas de rupture | pas à 0,5° : 1.961° ; à 0,125° : 0.491° ; **ratio 0.25** (une discontinuité resterait à ~1.00) ; monotone |
| D — milieu de la transition | entre les deux | 19.5° en → **10.04°** en sortie |
| D' — bord haut sur le corps | progressif | 15° → **−0.00°**, 24° → **24.00°** |
| E — diagonale volontaire 45° | conservée | corps à **45.0°** |
| F — virages forts ±90 / −45 | conservés | **90.0°** et **−45.0°** |
| F' — erreur au-delà de 24° | 0 | **0.0000°** |
| G — vitesse à intensité égale | inchangée | **3.460** / **3.460** / **3.479** m/s (0°, 8°, 45°) |
| H — multitouch | intact | stick tenu à travers un saut et une tape sprint, toujours redressé |

Plus : marche arrière rendue telle quelle, et intensité du stick conservée à
`0.000000` près sur tout le balayage.

**La direction mesurée est celle du `CharacterBody3D`**, projetée sur les
axes de la caméra — pas la valeur du widget. C'est ce qui rend le test
capable d'attraper une erreur de convention.

---

## 5. RÉSULTATS

| suite | 0.2.1 | 0.2.1b |
|---|---|---|
| `tools/benchmark_tests.gd` | 31 / 0 échec | 31 / 0 échec |
| `tests/collision_world_test.gd` | 144 / 0 échec | 144 / 0 échec |
| `tests/world_systems_test.gd` | 17 / 0 échec | 17 / 0 échec |
| `tests/soak_test.gd` | 3 / 0 échec | 3 / 0 échec |
| `tests/movement_test.gd` | 45 / 0 échec | **56 / 0 échec** |

**Régressions : aucune.** Aucun test supprimé, aucun seuil assoupli.

Deux ajustements de mesure, forcés par le changement de vitesse et tous deux
plus stricts ou neutres, jamais plus laxistes :

- l'échantillon « demi-stick » du test de glissement visait `Walking_A` ;
  à 0.45 du nouveau plafond il tombait à 1,66 m/s, juste au-delà du
  changement de démarche à 1,64, et jouait donc `Running_A`. Le clip de
  marche n'était plus testé du tout. L'amplitude passe à 0.34, soit
  1,25 m/s, et `Walking_A` est de nouveau couvert ;
- la vitesse du corps est désormais médianée **sur la même fenêtre** que les
  pieds, au lieu d'être échantillonnée une fois avant. Numérateur et
  dénominateur sur le même intervalle.

Un seuil a été **remplacé** pendant l'écriture, et c'est le seul changement
de test : « le bord du corridor n'est pas une falaise » était d'abord un
plafond arbitraire sur l'écart entre deux échantillons. C'est le mauvais
critère — une bande de 9° qui doit restituer 24° est forcément raide au
milieu, et une rampe raide n'est pas une falaise. Le test compare désormais
l'écart maximal à deux résolutions d'échantillonnage : pour une fonction
continue il diminue proportionnellement (0.25 observé), à travers une
véritable discontinuité il ne diminue pas.

---

## 6. FICHIERS MODIFIÉS

| fichier | rôle |
|---|---|
| `scripts/player/player_movement_config.gd` | WALK 3.8, RUN 5.8, bornes de validation |
| `scripts/ui/stick_shaping.gd` | **nouveau** — le corridor, sans aucune convention en dur |
| `scripts/ui/mobile_hud.gd` | axe avant du widget, réglages exposés, application au drag |
| `tests/movement_test.gd` | 11 vérifications ajoutées |
| `tools/benchmark_tests.gd` | fenêtre de mesure du glissement de pieds, couverture du clip de marche |
| `tools/calibrate_stride.gd` | planchers re-mesurés aux vitesses réelles |
| `docs/GODOT_0.2.1b_MOBILE_TUNING.md` | ce rapport |

Aucun asset. Aucune géométrie. Aucune animation. Aucun système de gameplay.

---

## 7. À RÉGLER SI BESOIN

Tout est exposé dans l'inspecteur, sur le téléphone :

| ressenti | levier |
|---|---|
| « ça dévie encore un peu » | `MobileHud.forward_corridor_deg` ↑ (18–20 max avant de gêner les petits virages) |
| « je ne peux plus corriger finement ma course » | `forward_corridor_deg` ↓ |
| « la sortie du corridor se sent » | `corridor_blend_deg` ↑ |
| vitesses | `scenes/player/PlayerMovement.tres` |

**La validation finale reste celle de l'utilisateur sur Samsung Galaxy A55.**
Aucune performance n'est mesurée ici : cet environnement rend en logiciel.
