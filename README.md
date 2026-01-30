# 📊 deces-dataprep

Projet de préparation et d'indexation des données du fichier des personnes décédées de l'INSEE. Ce projet utilise l'écosystème [matchID](https://github.com/matchid-project) pour transformer et indexer les données de décès dans Elasticsearch.

🔗 **Données source** : [Fichier des personnes décédées sur data.gouv.fr](https://www.data.gouv.fr/fr/datasets/fichier-des-personnes-decedees/)

---

## 📋 Table des matières

- [Vue d'ensemble](#-vue-densemble)
- [Prérequis](#-prérequis)
- [Installation](#-installation)
- [Démarrage rapide](#-démarrage-rapide)
- [Workflows](#-workflows)
- [Commandes disponibles](#-commandes-disponibles)
- [Configuration](#-configuration)
- [Traitements des données](#-traitements-des-données)
- [Déploiement distant](#-déploiement-distant)
- [Dépannage](#-dépannage)
- [License](#-license)

---

## 🏗️ Vue d'ensemble

Le projet [`deces-dataprep`](.) orchestre le pipeline complet de traitement des données de décès depuis data.gouv.fr jusqu'à la création d'index Elasticsearch optimisés pour la recherche.

### Architecture du pipeline

```
Data.gouv.fr → Stockage S3 → Traitement matchID → Index Elasticsearch → Sauvegarde
```

### Composants principaux

| Composant | Description | Fichier |
|-----------|-------------|---------|
| **Source** | Fichiers texte à largeur fixe de l'INSEE | [`deces_src.yml`](projects/deces-dataprep/datasets/deces_src.yml:1) |
| **Recette** | Pipeline de transformation des données | [`deces_dataprep.yml`](projects/deces-dataprep/recipes/deces_dataprep.yml:1) |
| **Destination** | Index Elasticsearch avec mappings optimisés | [`deces_index.yml`](projects/deces-dataprep/datasets/deces_index.yml:1) |
| **Orchestration** | Automatisation via Makefile | [`Makefile`](Makefile:1) |

### Traitements appliqués

- ✅ Normalisation des noms et prénoms (casse, format)
- ✅ Validation et correction des dates de naissance et décès
- ✅ Enrichissement géographique (communes, départements, pays)
- ✅ Filtrage des oppositions RGPD
- ✅ Calcul de l'âge au décès
- ✅ Historique des codes INSEE (fusions de communes)
- ✅ Géocodage (coordonnées GPS)
- ✅ Mapping des anciennes colonies françaises

---

## ✅ Prérequis

### Logiciels requis

- **Docker** (≥ 20.10) et **Docker Compose** (≥ 2.0)
- **Git** (≥ 2.0)
- **Make** (GNU Make ≥ 4.0)
- **Bash** (shell par défaut)

### Ressources système recommandées

| Environnement | RAM | Espace disque | CPU |
|---------------|-----|---------------|-----|
| **Développement** | 8 GB | 20 GB | 4 cœurs |
| **Production** | 16 GB | 100 GB | 8 cœurs |

### Ports utilisés

- **8081** : Interface MatchID (frontend)
- **9200** : Elasticsearch
- **5000** : API Backend MatchID

### Accès S3

Le projet supporte deux connecteurs S3 :

- **Développement local** : Utilise le backend intégré ou un stockage local
- **Production** : Nécessite des clés d'accès S3 (Scaleway, AWS, etc.)

---

## 🔧 Installation

### 1. Cloner le projet

```bash
git clone https://github.com/matchid-project/deces-dataprep.git
cd deces-dataprep
```

### 2. Configuration initiale

```bash
make config
```

Cette commande :
- Clone le [backend matchID](https://github.com/matchid-project/backend) dans le répertoire [`backend/`](Makefile:136)
- Copie les fichiers de configuration ([`artifacts`](Makefile:139), [`docker-compose-local.yml`](Makefile:140))
- Configure les variables d'environnement
- Vérifie les prérequis système

### 3. Configuration S3 (optionnel)

Pour utiliser un stockage S3 externe :

```bash
export STORAGE_ACCESS_KEY=votre_cle_acces
export STORAGE_SECRET_KEY=votre_cle_secrete
export REPOSITORY_BUCKET=votre-bucket-elasticsearch
```

---

## 🚀 Démarrage rapide

### Développement local

```bash
# Démarrer l'environnement complet
make dev

# Accès aux services :
# - Interface MatchID : http://localhost:8081
# - Elasticsearch : http://localhost:9200
```

L'interface MatchID permet de :
- Visualiser et tester les recettes de traitement
- Monitorer l'avancement du traitement
- Inspecter les données transformées
- Déboguer les transformations

### Traitement complet automatique

```bash
# Traitement de bout en bout
make all
```

Cette commande exécute séquentiellement :
1. **Configuration** ([`all-step0`](Makefile:278)) : Initialisation de l'environnement
2. **Traitement** ([`all-step1`](Makefile:281)) : Synchronisation et transformation des données
3. **Surveillance** ([`watch-run`](Makefile:191)) : Monitoring en temps réel
4. **Sauvegarde** ([`all-step2`](Makefile:284)) : Backup vers le stockage S3

⏱️ **Durée estimée** : 1h30 à 10h selon la taille des données et les ressources système.

### Arrêt des services

```bash
# Arrêt gracieux
make dev-stop

# Arrêt complet avec nettoyage
make down
```

---

## 🔄 Workflows

### Workflow de développement

```bash
# 1. Démarrer l'environnement de développement
make dev

# 2. Accéder à l'interface MatchID
# http://localhost:8081

# 3. Tester une recette sur un échantillon de données
# (via l'interface ou les commandes backend)

# 4. Arrêter l'environnement
make dev-stop
```

### Workflow de traitement complet

```bash
# 1. Synchroniser les données depuis data.gouv.fr
make datagouv-to-storage

# 2. Générer le tag de version des données
make data-tag

# 3. Vérifier si un backup existe déjà
make repository-check

# 4. Lancer le traitement (si pas de backup existant)
make recipe-run

# 5. Surveiller l'avancement
make watch-run

# 6. Sauvegarder le résultat
make repository-push
```

### Workflow de restauration

```bash
# 1. Vérifier les backups disponibles
make repository-check

# 2. Restaurer depuis le backup
make repository-restore

# 3. Démarrer les services
make up

# 4. Vérifier le nombre d'enregistrements
docker exec -it matchid-elasticsearch curl localhost:9200/_cat/indices
```

### Workflow de mise à jour incrémentale

```bash
# 1. Synchroniser uniquement les nouveaux fichiers
make datagouv-to-storage

# 2. Vérifier la version des données
make data-tag
cat data-tag

# 3. Lancer le traitement si nouvelle version
make full
```

---

## 📝 Commandes disponibles

### Gestion de l'environnement

| Commande | Description |
|----------|-------------|
| [`make config`](Makefile:65) | Configuration initiale et vérification des prérequis |
| [`make dev`](Makefile:148) | Lance l'environnement complet (Elasticsearch + Backend + Frontend) |
| [`make dev-stop`](Makefile:152) | Arrête tous les services de développement |
| [`make up`](Makefile:157) | Lance Elasticsearch et le backend uniquement (sans frontend) |
| [`make down`](Makefile:266) | Arrête tous les services |
| [`make clean`](Makefile:271) | Nettoyage complet (⚠️ supprime tout) |

### Traitement des données

| Commande | Description | Durée estimée |
|----------|-------------|---------------|
| [`make all`](Makefile:286) | ✨ Traitement complet automatique | 1h30 - 10h |
| [`make full`](Makefile:183) | Traitement avec vérifications préalables | 1h - 8h |
| [`make recipe-run`](Makefile:161) | Exécution de la recette de traitement | 1h - 8h |
| [`make watch-run`](Makefile:191) | 👀 Surveillance du traitement en cours | Variable |
| [`make backend-clean-logs`](Makefile:188) | Nettoyage des logs de traitement | Instantané |

### Synchronisation des données

| Commande | Description |
|----------|-------------|
| [`make datagouv-to-storage`](Makefile:70) | 📥 Synchronisation depuis data.gouv.fr vers S3 |
| [`make datagouv-to-s3`](Makefile:76) | Alias pour `datagouv-to-storage` |
| [`make datagouv-to-upload`](Makefile:79) | Téléchargement local dans `backend/upload/` |
| [`make data-tag`](Makefile:90) | Génération du tag de version des données |

### Sauvegarde et restauration

| Commande | Description | Méthode |
|----------|-------------|---------|
| [`make repository-push`](Makefile:249) | 💾 Sauvegarde via repository ES (recommandé) | Repository |
| [`make repository-restore`](Makefile:212) | ♻️ Restauration depuis repository ES | Repository |
| [`make repository-check`](Makefile:122) | Vérification des snapshots disponibles | Repository |
| [`make repository-config`](Makefile:108) | Configuration du repository S3 | Repository |
| [`make backup`](Makefile:225) | Sauvegarde classique (tar) | Backup |
| [`make backup-push`](Makefile:237) | Envoi du backup vers S3 | Backup |
| [`make backup-restore`](Makefile:206) | Restauration depuis backup classique | Backup |
| [`make backup-check`](Makefile:106) | Vérification des backups classiques | Backup |

**💡 Recommandation** : Utilisez la méthode `repository` qui est plus rapide et efficace pour les gros volumes.

### Déploiement distant (Cloud)

| Commande | Description |
|----------|-------------|
| [`make remote-config`](Makefile:291) | Configuration du serveur distant |
| [`make remote-deploy`](Makefile:298) | Déploiement sur le serveur distant |
| [`make remote-step1`](Makefile:304) | Exécution du traitement à distance |
| [`make remote-watch`](Makefile:312) | Surveillance du traitement distant |
| [`make remote-step2`](Makefile:318) | Sauvegarde à distance |
| [`make remote-clean`](Makefile:325) | Nettoyage du serveur distant |
| [`make remote-all`](Makefile:331) | Workflow complet distant |

### Utilitaires

| Commande | Description |
|----------|-------------|
| [`make dataprep-version`](Makefile:92) | Affiche la version du dataprep (hash) |

---

## ⚙️ Configuration

### Variables d'environnement principales

#### Configuration Elasticsearch

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| [`ES_INDEX`](Makefile:15) | `deces` | Nom de l'index Elasticsearch |
| [`ES_NODES`](Makefile:16) | `1` | Nombre de nœuds Elasticsearch |
| [`ES_MEM`](Makefile:17) | `1024m` | Mémoire allouée à Elasticsearch |
| [`ES_VERSION`](Makefile:18) | `8.6.1` | Version d'Elasticsearch |
| [`ES_PRELOAD`](Makefile:20) | `[]` | Fichiers à précharger en mémoire |

#### Configuration du traitement

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| [`RECIPE`](Makefile:22) | `deces_dataprep` | Nom de la recette à exécuter |
| [`CHUNK_SIZE`](Makefile:21) | `10000` | Taille des lots de traitement |
| [`RECIPE_THREADS`](Makefile:23) | `4` | Threads pour le traitement des données |
| [`RECIPE_QUEUE`](Makefile:24) | `1` | Longueur de la queue d'écriture |
| [`ES_THREADS`](Makefile:25) | `2` | Threads pour l'indexation Elasticsearch |
| [`TIMEOUT`](Makefile:26) | `2520` | Timeout en secondes (42 minutes) |
| [`ERR_MAX`](Makefile:19) | `20` | Nombre max d'erreurs tolérées |

#### Configuration S3

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| [`STORAGE_BUCKET`](Makefile:30) | `fichier-des-personnes-decedees` | Bucket de stockage des données |
| [`REPOSITORY_BUCKET`](Makefile:31) | `${STORAGE_BUCKET}-elasticsearch` | Bucket pour les snapshots ES |
| [`DATAGOUV_CONNECTOR`](Makefile:29) | `s3` | Type de connecteur (s3/upload) |
| `STORAGE_ACCESS_KEY` | - | Clé d'accès S3 (si nécessaire) |
| `STORAGE_SECRET_KEY` | - | Clé secrète S3 (si nécessaire) |

#### Configuration des fichiers

| Variable | Valeur | Description |
|----------|--------|-------------|
| [`FILES_TO_SYNC`](Makefile:39) | `fichier-opposition-deces-.*.csv(.gz)?|deces-.*.txt(.gz)?` | Fichiers à synchroniser |
| [`FILES_TO_SYNC_FORCE`](Makefile:40) | `fichier-opposition-deces-.*.csv(.gz)?` | Fichiers forcés (oppositions RGPD) |
| [`FILES_TO_PROCESS`](Makefile:42) | `deces-([0-9]{4}|2025-m[0-9]{2}).txt.gz` | Fichiers à traiter |

#### Configuration Cloud (Scaleway)

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| [`SCW_FLAVOR`](Makefile:57) | `PRO2-M` | Type d'instance Scaleway |
| [`SCW_VOLUME_TYPE`](Makefile:58) | `sbs_15k` | Type de volume |
| [`SCW_VOLUME_SIZE`](Makefile:59) | `50000000000` | Taille du volume (50 GB) |
| [`SCW_IMAGE_ID`](Makefile:60) | `8e7f9833...` | ID de l'image de base |

### Exemples de configuration

#### Configuration haute performance

```bash
export ES_MEM=4096m
export ES_NODES=2
export RECIPE_THREADS=8
export ES_THREADS=4
export CHUNK_SIZE=20000

make recipe-run
```

#### Configuration économique (ressources limitées)

```bash
export ES_MEM=512m
export RECIPE_THREADS=2
export ES_THREADS=1
export CHUNK_SIZE=5000

make recipe-run
```

#### Configuration avec S3 externe

```bash
export DATAGOUV_CONNECTOR=s3
export STORAGE_ACCESS_KEY=VOTRE_CLE
export STORAGE_SECRET_KEY=VOTRE_SECRET
export STORAGE_BUCKET=mon-bucket-deces
export REPOSITORY_BUCKET=mon-bucket-deces-elasticsearch

make full
```

#### Configuration avec stockage local

```bash
export DATAGOUV_CONNECTOR=upload

# Les fichiers seront téléchargés dans backend/upload/
make datagouv-to-upload
make recipe-run
```

### Fichiers de configuration

| Fichier | Description |
|---------|-------------|
| [`Makefile`](Makefile:1) | Configuration principale et orchestration |
| [`artifacts`](Makefile:63) | Variables d'environnement persistées |
| [`docker-compose-local.yml`](docker-compose-local.yml:1) | Configuration Docker locale |
| [`projects/deces-dataprep/recipes/deces_dataprep.yml`](projects/deces-dataprep/recipes/deces_dataprep.yml:1) | Recette de transformation |
| [`projects/deces-dataprep/datasets/deces_src.yml`](projects/deces-dataprep/datasets/deces_src.yml:1) | Configuration source |
| [`projects/deces-dataprep/datasets/deces_index.yml`](projects/deces-dataprep/datasets/deces_index.yml:1) | Mapping Elasticsearch |

---

## 🔬 Traitements des données

### Format source

Les données sources sont des fichiers texte à largeur fixe ([`deces_src.yml`](projects/deces-dataprep/datasets/deces_src.yml:1)) :

| Position | Largeur | Champ | Description |
|----------|---------|-------|-------------|
| 0-80 | 80 | `NOM_PRENOMS` | Nom et prénoms (format : `NOM*PRENOMS/`) |
| 80-81 | 1 | `SEXE` | Sexe (1=M, 2=F) |
| 81-89 | 8 | `DATE_NAISSANCE` | Date de naissance (YYYYMMDD) |
| 89-94 | 5 | `CODE_INSEE_NAISSANCE` | Code INSEE commune naissance |
| 94-124 | 30 | `COMMUNE_NAISSANCE` | Libellé commune de naissance |
| 124-154 | 30 | `PAYS_NAISSANCE` | Libellé pays de naissance |
| 154-162 | 8 | `DATE_DECES` | Date de décès (YYYYMMDD) |
| 162-167 | 5 | `CODE_INSEE_DECES` | Code INSEE commune décès |
| 167-177 | 10 | `NUM_DECES` | Numéro d'acte de décès |

### Pipeline de transformation

La recette [`deces_dataprep.yml`](projects/deces-dataprep/recipes/deces_dataprep.yml:1) applique les transformations suivantes :

#### 1. Identification et normalisation initiale

- Génération d'un identifiant unique (`UID`) basé sur Blake3
- Normalisation des caractères spéciaux
- Extraction du nom et des prénoms

#### 2. Filtrage RGPD

- Jointure avec le fichier des oppositions RGPD
- Suppression des enregistrements avec opposition
- Conservation de la confidentialité

#### 3. Traitement des dates

- Validation et correction des dates invalides
- Conversion au format standard (`YYYY/MM/DD`)
- Gestion des cas limites (29 février, jours > 31, etc.)
- Calcul de l'âge au décès

```python
# Exemple de correction de date
20250231 → 20250301  # 31 février → 1er mars
19001301 → 19011201  # mois 13 → décembre suivant
```

#### 4. Enrichissement géographique

##### Naissance

- Mapping des codes INSEE historiques (fusions de communes)
- Jointure avec le référentiel des communes françaises
- Ajout des coordonnées GPS (`GEOPOINT_NAISSANCE`)
- Gestion des anciennes colonies :
  - Algérie → Code pays 99352
  - Mayotte → Conversion 985XX → 976XX
  - Autres colonies → Mapping vers pays actuels

##### Décès

- Même enrichissement que pour la naissance
- Historique des codes INSEE
- Géolocalisation

#### 5. Normalisation finale

- Mise en forme des noms/prénoms (Title Case)
- Création de champs de recherche optimisés :
  - `PRENOMS_NOM` : Prénoms + Nom (lowercase)
  - `PRENOM_NOM` : Premier prénom + Nom (lowercase)
- Conversion du sexe (2 → F, 1 → M)

### Champs produits

L'index Elasticsearch final ([`deces_index.yml`](projects/deces-dataprep/datasets/deces_index.yml:1)) contient :

#### Identification

- `UID` : Identifiant unique (12 caractères)
- `SOURCE` : Nom du fichier source
- `SOURCE_LINE` : Numéro de ligne dans le fichier source

#### Identité

- `NOM`, `PRENOM`, `PRENOMS` : Identité (texte + keyword)
- `PRENOMS_NOM`, `PRENOM_NOM` : Champs de recherche optimisés
- `SEXE` : M ou F

#### Naissance

- `DATE_NAISSANCE` : Date brute
- `DATE_NAISSANCE_NORM` : Date normalisée (format date)
- `CODE_INSEE_NAISSANCE` : Code INSEE actuel
- `CODE_INSEE_NAISSANCE_HISTORIQUE` : Codes historiques
- `COMMUNE_NAISSANCE` : Libellé(s) de la commune
- `CODE_POSTAL_NAISSANCE` : Code(s) postal
- `DEPARTEMENT_NAISSANCE` : Code département
- `PAYS_NAISSANCE` : Pays (texte + keyword)
- `PAYS_NAISSANCE_CODEISO3` : Code ISO3 du pays
- `GEOPOINT_NAISSANCE` : Coordonnées GPS (geo_point)

#### Décès

- `DATE_DECES` : Date brute
- `DATE_DECES_NORM` : Date normalisée (format date)
- `AGE_DECES` : Âge au décès (en années)
- `CODE_INSEE_DECES` : Code INSEE actuel
- `CODE_INSEE_DECES_HISTORIQUE` : Codes historiques
- `COMMUNE_DECES` : Libellé(s) de la commune
- `CODE_POSTAL_DECES` : Code(s) postal
- `DEPARTEMENT_DECES` : Code département
- `PAYS_DECES` : Pays (texte + keyword)
- `PAYS_DECES_CODEISO3` : Code ISO3 du pays
- `GEOPOINT_DECES` : Coordonnées GPS (geo_point)
- `NUM_DECES` : Numéro d'acte (9 caractères)

### Analyseurs Elasticsearch

L'index utilise des analyseurs personnalisés pour optimiser la recherche :

- **`norm`** : Normalisation (suppression accents, lowercase, espaces)
- **`autocomplete_analyzer`** : Edge n-grams pour l'autocomplétion (2-10 caractères)
- **Index prefixes** : Sur les dates pour recherches partielles (YYYY, YYYYMM)

---

## ☁️ Déploiement distant

### Workflow distant complet

```bash
# 1. Configuration du serveur distant (Scaleway)
make remote-config

# 2. Déploiement sur le serveur
make remote-deploy

# 3. Exécution du traitement à distance
make remote-step1

# 4. Surveillance du traitement
make remote-watch

# 5. Sauvegarde
make remote-step2

# 6. Nettoyage du serveur
make remote-clean
```

Ou en une seule commande :

```bash
make remote-all
```

### Configuration requise

```bash
# Variables Scaleway
export SCW_FLAVOR=PRO2-M              # Type d'instance
export SCW_VOLUME_SIZE=50000000000    # 50 GB
export SCW_VOLUME_TYPE=sbs_15k        # SSD haute performance

# Variables S3
export STORAGE_ACCESS_KEY=votre_cle
export STORAGE_SECRET_KEY=votre_secret

# Lancer le déploiement
make remote-all
```

### Mise à jour de l'image de base

Pour créer une nouvelle image de base avec les dépendances préchargées :

```bash
make update-base-image
```

Cette commande :
1. Déploie une instance
2. Met à jour les paquets système
3. Précharge les images Docker (Python, Elasticsearch)
4. Crée un snapshot Scaleway
5. Met à jour le [`SCW_IMAGE_ID`](Makefile:60) dans le Makefile

---

## 🔧 Dépannage

### Problèmes courants

#### Erreur de mémoire Elasticsearch

**Symptôme** : `OutOfMemoryError` dans les logs Elasticsearch

**Solution** :
```bash
# Augmenter la mémoire allouée
make recipe-run ES_MEM=2048m

# Ou modifier les limites Docker
# Dans backend/docker-compose.yml, section elasticsearch.mem_limit
```

#### Timeout de traitement

**Symptôme** : Le traitement s'arrête avant la fin

**Solution** :
```bash
# Augmenter le timeout (en secondes)
make watch-run TIMEOUT=7200  # 2 heures
```

#### Trop d'erreurs dans le traitement

**Symptôme** : Message "Ooops count exceeds ERR_MAX"

**Solution** :
```bash
# Vérifier les logs
ls -la backend/log/*deces_dataprep*

# Augmenter le seuil d'erreurs
make recipe-run ERR_MAX=50

# Nettoyer et relancer
make backend-clean-logs
make recipe-run
```

#### Port déjà utilisé

**Symptôme** : Erreur "port 8081/9200 already in use"

**Solution** :
```bash
# Vérifier les processus sur les ports
netstat -tlnp | grep -E ':(8081|9200|5000)'

# Arrêter les services existants
make down

# Ou tuer le processus spécifique
sudo kill -9 $(lsof -ti:8081)
```

#### Problème de permissions

**Symptôme** : Erreur "Permission denied" lors du nettoyage

**Solution** :
```bash
# Le nettoyage nécessite sudo
sudo make clean

# Ou changer les permissions des fichiers Elasticsearch
sudo chown -R $USER:$USER backend/
```

#### Backup/Repository S3 échoue

**Symptôme** : Erreur lors de la sauvegarde vers S3

**Solution** :
```bash
# Vérifier les credentials
echo $STORAGE_ACCESS_KEY
echo $STORAGE_SECRET_KEY

# Reconfigurer le repository
rm repository-config
make repository-config

# Vérifier la connexion S3
make repository-check
```

#### Données corrompues

**Symptôme** : Données manquantes ou incorrectes après traitement

**Solution** :
```bash
# Nettoyer complètement
make clean

# Resynchroniser les données
make datagouv-to-storage

# Vérifier la version
make data-tag
cat data-tag

# Relancer le traitement
make all
```

### Vérifications de santé

```bash
# 1. Vérifier l'état d'Elasticsearch
curl -s http://localhost:9200/_cat/health

# 2. Vérifier le nombre de documents indexés
curl -s http://localhost:9200/_cat/indices | grep deces

# 3. Vérifier les logs de traitement
tail -f backend/log/*deces_dataprep*.log

# 4. Vérifier l'utilisation des ressources
docker stats

# 5. Tester une recherche simple
curl -X GET "http://localhost:9200/deces/_search?q=NOM:MARTIN&size=1&pretty"
```

### Logs et diagnostic

```bash
# Logs Elasticsearch
docker logs matchid-elasticsearch

# Logs Backend
docker logs matchid-backend

# Logs Frontend
docker logs matchid-frontend

# Logs de la recette
ls -lh backend/log/
cat backend/log/*deces_dataprep*.log
```

### Nettoyage progressif

```bash
# Nettoyage léger (logs uniquement)
make backend-clean-logs

# Nettoyage moyen (arrêt services + données temporaires)
make down
rm -f recipe-run full watch-run backup*

# Nettoyage complet (⚠️ supprime tout)
sudo make clean
```

---

## 📚 Documentation complémentaire

### Ressources matchID

- [Documentation officielle matchID](https://matchid-project.github.io/)
- [Backend matchID](https://github.com/matchid-project/backend)
- [Frontend matchID](https://github.com/matchid-project/frontend)

### Données INSEE

- [Fichier des personnes décédées](https://www.data.gouv.fr/fr/datasets/fichier-des-personnes-decedees/)
- [Documentation du format](https://www.insee.fr/fr/information/4190491)

### Technologies utilisées

- [Elasticsearch 8.6](https://www.elastic.co/guide/en/elasticsearch/reference/8.6/index.html)
- [Pandas](https://pandas.pydata.org/docs/)
- [Docker Compose](https://docs.docker.com/compose/)

---

## 📄 License

Ce projet est sous licence [GNU Lesser General Public License v3.0](LICENSE).

---

## 💡 Conseils et bonnes pratiques

### Performance

- ⚡ **Multi-threading** : Ajustez [`RECIPE_THREADS`](Makefile:23) et [`ES_THREADS`](Makefile:25) selon vos CPU
- 💾 **Mémoire** : Allouez suffisamment de RAM à Elasticsearch via [`ES_MEM`](Makefile:17)
- 📦 **Chunk size** : Réduisez [`CHUNK_SIZE`](Makefile:21) si vous manquez de mémoire
- 🔄 **Queue** : Augmentez [`RECIPE_QUEUE`](Makefile:24) pour paralléliser écriture/traitement

### Sécurité

- 🔐 **Credentials S3** : Ne jamais committer les clés d'accès
- 🔒 **Variables d'environnement** : Utilisez un fichier `.env` ou un gestionnaire de secrets
- 🛡️ **RGPD** : Les oppositions sont automatiquement filtrées

### Sauvegarde

- 📸 **Repository** : Préférez la méthode repository pour les gros volumes
- ⏰ **Fréquence** : Sauvegardez après chaque traitement complet réussi
- ✅ **Vérification** : Testez régulièrement la restauration

### Monitoring

- 📊 **watch-run** : Surveillez le traitement en temps réel
- 📝 **Logs** : Consultez les logs en cas d'erreur
- 🔍 **Elasticsearch** : Vérifiez régulièrement la santé du cluster

### Développement

- 🧪 **Tests** : Testez vos modifications sur des échantillons via l'interface matchID
- 📚 **Documentation** : Documentez vos changements dans la recette
- 🔄 **Version** : La version du dataprep est calculée automatiquement via hash

---

**Version du dataprep** : Calculée automatiquement à partir du hash des fichiers de configuration ([`DATAPREP_VERSION`](Makefile:3))

Pour obtenir la version actuelle :
```bash
make dataprep-version
