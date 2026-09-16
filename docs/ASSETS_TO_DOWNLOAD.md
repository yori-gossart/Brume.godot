# ASSETS À TÉLÉCHARGER — bloqués par la politique réseau

**Statut : les dix packs Quaternius imposés par la mission 0.2 n'ont pas pu
être intégrés. Aucun n'est téléchargeable depuis cet environnement.**

Ce n'est pas une estimation : la passerelle réseau répond **403 au CONNECT**,
c'est-à-dire un refus de politique avant toute requête HTTP.

```
403 CONNECT  quaternius.com:443
403 CONNECT  www.quaternius.com:443
403 CONNECT  quaternius.itch.io:443
403 CONNECT  itch.io:443
403 CONNECT  poly.pizza:443
403 CONNECT  sketchfab.com:443
403 CONNECT  opengameart.org:443
403 CONNECT  kenney.nl:443
403 CONNECT  cdn.jsdelivr.net:443
```

Seul GitHub est servi (lecture git anonyme). **Quaternius n'a pas de dépôt
GitHub officiel** — recherche faite, 49 dépôts contenant « Quaternius », tous
des ports et miroirs tiers, aucun appartenant à Tomás Laulhé.

## Pourquoi je n'ai pas pris un miroir GitHub

Des miroirs tiers des packs Quaternius existent et sont, eux, téléchargeables.
Je ne les ai pas utilisés, pour une raison qui est **votre propre règle**,
écrite dans `ASSET_LICENSES.md` de Fog Nomad three.js et reconduite en 0.1 :

> « Un asset dont la licence n'a pas été vérifiée n'entre pas. Vérifiée
> signifie lue chez l'auteur, pas déduite d'un miroir ou d'un article de
> blog. […] **y compris via un miroir qui les annonce comme CC0.** »

et la section 4 de la mission 0.2 : « **Toujours revalider la licence
officielle avant intégration.** » Le README d'un miroir n'est pas la licence
officielle. Un miroir peut être périmé, modifié ou relicencié, et Fog Nomad
est un projet à visée commerciale.

**C'est une décision, pas une fatalité.** Si vous voulez que j'utilise un
miroir précis, ou si vous téléchargez les packs vous-même, dites-le : tout le
pipeline est déjà prêt à les recevoir (voir plus bas).

---

## Ce qu'il faut télécharger

Source officielle unique : **https://quaternius.com/packs.html**
(auteur : Tomás Laulhé — Quaternius. Licence annoncée : **CC0 1.0**.
À relire chez l'auteur au moment du téléchargement.)

Format à préférer : **glTF / GLB**. Godot les importe nativement, y compris
l'éditeur Android. Éviter le FBX : il exige un convertisseur desktop et
casserait la contrainte « ouvrable depuis le téléphone ».

| # | Pack | Sert à | Destination |
| --- | --- | --- | --- |
| 1 | **Universal Base Characters** | corps du joueur et des PNJ (Regular Male / Regular Female) | `assets/quaternius/characters/` |
| 2 | **Modular Character Outfits — Fantasy** | tenue d'éclaireur, variantes légères | `assets/quaternius/outfits/` |
| 3 | **Universal Animation Library** | idle, walk, jog, sprint, directionnel, **swim** | `assets/quaternius/animations/` |
| 4 | **Universal Animation Library 2** | interactions, melee, parkour, farming (plus tard) | `assets/quaternius/animations/` |
| 5 | **Stylized Nature MegaKit** | 8-12 arbres, 6-10 rochers, 8-15 plantes | `assets/quaternius/nature/` |
| 6 | **Ultimate Animated Animal Pack** | **cerf** et **renard** (ou loup) | `assets/quaternius/animals/` |
| 7 | **Medieval Village MegaKit** | cabane, poste d'éclaireur, murs, portes, toits, escaliers | `assets/quaternius/buildings/` |
| 8 | **Ultimate Modular Ruins Pack** | ruines modulaires | `assets/quaternius/ruins/` |
| 9 | **Fantasy Props MegaKit** | coffre, caisse, livre, outil, potion, objets de camp | `assets/quaternius/props/` |
| 10 | **Ultimate Monsters** | créature fantasy pour la showcase | `assets/quaternius/monsters/` |
| 11 | **Ultimate Animated Character Pack** | gobelin (§49) | `assets/quaternius/monsters/` |

Les dossiers existent déjà dans le dépôt, chacun avec un `README.md` qui
rappelle ce qu'on y attend.

## Ce qu'il faut faire en les déposant

1. Ne copier que les fichiers réellement utilisés (§66) — pas les ZIP entiers.
2. Copier **le fichier de licence livré avec le pack** à côté des modèles.
3. Compléter `docs/ASSET_MANIFEST.md` : une ligne par fichier intégré.
4. Renseigner les tables de données, **pas le code** :
   - arbres / rochers / plantes → `SPECIES` en tête de `scripts/world/scatter.gd`
   - corps, tenues, couleurs → `scripts/characters/appearance_catalog.gd`
   - objets → les `.tres` de `assets/data/items/`
   - animaux → `scripts/animals/animal_species.gd`

Le pipeline 0.2 est **data-driven exprès pour ça** : intégrer les packs doit
être un changement de données, pas un changement de code.

---

## Conséquences sur la mission 0.2

Bloqué, et documenté comme tel :

| Section | Sujet | Marqueur |
| --- | --- | --- |
| §5-8 | corps et tenues Quaternius | `QUATERNIUS_PACKS_UNREACHABLE` |
| §9 | Universal Animation Library | `QUATERNIUS_PACKS_UNREACHABLE` |
| §15-16 | Stylized Nature MegaKit | `QUATERNIUS_PACKS_UNREACHABLE` |
| §36 | animation de nage retargetée | `SWIM_ANIMATION_PARTIAL` |
| §37 | cerf et renard | `ANIMAL_ASSET_BLOCKED` |
| §40 | Medieval Village MegaKit | `QUATERNIUS_PACKS_UNREACHABLE` |
| §42 | Ultimate Modular Ruins | `RUINS_PACK_UNREACHABLE` |
| §48 | Ultimate Monsters | `MONSTER_ASSET_BLOCKED` |
| §49 | gobelin | `GOBLIN_ASSET_IMPORT_BLOCKED` |
| §50 | troll | `TROLL_ASSET_PENDING` |

**Non bloqué, et livré dans cette version :** les portes 1 à 5 du §61 —
convention de layers, arbres et rochers solides, bâtiments/portes/ruines
solides, interaction en mouvement, système de surfaces. C'est précisément
l'ordre que la mission impose, et il ne dépend d'aucun pack.

Conformément au §67, **aucun asset n'a été recréé en primitives pour
remplacer un pack manquant**. Ce qui est construit en géométrie Godot
(cabane, tour, ruine, pont, feu de camp) l'est parce que c'est de
l'architecture de niveau, pas un modèle d'auteur — et c'est exactement le
repli que le §42 autorise déjà pour les ruines.
