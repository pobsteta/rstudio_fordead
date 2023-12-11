## variables input a modifier
species <- "picea_abies"
rep_in <- "~/"
tuile <- "T32ULV"
date_start <- "2018-01-01"
date_end <- as.character(Sys.Date())

# Crée les répertoires
dir.create(file.path(rep_in, species, "s2zip"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "extract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "calc"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "extract", "year"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "final", tuile), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(rep_in, species, "sensitivity", tuile), recursive = TRUE, showWarnings = FALSE)

## Recuperation de la zone interet avec code parcelle
## Etendu de la zone d'étude
# etendu <- sf::read_sf(file.path(rep_in, species, "extent.gpkg"))

## telecharge les images S2 et dézippe les fichiers avec les bandes necessaires
system(paste0("fordead theia_preprocess -i ", rep_in, "/", species, "/s2zip -o ", rep_in, "/", species, "/extract -t ", tuile, " --login_theia pascal.obstetar@gmail.com --password_theia Pobf6332! --start_date ", date_start, " --end_date ", date_end, " --lim_perc_cloud 45"))
## libere la mémoire
gc()

## on calcule les résultats à partir de l'année depuis 2018
# 1/ Step 1 - Calcul de l'indice de végétation et des masques :
system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/", tuile, " -o ", rep_in, "/", species, "/calc/", tuile, " --compress_vi --apply_source_mask --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR"))

# 2/ Step 2 - Apprentissage du modèle :
system(paste0("fordead train_model -o ", rep_in, "/", species, "/calc/", tuile, " --nb_min_date 10 --min_last_date_training ", date_start, " --max_last_date_training 2018-08-01"))

# 3/ Step 3 - Détection du dépérissement :
system(paste0("fordead dieback_detection -o ", rep_in, "/", species, "/calc/", tuile, " --threshold_anomaly 0.16 --stress_index_mode weighted_mean"))

# 4/ Step 4 - Calcul du masque forêt à partir d'OSO (17 = résineux) :
system(paste0("fordead forest_mask -o ", rep_in, "/", species, "/calc/", tuile, " -f OSO --path_oso ~/OCS_2022.tif --list_code_oso 17"))

# 5/ Step 5 - Export des résultats :
system(paste0("fordead export_results -o ", rep_in, "/", species, "/calc/", tuile, " --start_date ", date_start, " --end_date ", date_end, " --frequency M -t 0.2 -t 0.265 -c '0-Anomalie faible' -c '1-Anomalie moyenne' -c '2-Anomalie forte'"))
