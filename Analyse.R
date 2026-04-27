# =============================================================================
# PROJET  : INÉGALITÉS D'ACCÈS AUX SOINS HOSPITALIERS — MONTRÉAL 2026–2034
# =============================================================================
# Objet   : (1) Documenter les inégalités d'accès aux soins avant la réforme
#               de 2030, aux niveaux individuel et quartier.
#           (2) Évaluer l'impact des cliniques locales sur les admissions
#               hospitalières via la méthode Différences-en-Différences (DiD).
# Packages: tidyverse, lubridate, geosphere, fixest
# =============================================================================

# ── 0. Packages ───────────────────────────────────────────────────────────────
library(tidyverse)
library(lubridate)
library(geosphere)   # distances Haversine
library(fixest)      # feols() — OLS avec effets fixes


# =============================================================================
# SECTION 1 : SIMULATION DES DONNÉES
# =============================================================================

set.seed(42)

# ── 1.1 Habitants (n = 5 000) ─────────────────────────────────────────────────
n_hab <- 5000

habitants <- tibble(
  ID_Individu   = 1:n_hab,
  Code_Postal   = paste0(
    "H", sample(1:9, n_hab, replace = TRUE),
    sample(c("A","B","G","N","R","T"), n_hab, replace = TRUE), " ",
    sample(0:9, n_hab, replace = TRUE),
    sample(LETTERS[1:9], n_hab, replace = TRUE),
    sample(0:9, n_hab, replace = TRUE)
  ),
  Revenu_Menage = pmax(10000, round(rnorm(n_hab, mean = 58000, sd = 22000))),
  Quartier_ID   = sample(1:19, n_hab, replace = TRUE),
  Latitude      = runif(n_hab, 45.42, 45.70),
  Longitude     = runif(n_hab, -73.97, -73.47)
)

# ── 1.2 Admissions hospitalières (n = 20 000, période 2026–2034) ──────────────
n_adm <- 20000

admissions <- tibble(
  ID_Individu = sample(habitants$ID_Individu, n_adm, replace = TRUE),
  Date_Admission = sample(
    seq(as.Date("2026-01-01"), as.Date("2034-12-31"), by = "day"),
    n_adm, replace = TRUE
  ),
  Diagnostic_Principal = sample(
    c("Cardiologie","Pneumologie","Traumatologie",
      "Neurologie","Orthopédie","Urgences","Autres"),
    n_adm, replace = TRUE,
    prob = c(0.18, 0.14, 0.18, 0.14, 0.14, 0.12, 0.10)
  ),
  ID_Hopital = sample(1:12, n_adm, replace = TRUE)
) |>
  mutate(
    Annee = year(Date_Admission),
    Mois  = month(Date_Admission)
  )

# ── 1.3 Hôpitaux (12 établissements majeurs) ─────────────────────────────────
hopitaux <- tibble(
  ID_Hopital  = 1:12,
  Nom         = paste("Hôpital", LETTERS[1:12]),
  Latitude    = runif(12, 45.45, 45.68),
  Longitude   = runif(12, -73.90, -73.52),
  Quartier_ID = sample(1:19, 12, replace = TRUE),
  Nb_Lits     = sample(150:800, 12, replace = TRUE)
)

# ── 1.4 Cliniques locales (25 cliniques, ouvertes dès 2030) ───────────────────
n_cl <- 25

cliniques <- tibble(
  ID_Clinique    = 1:n_cl,
  Latitude       = runif(n_cl, 45.44, 45.69),
  Longitude      = runif(n_cl, -73.92, -73.50),
  Quartier_ID    = sample(1:19, n_cl, replace = TRUE),
  Date_Ouverture = sample(
    seq(as.Date("2030-01-01"), as.Date("2031-06-30"), by = "month"),
    n_cl, replace = TRUE
  )
)

cat("=== Dimensions des bases simulées ===\n")
cat("Habitants  :", nrow(habitants), "\n")
cat("Admissions :", nrow(admissions), "\n")
cat("Hôpitaux   :", nrow(hopitaux), "\n")
cat("Cliniques  :", nrow(cliniques), "\n\n")


# =============================================================================
# SECTION 2 : MANDAT 1 — INÉGALITÉS AVANT LA RÉFORME (2026–2029)
# =============================================================================

# ── 2.1 Période pré-réforme ───────────────────────────────────────────────────
adm_pre <- admissions |>
  filter(Annee < 2030)

cat("Admissions pré-réforme (2026–2029) :", nrow(adm_pre), "\n\n")

# ─────────────────────────────────────────────────────────────────────────────
# A. NIVEAU INDIVIDUEL
# ─────────────────────────────────────────────────────────────────────────────

# Nombre d'admissions par individu (pré-réforme)
adm_ind <- adm_pre |>
  count(ID_Individu, name = "Nb_Adm")

# Jointure avec les caractéristiques socio-économiques
data_ind <- habitants |>
  left_join(adm_ind, by = "ID_Individu") |>
  mutate(
    Nb_Adm         = replace_na(Nb_Adm, 0),
    Hospitalise     = if_else(Nb_Adm > 0, 1L, 0L),
    Quintile_Revenu = ntile(Revenu_Menage, 5),
    Revenu_k        = Revenu_Menage / 1000
  )

# Statistiques par quintile
ineg_ind <- data_ind |>
  group_by(Quintile_Revenu) |>
  summarise(
    Revenu_Moyen  = round(mean(Revenu_Menage)),
    Nb_Adm_Moyen  = round(mean(Nb_Adm), 3),
    Taux_Hosp_pct = round(mean(Hospitalise) * 100, 1),
    N             = n(),
    .groups = "drop"
  )

cat("=== Inégalités individuelles par quintile de revenu ===\n")
print(ineg_ind)

# Corrélation Pearson : revenu vs admissions
cor_r <- cor.test(data_ind$Revenu_Menage, data_ind$Nb_Adm, method = "pearson")
cat("\nCorrélation Pearson : r =", round(cor_r$estimate, 3),
    "| p =", round(cor_r$p.value, 4), "\n\n")

# OLS simple : Nb_Adm ~ Revenu_k
ols_ind <- lm(Nb_Adm ~ Revenu_k, data = data_ind)
cat("=== OLS individuel : Nb_Adm ~ Revenu_k ===\n")
print(summary(ols_ind))

# Logit : P(Hospitalisé = 1) ~ Revenu_k
logit_ind <- glm(
  Hospitalise ~ Revenu_k,
  data   = data_ind,
  family = binomial(link = "logit")
)
cat("=== Logit : P(Hospitalisé = 1) ~ Revenu_k ===\n")
print(summary(logit_ind))
cat("\nOdds Ratios :\n")
print(round(exp(coef(logit_ind)), 4))

# ─────────────────────────────────────────────────────────────────────────────
# B. NIVEAU QUARTIER
# ─────────────────────────────────────────────────────────────────────────────

# Agrégats par quartier
stats_q <- habitants |>
  group_by(Quartier_ID) |>
  summarise(
    Revenu_Moyen_Q = mean(Revenu_Menage),
    Nb_Habitants_Q = n(),
    .groups = "drop"
  )

# Hôpitaux par quartier
hopitaux_q <- hopitaux |>
  count(Quartier_ID, name = "Nb_Hopitaux")

# Admissions pré-réforme par quartier
adm_q <- adm_pre |>
  left_join(habitants |> select(ID_Individu, Quartier_ID), by = "ID_Individu") |>
  count(Quartier_ID, name = "Nb_Adm_Q")

# Table quartier
data_quartier <- stats_q |>
  left_join(hopitaux_q, by = "Quartier_ID") |>
  left_join(adm_q,      by = "Quartier_ID") |>
  mutate(
    Nb_Hopitaux = replace_na(Nb_Hopitaux, 0),
    Nb_Adm_Q    = replace_na(Nb_Adm_Q, 0),
    Taux_Adm_1k = round(Nb_Adm_Q / Nb_Habitants_Q * 1000, 1),
    Desert_Med  = if_else(Nb_Hopitaux == 0, "Désert médical", "Couvert"),
    Defavorise  = if_else(
      Revenu_Moyen_Q < quantile(Revenu_Moyen_Q, 0.25),
      "Défavorisé", "Autre"
    )
  )

cat("=== Table des quartiers ===\n")
print(data_quartier |> arrange(Revenu_Moyen_Q))

# OLS quartier
ols_q <- lm(Taux_Adm_1k ~ Revenu_Moyen_Q + Nb_Hopitaux, data = data_quartier)
cat("\n=== OLS quartier : Taux_Adm_1k ~ Revenu_Moyen_Q + Nb_Hopitaux ===\n")
print(summary(ols_q))

# Comparaison défavorisés vs favorisés
taux_grp <- data_quartier |>
  group_by(Defavorise) |>
  summarise(
    Nb_Quartiers   = n(),
    Taux_Adm_Moyen = round(mean(Taux_Adm_1k), 1),
    Revenu_Moy     = round(mean(Revenu_Moyen_Q)),
    .groups = "drop"
  )
cat("\n=== Taux d'admission : défavorisés vs favorisés ===\n")
print(taux_grp)

t_res <- t.test(Taux_Adm_1k ~ Defavorise, data = data_quartier)
cat("t =", round(t_res$statistic, 3), "| p =", round(t_res$p.value, 4), "\n\n")


# =============================================================================
# SECTION 3 : MANDAT 2 — IMPACT DES CLINIQUES (DiD)
# =============================================================================

# ── 3.1 Distances Haversine entre hôpitaux et cliniques ──────────────────────
dist_mat <- expand_grid(
  ID_Hopital  = hopitaux$ID_Hopital,
  ID_Clinique = cliniques$ID_Clinique
) |>
  left_join(hopitaux  |> select(ID_Hopital,  Lat_H = Latitude, Lon_H = Longitude),
            by = "ID_Hopital") |>
  left_join(cliniques |> select(ID_Clinique, Lat_C = Latitude, Lon_C = Longitude),
            by = "ID_Clinique") |>
  rowwise() |>
  mutate(
    Dist_km = distHaversine(c(Lon_H, Lat_H), c(Lon_C, Lat_C)) / 1000
  ) |>
  ungroup()

dist_min_hop <- dist_mat |>
  group_by(ID_Hopital) |>
  summarise(Dist_Min_km = min(Dist_km), .groups = "drop")

# ── 3.2 Assignation du groupe traité (seuil = 2 km) ──────────────────────────
SEUIL_KM <- 2

hopitaux_did <- hopitaux |>
  left_join(dist_min_hop, by = "ID_Hopital") |>
  mutate(Traite = if_else(Dist_Min_km <= SEUIL_KM, 1L, 0L))

cat("=== Assignation du traitement (seuil =", SEUIL_KM, "km) ===\n")
cat("Traités  :", sum(hopitaux_did$Traite), "\n")
cat("Contrôles:", sum(1L - hopitaux_did$Traite), "\n\n")
print(hopitaux_did |> select(Nom, Dist_Min_km, Traite) |> arrange(Dist_Min_km))

# ── 3.3 Panel cylindré (hôpital × année) ─────────────────────────────────────
panel_did <- admissions |>
  count(ID_Hopital, Annee, name = "Nb_Adm") |>
  complete(ID_Hopital = 1:12, Annee = 2026:2034,
           fill = list(Nb_Adm = 0)) |>
  left_join(hopitaux_did |> select(ID_Hopital, Traite, Dist_Min_km),
            by = "ID_Hopital") |>
  mutate(
    Post = if_else(Annee >= 2030, 1L, 0L),
    DiD  = Traite * Post
  )

cat("\n=== Panel DiD :", nrow(panel_did), "lignes ×",
    ncol(panel_did), "colonnes ===\n\n")

# ── 3.4 Test de tendances parallèles (pré-trend) ─────────────────────────────
panel_pre <- panel_did |>
  filter(Annee < 2030) |>
  mutate(Annee_c = Annee - 2026)

m_pretrend <- lm(
  Nb_Adm ~ Traite * Annee_c + factor(ID_Hopital),
  data = panel_pre
)

coef_inter <- coef(summary(m_pretrend))["Traite:Annee_c", ]
cat("=== Test de tendances parallèles ===\n")
cat("Interaction Traité × Année_c :",
    "coef =", round(coef_inter["Estimate"], 3),
    "| p =",  round(coef_inter["Pr(>|t|)"], 4), "\n")
if (coef_inter["Pr(>|t|)"] > 0.10) {
  cat("Tendances parallèles non rejetées. DiD valide. ✅\n\n")
} else {
  cat("Attention : biais de pré-tendance potentiel. ⚠️\n\n")
}

# ── 3.5 Régression DiD principale ────────────────────────────────────────────
# Y_ht = alpha + beta*DiD_ht + gamma_h + delta_t + eps_ht
modele_did <- feols(
  Nb_Adm ~ DiD | ID_Hopital + Annee,
  data    = panel_did,
  cluster = ~ID_Hopital
)

cat("=== Régression DiD principale ===\n")
print(summary(modele_did))

coef_did <- coef(modele_did)["DiD"]
cat("Coefficient DiD :", round(coef_did, 3), "\n")
if (coef_did < 0) {
  cat("-> Les cliniques ont RÉDUIT les admissions dans les hôpitaux voisins.\n\n")
} else {
  cat("-> Aucun effet de substitution significatif.\n\n")
}

# ── 3.6 DiD avec contrôle (Nb_Lits) ──────────────────────────────────────────
panel_ctrl <- panel_did |>
  left_join(hopitaux |> select(ID_Hopital, Nb_Lits, Quartier_ID), by = "ID_Hopital") |>
  left_join(data_quartier |> select(Quartier_ID, Revenu_Moyen_Q), by = "Quartier_ID")

modele_did_ctrl <- feols(
  Nb_Adm ~ DiD + Nb_Lits | ID_Hopital + Annee,
  data    = panel_ctrl,
  cluster = ~ID_Hopital
)
cat("=== DiD avec contrôle (Nb_Lits) ===\n")
print(summary(modele_did_ctrl))


# =============================================================================
# SECTION 4 : TESTS DE ROBUSTESSE
# =============================================================================

# ── 4.1 Multi-seuils (1, 2, 3, 5 km) ─────────────────────────────────────────
cat("=== Robustesse : seuils de traitement multiples ===\n")

resultats_seuils <- map_dfr(c(1, 2, 3, 5), function(s) {
  h_s <- hopitaux |>
    left_join(dist_min_hop, by = "ID_Hopital") |>
    mutate(Traite_s = if_else(Dist_Min_km <= s, 1L, 0L))

  p_s <- panel_did |>
    select(-Traite, -DiD) |>
    left_join(h_s |> select(ID_Hopital, Traite = Traite_s), by = "ID_Hopital") |>
    mutate(DiD = Traite * Post)

  m <- feols(Nb_Adm ~ DiD | ID_Hopital + Annee,
             data = p_s, cluster = ~ID_Hopital)

  tibble(
    Seuil_km   = s,
    Nb_Traites = sum(h_s$Traite_s),
    Coef_DiD   = round(coef(m)["DiD"], 3),
    SE         = round(se(m)["DiD"],   3),
    P_Value    = round(pvalue(m)["DiD"], 4)
  )
})
print(resultats_seuils)

# ── 4.2 Test placebo (réforme fictive en 2028) ────────────────────────────────
panel_placebo <- panel_did |>
  filter(Annee < 2030) |>
  mutate(
    Post_pl = if_else(Annee >= 2028, 1L, 0L),
    DiD_pl  = Traite * Post_pl
  )

m_placebo <- feols(
  Nb_Adm ~ DiD_pl | ID_Hopital + Annee,
  data    = panel_placebo,
  cluster = ~ID_Hopital
)
cat("\n=== Test placebo (réforme fictive en 2028) ===\n")
print(summary(m_placebo))
cat("DiD placebo :", round(coef(m_placebo)["DiD_pl"], 3),
    "| p =", round(pvalue(m_placebo)["DiD_pl"], 4), "\n")
if (pvalue(m_placebo)["DiD_pl"] > 0.10) {
  cat("Pas d'effet pré-traitement. ✅\n\n")
} else {
  cat("Effet pré-traitement détecté. ⚠️\n\n")
}

# ── 4.3 Effet hétérogène DiD × revenu du quartier ────────────────────────────
panel_het <- panel_did |>
  left_join(hopitaux |> select(ID_Hopital, Quartier_ID), by = "ID_Hopital") |>
  left_join(data_quartier |> select(Quartier_ID, Revenu_Moyen_Q), by = "Quartier_ID") |>
  mutate(
    Rev_c     = (Revenu_Moyen_Q - mean(Revenu_Moyen_Q, na.rm = TRUE)) / 1000,
    DiD_x_Rev = DiD * Rev_c
  )

m_het <- feols(
  Nb_Adm ~ DiD + Rev_c + DiD_x_Rev | ID_Hopital + Annee,
  data    = panel_het,
  cluster = ~ID_Hopital
)
cat("=== Effet hétérogène DiD × revenu quartier ===\n")
print(summary(m_het))


# =============================================================================
# SECTION 5 : TABLEAU SYNTHÈSE FINAL
# =============================================================================

cat("=== TABLEAU DiD 2×2 ===\n")

synthese_2x2 <- panel_did |>
  mutate(
    Groupe  = if_else(Traite == 1, "Traité",    "Contrôle"),
    Periode = if_else(Post   == 1, "Post-2030", "Pré-2030")
  ) |>
  group_by(Groupe, Periode) |>
  summarise(Adm_Moy = round(mean(Nb_Adm), 2), .groups = "drop") |>
  pivot_wider(id_cols = Groupe, names_from = Periode, values_from = Adm_Moy) |>
  mutate(Difference = `Post-2030` - `Pré-2030`)

print(synthese_2x2)

did_manuel <- synthese_2x2$Difference[synthese_2x2$Groupe == "Traité"] -
              synthese_2x2$Difference[synthese_2x2$Groupe == "Contrôle"]

cat("\nEstimateur DiD (manuel)     :", round(did_manuel, 3), "\n")
cat("Estimateur DiD (régression) :", round(coef_did,   3), "\n")
cat("\n=== FIN DU SCRIPT R — PARTIE 2 ===\n")
