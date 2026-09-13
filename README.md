# Fog Nomad — Godot Production Benchmark 0.1

Un banc d'essai pour répondre à **une** question : Godot nous ferait-il
gagner assez en rendu, en environnement, en collisions, en physique et en
ergonomie mobile pour justifier de quitter Three.js ?

Ce dépôt est **séparé** de Fog Nomad 0.7.2 (three.js), qui reste la
référence de gameplay et n'est modifié en aucune façon.

> 📄 **Le rapport, les verdicts et l'auto-audit : [`docs/BENCHMARK_REPORT.md`](docs/BENCHMARK_REPORT.md)**
> 📱 **Ouvrir sur téléphone : [`docs/ANDROID_PHONE_WORKFLOW.md`](docs/ANDROID_PHONE_WORKFLOW.md)**
> ⚖️ **Licences des assets : [`docs/ASSET_LICENSES.md`](docs/ASSET_LICENSES.md)**

| | |
| --- | --- |
| ![La Brume](docs/screenshots/brume.jpg) | ![Tour-balise et nage](docs/screenshots/beacon_and_swim.jpg) |

---

## Contraintes tenues

| | |
| --- | --- |
| Moteur | **Godot 4.3**, renderer **Mobile** (jamais Forward+) |
| Langage | **GDScript uniquement** — pas de C#, pas de GDExtension, pas de plugin |
| Orientation | **Portrait**, fenêtre de référence 720 × 1280 |
| Scène | **une seule**, 280 × 280 m, `scenes/BenchmarkWorld.tscn` |
| Dépendances externes | **aucune** |
| Cible de test | Samsung Galaxy A55, éditeur Godot pour Android |

Pas de monde procédural, pas de chunks, pas de prologue, pas d'inventaire,
pas de craft : ce benchmark compare la **qualité de production**, pas le
streaming.

## Lancer

Importez le projet dans Godot 4.3+ et appuyez sur **PLAY**. La scène
principale est déjà réglée.

En ligne de commande :

```bash
godot --path . --rendering-method mobile --resolution 720x1280
```

## Vérifier

La suite de tests pilote la vraie scène à travers la vraie physique et
mesure des nombres — elle n'affirme jamais qu'une chose marche parce qu'un
nœud existe :

```bash
godot --headless --path . --script tools/benchmark_tests.gd
```

29 vérifications : déplacement, course, orientation du modèle, glissement
des pieds mesuré au pied posé, collisions arbre / rocher / bâtiment,
ramassage en pleine course, détection d'eau, patauger, nage, distinction et
navigation du NPC, fuite de l'animal, Brume, et les deux niveaux de qualité.

## Organisation

```
scenes/            BenchmarkWorld.tscn + player/ world/ npc/ animals/
                   environment/ fog/ ui/
scripts/           toute la logique, GDScript
  terrain_data.gd    LA fonction de terrain — tout le reste en dépend
  locomotion_rig.gd  AnimationTree partagé joueur/NPC
shaders/           terrain, eau, brume (rideau + nappe), cristal, volutes
assets/            characters/ environment/ materials/ audio/
docs/              rapport, licences, guide téléphone
tools/             suite de tests, calibrations, captures
```

Le terrain, l'eau, le maillage de navigation, la végétation, les deux
bâtiments et toute la Brume sont **construits par script au chargement**
(≈ 510 ms), à partir d'une seule fonction de hauteur. Ce n'est pas de la
génération procédurale de monde — pas de graine, pas de chunks, pas de
streaming — c'est une scène fixe écrite en formules plutôt qu'en quarante
mille sommets, pour qu'elle reste **ouvrable et modifiable sur un
téléphone**.

## Produire l'archive

```bash
tools/make_zip.sh
```

Produit `build/fog-nomad-godot-benchmark-0.1.zip`, sans `.godot/` ni cache,
importable directement par Godot.

## Licence

Code de ce dépôt : à la discrétion du projet Fog Nomad.
Assets : **CC0 1.0** (KayKit, par Kay Lousberg) — usage commercial autorisé,
licences livrées à côté des fichiers. Détail dans `docs/ASSET_LICENSES.md`.
