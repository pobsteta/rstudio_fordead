## variables input
species <- "picea_abies"
rep_in <- "/media/pascal/orange/data"
tuile <- "T31TGN"
date_start <- "2018-01-01"
# date_end <- "2018-05-01"
date_end <- as.character(Sys.Date())
setwd("~/rstudio_fordead")
source("s2_list.R")

# Crée les répertoires
dir.create(file.path(rep_in, species, "s2zip"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "extract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "calc"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "extract", "year"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "final", tuile), recursive = TRUE, showWarnings = FALSE)

## Recuperation de la zone interet avec code FRT ONF
# code foret a modifier pour le calul de la zone d'interet
# Besançon
fiidtn_frt <- c("F06040H")
# Moidons
# fiidtn_frt <- c("F07255A")

## ows4R
# Log to wfs frt ONF schema
# Connexion au WFS
wfs_frt <- ows4R::WFSClient$new(
  url = "http://ws.carmencarto.fr/WFS/105/ONF_Forets",
  serviceVersion = "2.0.0"
)
# Récupère in feature type (pour description, ou get features)
frt <- wfs_frt$capabilities$findFeatureTypeByName("ms:FOR_PUBL_FR")

# Créer les enregistrements avec filtre sur les objets ows4R
# filtre <- ows4R::OGCFilter$new(do.call(ows4R::Or$new, lapply(fiidtn_frt, function(val) {
#   ows4R::PropertyIsEqualTo$new("iidtn_frt", val)
# })))
filtre <- ows4R::OGCFilter$new(ows4R::PropertyIsEqualTo$new("iidtn_frt", fiidtn_frt))
frt_data <- frt$getFeatures(Filter = filtre)

## Etendu de la zone d'étude
extent <- frt_data
# extent <- sf::read_sf(file.path(rep_in, species, "extent.shp"))

sf::write_sf(extent, file.path(rep_in, species, "extent.shp"))

# 0/ Step 0 - chargement des data THEIA
resu <- s2_list(
  tiles = c("T31TGN"),
  time_interval = c(date_start, date_end),
  level = "l2a",
  platform = "s2a",
  time_period = "full",
  maxcloud = 45,
  collection = "sentinel2",
  path_to_download = rep_in,
  project_name = species,
  download = TRUE,
  extract = FALSE
)
# vérifie les chargements et dézippe les fichiers necessaires
system(paste0("fordead theia_preprocess -i ", rep_in, "/", species, "/s2zip -o ", rep_in, "/", species, "/extract -t ", tuile, " --login_theia pascal.obstetar@gmail.com --password_theia Pobf6332! --start_date ", date_start, " --end_date ", date_end, " --lim_perc_cloud 45"))
gc()

# on calcule les résultats par année depuis 2018
for (i in seq(lubridate::year(date_start), lubridate::year(date_start) + round(as.numeric(difftime(date_end, date_start, units = "days")) / 365.25, 0))) {
  message(paste("Calcul pour year", i))
  fichiers <- list.files(path = paste0(rep_in, "/", species, "/extract/", tuile), pattern = paste0("SENTINEL2[A-B]_", i), full.names = TRUE)

  # deplace les fichiers dans year
  system(paste0("mv ", paste(fichiers, collapse = " "), " ", file.path(rep_in, species, "extract", "year")))

  # 1/ Step 1 - Calcul de l'indice de végétation et des masques :
  # system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/year -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR"))
  system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/year -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --extent_shape_path ", file.path(rep_in, species, "extent.shp")))
  gc(verbose = FALSE)

  # 2/ Step 2 - Apprentissage du modèle :
  system(paste0("fordead train_model -o ", rep_in, "/", species, "/calc --nb_min_date 10 --min_last_date_training ", date_start, " --max_last_date_training 2018-08-01"))
  gc(verbose = FALSE)

  # 3/ Step 3 - Détection du dépérissement :
  system(paste0("fordead dieback_detection -o ", rep_in, "/", species, "/calc --threshold_anomaly 0.16 --stress_index_mode weighted_mean"))
  gc(verbose = FALSE)

  # 4/ Step 4 - Calcul du masque forêt à partir d'OSO (17 = résineux):
  system(paste0("fordead forest_mask -o ", rep_in, "/", species, "/calc -f OSO --path_oso /home/pascal/fordead_data/OCS_2018.tif --list_code_oso 17"))
  gc(verbose = FALSE)

  # 5/ Step 5 - Export des résultats :
  system(paste0("fordead export_results -o ", rep_in, "/", species, "/calc --frequency M -t 0.2 -t 0.265 -c '0-Anomalie faible' -c '1-Anomalie moyenne' -c '2-Anomalie forte'"))
  gc(verbose = FALSE)

  # Deplacer les resultats dans final
  system(paste0("mv ", file.path(rep_in, species, "calc", "Results"), " ", file.path(rep_in, species, "final", tuile, i)))

  # attente de 5s
  Sys.sleep(5)
}

# recopie tout de nouveau dans la tuile
fichiers <- list.files(path = file.path(rep_in, species, "extract", "year"), full.names = TRUE)

# deplace les fichiers dans year
system(paste0("mv ", paste(fichiers, collapse = " "), " ", file.path(rep_in, species, "extract", tuile)))

v2018 <- sf::read_sf(file.path(rep_in, species, "final", tuile, 2018, "periodic_results_dieback.shp")) |>
  sf::st_transform(2154) |>
  dplyr::mutate(classe = as.factor(class))
rbase <- raster::raster(v2018, res = 10)
v2019 <- sf::read_sf(file.path(rep_in, species, "final", tuile, 2019, "periodic_results_dieback.shp")) |>
  sf::st_transform(2154) |>
  dplyr::mutate(classe = as.factor(class))

r2018 <- fasterize::fasterize(v2018, rbase, field = "classe")
r2019 <- fasterize::fasterize(v2019, rbase, field = "classe")
cm <- caret::confusionMatrix(factor(r2018[], levels = 1:4), factor(r2019[], levels = 1:4), dnn = c("2018", "2019"))
cm$table
tab <- cm$table |> 
  as.data.frame()
tab

coul <- c("1" = "green", "2" = "orange", "3" = "red", "4" = "gray")
circlize::chordDiagram(
  x = tab,
  grid.col = coul,
  transparency = 0.25,
  directional = 1,
  direction.type = c("arrows", "diffHeight"),
  diffHeight = -0.05,
  link.arr.type = "triangle",
  link.sort = TRUE,
  link.largest.ontop = TRUE
)
