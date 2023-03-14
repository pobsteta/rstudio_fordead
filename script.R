## variables input
species <- "picea_abies"
rep_in <- "/media/pascal/orange/data"
tuile <- "T31TGN"
date_start <- "2018-01-01"
# date_end <- as.character(Sys.Date())
date_end <- "2018-03-31"
source("s2_list.R")

# Crée les répertoires
dir.create(file.path(rep_in, species, "s2zip"), recursive = TRUE)
dir.create(file.path(rep_in, species, "extract"), recursive = TRUE)
dir.create(file.path(rep_in, species, "calc"), recursive = TRUE)

## Recuperation de la zone interet avec code FRT ONF
# code foret a modifier pour le calul de la zone d'interet
iidtn_frt <- c("F06040H", "F07255A")

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
filtre <- ows4R::OGCFilter$new(do.call(ows4R::Or$new, lapply(iidtn_frt, function(val) {
  ows4R::PropertyIsEqualTo$new("iidtn_frt", val)
})))
# filtre <- OGCFilter$new(PropertyIsEqualTo$new("iidtn_frt", iidtn_frt))
frt_data <- frt$getFeatures(Filter = filtre)

## Etendu de la zone d'étude
extent <- frt_data

sf::write_sf(extent, file.path(rep_in, species, "extent.shp"))

# 0/ Step 0 - chargement des data THEIA
# system(paste0("fordead theia_preprocess -i ", rep_in, "/", species, "/s2zip -o ", rep_in, "/", species, "/extract -t ", tuile, " --login_theia pascal.obstetar@gmail.com --password_theia Pobf6332! --start_date ", date_start, " --end_date ", date_end, " --lim_perc_cloud 45"))
resu <- s2_list(
  tiles = c("T31TGN"),
  # time_interval = c("2018-01-01", as.character(Sys.Date())),
  time_interval = c(date_start, date_end),
  level = "l2a",
  platform = "s2a",
  time_period = "full",
  maxcloud = 45,
  collection = "sentinel2",
  path_to_download = rep_in,
  project_name = species,
  download = TRUE,
  extract = TRUE
)

# 1/ Step 1 - Calcul de l'indice de végétation et des masques :
# system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract -o ", rep_in, "/", species, "/calc -n -1 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --ignored_period ['11-01','05-01']"))
system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --extent_shape_path ", file.path(rep_in, species, "extent.shp")))

# 2/ Step 2 - Apprentissage du modèle :
system(paste0("fordead train_model -o ", rep_in, "/", species, "/calc --nb_min_date 10 --min_last_date_training ", date_start, " --max_last_date_training ", as.character(as.Date(date_start) + 360)))

# 3/ Step 3 - Détection du dépérissement :
system(paste0("fordead dieback_detection -o ", rep_in, "/", species, "/calc --threshold_anomaly 0.16 --stress_index_mode mean"))

# 4/ Step 4 - Calcul du masque forêt à partir d'OSO (17 = résineux):
system(paste0("fordead forest_mask -o ", rep_in, "/", species, "/calc -f OSO --path_oso /home/pascal/fordead_data/OCS_2021.tif --list_code_oso 17"))

# 5/ Step 5 - Export des résultats :
system(paste0("fordead export_results -o ", rep_in, "/", species, "/calc --frequency M -t 0.2 -t 0.265 -c '0-Anomalie faible' -c '1-Anomalie moyenne' -c '2-Anomalie forte'"))

