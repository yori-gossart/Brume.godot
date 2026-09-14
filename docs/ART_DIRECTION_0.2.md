# DIRECTION ARTISTIQUE 0.2

## Le point de départ, honnêtement

La mission imposait dix packs Quaternius. **Aucun n'était téléchargeable**
(`ASSETS_TO_DOWNLOAD.md`). Ce document décrit donc ce qui a été fait de
l'identité visuelle **avec les assets dont la licence était vérifiable**, et
ce qui reste en attente.

Le style cible ne change pas : **stylized fantasy / semi-cartoon**, un monde
beau, mystérieux, légèrement mélancolique, vivant et dangereux. Ni
photoréalisme, ni voxel, ni chibi extrême.

La cohérence est obtenue par une décision simple : **tous les modèles
d'auteur du projet viennent d'un seul auteur**, Kay Lousberg, en CC0. Trois
packs, une seule main. C'est ce qui empêche le « mélange incohérent de cinq
styles » que la section 3 interdit.

---

## Le joueur n'est plus vert

La section 7 demandait que le vert cesse d'être la couleur par défaut. Le
modèle disponible est un rôdeur à capuche verte, et la tenue modulaire
Quaternius qui aurait permis de simplement changer de vêtement est
indisponible. La couleur est donc changée **dans le shader, par bande de
teinte**.

### Pourquoi ça marche : les atlas ont été mesurés

Chaque personnage partage un atlas 1024² en aplats. Les grappes de couleur
ont été extraites et regroupées par teinte ; voici ce qui est réellement
dans les fichiers :

| Corps | Grappe « tenue » | Teinte | Sat. | Val. | Séparée de la peau par |
| --- | --- | --- | --- | --- | --- |
| Éclaireur (Rogue) | capuche/cape **verte** | 152–164° | 0,87–1,00 | 0,37–0,69 | 130° de teinte |
| Robuste (Barbarian) | étoffe bleu acier | 200–210° | 0,41 | 0,51 | 180° de teinte |
| Longiligne (Mage) | robe violette | 240–250° | 0,40 | 0,41 | 220° de teinte |
| Équipé (Knight) | surcot rouge | 350–360° | 0,56 | 0,95 | **la valeur** (0,95 contre 0,61 du cuir) |

Et le socle commun à tous :

| Grappe | Teinte | Sat. | Val. |
| --- | --- | --- | --- |
| Peau | 21–26° | 0,31–0,53 | 0,78–0,97 |
| Cuir / sangles | 12–19° | 0,54–0,65 | 0,49–0,70 |
| Acier | ~200° | 0,11 | — |

Le vert de la capuche est **seul** à 155° avec une saturation de 0,9 : rien
d'autre dans l'atlas n'en approche. Une bande centrée là repeint la capuche
et la cape, et ne touche ni la peau, ni le cuir, ni l'acier.

La peau et le cuir, eux, se chevauchent en teinte. Ils sont séparés par la
**luminosité** — d'où le plancher de valeur dans
`shaders/character_recolor.gdshader`. C'est aussi ce qui permet de recolorer
le surcot rouge du Knight sans teindre ses sangles.

Chaque bande conserve l'ombrage d'origine : le pixel garde sa clarté
relative et ne change que de teinte et de saturation. Les plis restent des
plis.

### La palette (section 7)

Ocre · Rouille · Bleu ardoise · Beige · Gris ardoise · Bordeaux · Vert de
forêt · Nuit.

Le vert est **présent et disponible**, comme une option parmi huit. Le
joueur démarre en **ocre**.

---

## Les quatre nomades

| | Corps | Teinte 1 | Teinte 2 | Peau | Accessoires | Démarche |
| --- | --- | --- | --- | --- | --- | --- |
| **Éclaireur** | svelte | bleu ardoise | beige | claire | cape | 1,50 m/s |
| **Voyageur** | armuré | bordeaux | ocre | olive | cape | 1,25 m/s |
| **Artisan** | massif | rouille | gris ardoise | ambre | — | 1,40 m/s |
| **Ancien** | longiligne | nuit | vert de forêt | brune | cape | 1,05 m/s |

Quatre corps différents, quatre tenues, quatre teints, deux jeux
d'accessoires, quatre allures. **Aucun n'est distingué par une échelle** —
la suite de tests le vérifie explicitement (`NPCS NOT SCALE VARIANTS`),
parce que la section 13 l'interdit nommément.

L'Éclaireur partage volontairement la silhouette du joueur : la section 12
demande « silhouette similaire au joueur mais tenue/couleur différentes ».

---

## Ce qui n'est pas là, et pourquoi

| Attendu | État |
| --- | --- |
| Corps Homme / Femme (Universal Base Characters) | **absent** — les quatre corps disponibles sont des carrures, pas des genres |
| Coiffures | **absent** — ces modèles n'ont pas de maillage de cheveux séparable ; la rangée est affichée **grisée et légendée** dans l'écran d'apparence |
| Tenues modulaires | **partiel** — les « variantes » se limitent à des jeux d'accessoires (cape, chapeau) |
| Cerf et renard | **absent** — placeholders étiquetés dans la scène |
| Monstre, gobelin, troll | **absent** |

L'écran d'apparence affiche la rangée « CHEVEUX » désactivée avec la raison
écrite dessous. Faire semblant aurait été pire, la cacher aurait laissé
croire que la fonction n'existe pas.

---

## Le monde : composition plutôt que dispersion

La section 16 interdit « un arbre au hasard tous les X mètres ». La
dispersion 0.1 était exactement cela. En 0.2, la forêt est **composée**
(`scripts/world/forest_composition.gd`) :

* **14 peuplements** de trois tailles très différentes — des tailles égales
  donnent du papier peint ;
* des **clairières** percées dans les grands peuplements ;
* des **lisières**, où la densité tombe et où poussent d'autres essences ;
* des **arbres isolés** — les morts, qui doivent être seuls pour se voir ;
* un **bord de chemin** planté, pour que la route ait l'air taillée *dans*
  quelque chose ;
* des **champs de rochers** avec leur propre végétation basse ;
* du **sous-bois** qui ne pousse que sous un couvert.

Chaque essence déclare **où elle appartient**, et l'échantillonneur respecte
ce choix. Résultat : 9 essences d'arbres et 5 de rochers réparties en
~370 instances, en 16 draw calls.

## Éclairage et Brume

Inchangés depuis 0.1, délibérément (§76) : soleil rasant avec ombres en
cascade, remplissage bleuté très faible, brouillard de profondeur violet qui
passe la main à la Brume, et la Brume elle-même en trois rideaux avec
nappes au sol et volutes.

Ce qui change : la Brume a maintenant **sa propre couche physique**
(`HAZARD_FOG`), les PNJ et les animaux la détectent, et ils la fuient.
C'est un petit ajout qui change beaucoup : les gens s'écartent de la ligne
de brume, donc la ligne de brume a l'air mauvaise.

## Réserve honnête

L'étalonnage de la Brume tire toujours vers la brume pâle plutôt que vers le
violet menaçant de la direction artistique. C'est un réglage d'uniformes de
shader, pas une reconstruction, et c'est toujours sur la liste.
