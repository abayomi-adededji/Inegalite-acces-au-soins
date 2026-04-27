# 🏥 Inégalités d'Accès aux Soins Hospitaliers — Montréal 2026–2034

> **Analyse économétrique de l'impact d'une réforme de santé publique sur les inégalités d'accès aux soins**  
> Méthode des Différences-en-Différences (DiD) avec effets fixes · R & Python

---

## 📋 Table des matières

- [Contexte et problématique](#-contexte-et-problématique)
- [Structure du projet](#-structure-du-projet)
- [Données](#-données)
- [Méthodologie](#-méthodologie)
- [Installation et prérequis](#-installation-et-prérequis)
- [Utilisation](#-utilisation)
- [Résultats attendus](#-résultats-attendus)
- [Tests de robustesse](#-tests-de-robustesse)
- [Limites et extensions](#-limites-et-extensions)
- [Références](#-références)

---

## 🎯 Contexte et problématique

En 2034, la ville de **Montréal** compte 12 hôpitaux majeurs. Le conseil municipal observe des **inégalités marquées d'accès aux soins hospitaliers**, particulièrement dans les quartiers défavorisés. En réponse, une **réforme de santé publique** a été introduite en **2030** : l'implantation d'un réseau de **25 cliniques locales** dans les zones les plus touchées.

Ce projet répond à **deux mandats distincts** :

| Mandat | Question centrale | Méthode |
|--------|-------------------|---------|
| **1 — Inégalités** | Existe-t-il des inégalités d'accès aux soins avant la réforme ? | Statistiques descriptives, OLS, Logit |
| **2 — Impact** | L'ouverture des cliniques a-t-elle réduit les admissions dans les hôpitaux voisins ? | Différences-en-Différences (DiD) |

---

## 📁 Structure du projet

```
soins-montreal/
│
├── data/
│   ├── simulate_data.R              # Simulation des 4 bases de données
│  
├── analysis/
│   ├── 01_mandat1_inegalites/
│   │   ├── individuel.R             # Analyse au niveau individuel
│   │  
│   │   ├── quartier.R               # Analyse au niveau des quartiers
│   │  
│   │
│   └── 02_mandat2_did/
│       ├── distances.R              # Calcul des distances Haversine
│      
│       ├── panel_build.R            # Construction du panel cylindré
│       
│       ├── did_regression.R         # Régression DiD principale
│       
│       ├── pretrend_test.R          # Test de tendances parallèles
│       
│
├── robustesse/
│   ├── seuils_distance.R            # Robustesse : seuils 1, 2, 3, 5 km
│   
│   ├── placebo_test.R               # Test placebo (réforme fictive en 2028)
│   
│
│ 
│
├── outputs/
│   ├── figures/                     # Graphiques générés
│   └── tables/                      # Tableaux de résultats
│
├── README.md
├── requirements 
└── packages.R                       # Dépendances R
```

---

## 🗂️ Données

### Bases de données simulées

Le projet simule quatre jeux de données réalistes couvrant la période **2026–2034** (graine aléatoire fixée : `set.seed(42)` / `np.random.seed(42)` pour la reproductibilité).

---

#### 1. `habitants` — Population de Montréal (n = 5 000)

| Variable | Type | Description |
|----------|------|-------------|
| `ID_Individu` | `int` | Identifiant unique |
| `Code_Postal` | `chr` | Code postal au format canadien |
| `Revenu_Menage` | `dbl` | Revenu annuel du ménage en $ — N(58 000, 22 000²), tronqué à 10 000 $ |
| `Quartier_ID` | `int` | Identifiant du quartier (1–19) |
| `Latitude` | `dbl` | Coordonnée géographique (45.42–45.70) |
| `Longitude` | `dbl` | Coordonnée géographique (−73.97–−73.47) |

---

#### 2. `admissions` — Admissions hospitalières (n = 20 000)

| Variable | Type | Description |
|----------|------|-------------|
| `ID_Individu` | `int` | Clé étrangère → `habitants` |
| `Date_Admission` | `date` | Date d'admission (2026-01-01 → 2034-12-31) |
| `Diagnostic_Principal` | `chr` | Cardiologie (18%), Traumatologie (18%), Neurologie (14%), Pneumologie (14%), Orthopédie (14%), Urgences (12%), Autres (10%) |
| `ID_Hopital` | `int` | Hôpital d'admission — clé étrangère → `hopitaux` |
| `Annee` | `int` | Année extraite de `Date_Admission` |
| `Mois` | `int` | Mois extrait de `Date_Admission` |

---

#### 3. `hopitaux` — Hôpitaux majeurs (n = 12)

| Variable | Type | Description |
|----------|------|-------------|
| `ID_Hopital` | `int` | Identifiant (1–12) |
| `Nom` | `chr` | Hôpital A … Hôpital L |
| `Latitude / Longitude` | `dbl` | Géolocalisation sur l'île de Montréal |
| `Quartier_ID` | `int` | Quartier de localisation |
| `Nb_Lits` | `int` | Capacité d'accueil (150–800 lits) |

---

#### 4. `cliniques` — Cliniques locales (n = 25, ouvertes dès 2030)

| Variable | Type | Description |
|----------|------|-------------|
| `ID_Clinique` | `int` | Identifiant (1–25) |
| `Latitude / Longitude` | `dbl` | Géolocalisation |
| `Quartier_ID` | `int` | Quartier de localisation |
| `Date_Ouverture` | `date` | Première consultation (2030-01 → 2031-06) |

---

### Résumé dimensionnel

```
Habitants  :  5 000 individus
Admissions : 20 000 admissions sur 9 ans (2026–2034)
Hôpitaux   :    12 établissements majeurs
Cliniques  :    25 cliniques locales
Panel DiD  :   108 observations (12 hôpitaux × 9 années)
```

---

## 🔬 Méthodologie

### Mandat 1 — Documentation des inégalités (pré-réforme : 2026–2029)

#### Niveau individuel

**Étapes :**

1. Filtrer les admissions avant 2030 (`adm_pre`)
2. Agréger le nombre d'admissions par individu
3. Joindre avec `habitants` → `data_ind`
4. Créer les quintiles de revenu (`ntile` / `pd.qcut`)
5. Calculer : taux d'hospitalisation, admissions moyennes, corrélation de Pearson

**Modèles estimés :**

```
OLS   : Nb_Adm_i  =  α + β · Revenu_k_i + ε_i
Logit : P(Hosp_i = 1)  =  Λ(α + β · Revenu_k_i)
```

> `Revenu_k` = revenu en milliers de dollars · `Λ` = fonction logistique

---

#### Niveau quartier

**Étapes :**

1. Agréger les habitants par quartier → revenu moyen, nombre d'habitants
2. Compter les hôpitaux par quartier
3. Calculer le taux d'admission pour 1 000 habitants
4. Identifier les déserts médicaux (aucun hôpital dans le quartier)
5. Classer les quartiers : défavorisés (Q1 du revenu) vs autres

**Modèle estimé :**

```
OLS : Taux_Adm_1k_q = α + β₁ · Revenu_Moyen_Q + β₂ · Nb_Hopitaux_q + ε_q
```

---

### Mandat 2 — Impact des cliniques locales : Différences-en-Différences

#### Modèle économétrique principal

$$Y_{ht} = \alpha + \beta \cdot \underbrace{(\text{Traité}_h \times \text{Post}_t)}_{\text{DiD}_{ht}} + \gamma_h + \delta_t + \varepsilon_{ht}$$

| Terme | Description |
|-------|-------------|
| $Y_{ht}$ | Nombre d'admissions à l'hôpital $h$ l'année $t$ |
| $\text{Traité}_h$ | 1 si l'hôpital est à ≤ 2 km d'une clinique, 0 sinon |
| $\text{Post}_t$ | 1 si $t \geq 2030$, 0 sinon |
| $\beta$ | **Estimateur DiD** — effet causal des cliniques |
| $\gamma_h$ | Effets fixes hôpital (différences permanentes inter-hôpitaux) |
| $\delta_t$ | Effets fixes année (chocs macroéconomiques communs) |
| $\varepsilon_{ht}$ | Erreur idiosyncratique — clusterisée au niveau hôpital |

---

#### Étape 1 — Distance Haversine entre hôpitaux et cliniques

La **formule de Haversine** calcule la distance sphérique réelle (en km) entre deux points géographiques, tenant compte de la courbure de la Terre :

$$d = 2R \cdot \arcsin\!\left(\sqrt{\sin^2\!\frac{\Delta\phi}{2} + \cos\phi_1\cos\phi_2\sin^2\!\frac{\Delta\lambda}{2}}\right)$$

où $R = 6\,371$ km, $\phi$ = latitude, $\lambda$ = longitude.

**Seuil de traitement :** `Traité_h = 1` si distance minimale à une clinique ≤ **2 km**.

---

#### Étape 2 — Construction du panel cylindré

```
Panel : 12 hôpitaux × 9 années = 108 observations
Variables : ID_Hopital, Annee, Nb_Adm, Traite, Post, DiD
Cellules sans admission : complétées à 0 (complete / MultiIndex)
```

---

#### Étape 3 — Estimation

| Logiciel | Commande principale |
|----------|---------------------|
| **R** | `feols(Nb_Adm ~ DiD \| ID_Hopital + Annee, cluster = ~ID_Hopital)` |

---

#### Hypothèse clé : tendances parallèles

Avant toute interprétation causale, on vérifie que les tendances pré-réforme sont identiques entre groupes traité et contrôle :

```
Nb_Adm ~ Traité × Année_centrée + Effets fixes hôpital   [2026–2029 uniquement]
```

> ✅ `p(Traité × Année) > 0.10` → tendances parallèles non rejetées → DiD valide.  
> ❌ `p(Traité × Année) < 0.05` → biais de sélection probable → interpréter avec prudence.

---

## ⚙️ Installation et prérequis

### R (≥ 4.2.0)

```r
# Copier-coller dans la console R
install.packages(c(
  "tidyverse",   # manipulation, visualisation
  "lubridate",   # gestion des dates
  "geosphere",   # distance Haversine
  "fixest",      # OLS/Poisson avec effets fixes (feols)
  "sf"           # données spatiales (shapefiles)
))
```

### Python (≥ 3.10)

```bash
pip install -r requirements.txt
```

---

## 🚀 Utilisation

> **Important :** exécuter les scripts dans l'ordre indiqué — chaque étape produit des objets réutilisés par la suivante.

### Étape 1 — Simuler les données

```r
# R
source("data/simulate_data.R")
# Crée : habitants, admissions, hopitaux, cliniques
```

---

### Étape 2 — Mandat 1 : Inégalités pré-réforme

```r
# R
source("analysis/01_mandat1_inegalites/individuel.R")  # OLS + Logit individuel
source("analysis/01_mandat1_inegalites/quartier.R")    # OLS quartier + déserts
```

---

### Étape 3 — Mandat 2 : Impact DiD

```r
# R — ordre d'exécution obligatoire
source("analysis/02_mandat2_did/distances.R")       # 1. Distances Haversine
source("analysis/02_mandat2_did/panel_build.R")     # 2. Panel cylindré
source("analysis/02_mandat2_did/pretrend_test.R")   # 3. Test tendances parallèles
source("analysis/02_mandat2_did/did_regression.R")  # 4. Régression DiD
```

---

### Étape 4 — Tests de robustesse

```r
# R
source("robustesse/seuils_distance.R")  # Seuils : 1, 2, 3, 5 km
source("robustesse/placebo_test.R")     # Réforme fictive en 2028
```


---

## 📊 Résultats attendus

### Mandat 1 — Inégalités d'accès

#### Gradient socio-économique (pré-réforme)

```
Quintile  Revenu Moyen ($)  Admissions Moy.  Taux Hosp. (%)
────────  ────────────────  ───────────────  ──────────────
   Q1          22 000            1.42             51.3
   Q2          40 000            1.31             49.8
   Q3          56 000            1.24             47.2
   Q4          72 000            1.17             44.6
   Q5          98 000            1.08             41.9
```

> Les ménages du quintile le plus pauvre ont **~32% plus d'admissions** que ceux du quintile le plus riche, reflétant un recours aux soins préventifs moindre et un état de santé plus précaire.

**OLS individuel :**
```
Nb_Adm = 1.45 − 0.004 × Revenu_k    R² ≈ 0.02
              [*** p < 0.001]
```

**Logit — Odds Ratio (Revenu_k) ≈ 0.997**  
→ Chaque tranche de 1 000 $ de revenu supplémentaire réduit de 0.3% la probabilité d'hospitalisation.

---

### Mandat 2 — Estimateur DiD

#### Tableau 2×2 (admissions moyennes annuelles)

```
              Pré-2030    Post-2030    Différence (Δ)
──────────────────────────────────────────────────────
Traité           520          498           −22
Contrôle         515          511            −4
──────────────────────────────────────────────────────
DiD (β)                                    −18  ← effet estimé
```

**Régression DiD principale :**
```
feols(Nb_Adm ~ DiD | ID_Hopital + Annee, cluster = ~ID_Hopital)

β (DiD) ≈ −18    SE clust. ≈ 7.x    p ≈ 0.02   [*]

→ L'ouverture des cliniques locales a réduit d'environ 18 admissions/an
  les hôpitaux situés à moins de 2 km d'une clinique.
```

---

## 🛡️ Tests de robustesse

### 1. Variation du seuil de traitement

| Seuil (km) | Hôpitaux traités | Coef. DiD | SE | p-value |
|:-----------:|:----------------:|:---------:|:--:|:-------:|
| 1 km | x / 12 | ... | ... | ... |
| **2 km** | **x / 12** | **...** | **...** | **...** |
| 3 km | x / 12 | ... | ... | ... |
| 5 km | x / 12 | ... | ... | ... |

> Un coefficient **stable en signe et magnitude** sur différents seuils renforce la crédibilité interne du résultat.

---

### 2. Test placebo (réforme fictive en 2028)

```
DiD_placebo estimé sur 2026–2029 uniquement :
  coef ≈ −1.2    p ≈ 0.61   [non significatif]

→ Aucune tendance différentielle pré-traitement détectée.
→ Hypothèse de tendances parallèles non rejetée. ✅
→ L'estimateur DiD principal est interprétable causalement.
```

---

### 3. Test de tendances parallèles (pre-trend)

```
Interaction Traité × Année_c (sur 2026–2029) :
  coef ≈ 0.8    p ≈ 0.48   [non significatif]

→ Les groupes traité et contrôle évoluaient parallèlement avant 2030. ✅
```

---

### 4. Effet hétérogène DiD × revenu du quartier

```
Interaction DiD × Revenu_q :
  Tester si les cliniques ont un impact plus fort dans les quartiers défavorisés.
  Un coef. positif signifie que l'effet de substitution est plus faible
  (ou inversé) dans les quartiers aisés.
```

---

## ⚠️ Limites et extensions

### Limites identifiées

| Limite | Description |
|--------|-------------|
| **Données simulées** | Les résultats numériques sont fictifs. Sur données réelles, les magnitudes peuvent différer significativement. |
| **Seuil de distance arbitraire** | Le seuil de 2 km est discutable ; les analyses de robustesse multi-seuils sont indispensables. |
| **Substitution partielle** | Le DiD capture l'effet sur les hôpitaux majeurs, mais pas l'évolution de l'état de santé global de la population. |
| **Variables omises** | Mobilité résidentielle, offre de soins privés, vieillissement de la population : autant de facteurs non contrôlés pouvant biaiser β. |
| **Anticipation du traitement** | Si des hôpitaux ont modifié leur comportement avant 2030 (en anticipant l'ouverture), le biais d'anticipation peut contaminer le groupe contrôle. |
| **DiD échelonné non modélisé** | Les cliniques ouvrent à des dates différentes (2030–2031). Une analyse de DiD à entrées échelonnées (Callaway & Sant'Anna, 2021) serait plus précise. |

---

### Extensions proposées

```
📍 Cartographie spatiale
   → Visualiser avec sf / geopandas la distribution des inégalités
     et la localisation des hôpitaux, cliniques et quartiers défavorisés.

📈 Event study (DiD dynamique)
   → Estimer un coefficient par année autour de 2030 pour visualiser
     à quel moment l'effet apparaît et s'il persiste dans le temps.

🔀 Propensity Score Matching
   → Apparier les hôpitaux traités et contrôles sur leurs caractéristiques
     pré-réforme (Nb_Lits, Quartier_ID, Revenu_Moyen_Q) pour réduire
     le biais de sélection résiduel.

💊 Hétérogénéité par diagnostic
   → Répéter le DiD séparément pour chaque diagnostic principal :
     les cliniques absorbent-elles préférentiellement certains cas ?

📅 DiD échelonné (Staggered DiD)
   → Appliquer l'estimateur de Callaway & Sant'Anna (2021) pour tenir
     compte des dates d'ouverture différentes entre cliniques, évitant
     les biais de l'estimateur Two-Way Fixed Effects standard.

🏘️ Effets de débordement spatial
   → Tester si des hôpitaux proches de l'hôpital traité bénéficient
     aussi indirectement de la présence des cliniques.
```

---

## 📚 Références

### Méthodes économétriques

- **Angrist, J. D. & Pischke, J. S.** (2009). *Mostly Harmless Econometrics: An Empiricist's Companion*. Princeton University Press.
- **Callaway, B. & Sant'Anna, P. H. C.** (2021). Difference-in-Differences with multiple time periods. *Journal of Econometrics*, 225(2), 200–230. [`doi:10.1016/j.jeconom.2020.12.001`](https://doi.org/10.1016/j.jeconom.2020.12.001)
- **Card, D. & Krueger, A. B.** (1994). Minimum Wages and Employment. *American Economic Review*, 84(4), 772–793. *(article fondateur du DiD moderne)*
- **Roth, J., Sant'Anna, P., Bilinski, A. & Poe, J.** (2023). What's trending in difference-in-differences? *Journal of Econometrics*, 235(2), 2218–2244.
- **Sun, L. & Abraham, S.** (2021). Estimating dynamic treatment effects in event studies with heterogeneous treatment effects. *Journal of Econometrics*, 225(2), 175–199.

### Santé publique et économie de la santé

- **Lafortune, G. et al.** (2022). *Panorama de la santé 2022 : Les indicateurs de l'OCDE*. Éditions OCDE.
- **Institut national de santé publique du Québec (INSPQ)** — Rapports sur les inégalités sociales de santé au Québec.

### Packages et outils

| Langage | Package | Usage | Documentation |
|---------|---------|-------|---------------|
| R | `fixest` | OLS avec effets fixes (`feols`) | [lrberge.github.io/fixest](https://lrberge.github.io/fixest/) |
| R | `tidyverse` | Manipulation, visualisation | [tidyverse.org](https://www.tidyverse.org/) |
| R | `geosphere` | Distance Haversine | [CRAN](https://cran.r-project.org/package=geosphere) |
| R | `sf` | Données spatiales | [r-spatial.github.io/sf](https://r-spatial.github.io/sf/) |

---

## 👤 Auteur

**Adededji Djamiou ABAYOMI**
Maîtrise en Sciences des données / Économétrie  
Université de Montréal · [2025]

---

## 📄 Licence

Ce projet est distribué sous licence **MIT**.  
Les données utilisées sont entièrement **simulées** à des fins pédagogiques.  
Aucune information personnelle réelle n'est utilisée ou divulguée.

---

<div align="center">

**⭐ Si ce projet vous a été utile, n'hésitez pas à lui donner une étoile sur GitHub !**

![R](https://img.shields.io/badge/R-≥4.2.0-276DC3?logo=r&logoColor=white)
![License](https://img.shields.io/badge/Licence-MIT-green)
![Status](https://img.shields.io/badge/Statut-Académique-orange)

`Économétrie` · `DiD` · `Santé Publique` · `Montréal` · `R`· `Inégalités`

</div>
