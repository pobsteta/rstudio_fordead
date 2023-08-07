## variables input
species <- "picea_abies"
rep_in <- "/media/obstetar/orange/data"
tuile <- "T32ULV"
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

## Etendu de la zone d'étude
# etendu <- sf::read_sf(file.path(rep_in, species, "etendu.shp"))
## Enregistre la zone dans le reprtoire de travail
# sf::write_sf(etendu, file.path(rep_in, species, "etendu.shp"))

# 0/ Step 0 - chargement des data THEIA
resu <- s2_list(
  tiles = tuile,
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
  message(paste("Calcul pour l'année", i))
  fichiers <- list.files(path = paste0(rep_in, "/", species, "/extract/", tuile), pattern = paste0("SENTINEL2[A-B]_", i), full.names = TRUE)
  
  # on divise l'extent de la dalle en 4 parts
  f <- list.files(path = fichiers[1], pattern = "B2.tif$", full.names = TRUE)
  e <- as(raster::extent(raster::raster(f)), "SpatialPolygons") |>
    sf::st_as_sf()
  sf::st_crs(e) <- sf::st_crs(raster::raster(f))
  # cree 4 polygones
  grid_sf <- sf::st_make_grid(e, cellsize = (sf::st_bbox(e)$xmax - sf::st_bbox(e)$xmin) / 2, square = TRUE) |>
    sf::st_as_sf() |> 
    dplyr::mutate(name = dplyr::row_number()) |> 
    sf::st_transform(2154)
  # sauvegarede en shape
  grid_sf |> 
    dplyr::group_by(name) |> 
    tidyr::nest() |> 
    dplyr::mutate(txt = purrr::walk2(.x = data, .y = name, ~sf::write_sf(obj = .x, paste0("p", .y, ".shp"), overwrite = TRUE)))
  
  # deplace les fichiers dans year
  system(paste0("mv ", paste(fichiers, collapse = " "), " ", file.path(rep_in, species, "extract", "year")))
  
  for (p in 1:4) {
    message(paste("Calcul pour l'année", i, "partie", p, "/ 4"))
    # message(paste("Calcul pour l'année", i))
    # 1/ Step 1 - Calcul de l'indice de végétation et des masques :
    # system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/year -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR"))
    system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/year -o ", rep_in, "/", species, "/calc/", tuile, "/", i, "/", p, " -n -1 --compress_vi --lim_perc_cloud 0.4 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --extent_shape_path ", paste0("p", p, ".shp")))
    # system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract/year -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --extent_shape_path ", file.path(rep_in, species, "extent.shp")))
    
    # 2/ Step 2 - Apprentissage du modèle :
    system(paste0("fordead train_model -o ", rep_in, "/", species, "/calc/", tuile, "/", i, "/", p, " --nb_min_date 10 --min_last_date_training ", date_start, " --max_last_date_training 2018-08-01"))
    
    # 3/ Step 3 - Détection du dépérissement :
    system(paste0("fordead dieback_detection -o ", rep_in, "/", species, "/calc/", tuile, "/", i, "/", p, " --threshold_anomaly 0.16 --stress_index_mode weighted_mean"), )
    
    # 4/ Step 4 - Calcul du masque forêt à partir d'OSO (17 = résineux):
    system(paste0("fordead forest_mask -o ", rep_in, "/", species, "/calc/", tuile, "/", i, "/", p, " -f OSO --path_oso /home/obstetar/fordead_data/OCS_2018.tif --list_code_oso 17"))
    
    # 5/ Step 5 - Export des résultats :
    system(paste0("fordead export_results -o ", rep_in, "/", species, "/calc/", tuile, "/", i, "/", p, " --start_date ", date_start, " --end_date ", date_end, " --frequency M -t 0.2 -t 0.265 -c '0-Anomalie faible' -c '1-Anomalie moyenne' -c '2-Anomalie forte'"))
    
    # # cree le repertoire
    # dir.create(file.path(rep_in, species, "final", tuile, i, p), recursive = TRUE, showWarnings = FALSE)
    # 
    # # Deplacer les resultats dans final
    # system(paste0("mv -u ", file.path(rep_in, species, "calc", "Results"), " ", file.path(rep_in, species, "final", tuile, i, p)))
    
    # attente de 5s
    Sys.sleep(5)
    
    # # supprime les calculs
    # unlink(file.path(rep_in, species, "calc"), recursive = TRUE)
    # 
    # # recree le repertoire
    # dir.create(file.path(rep_in, species, "calc"), recursive = TRUE, showWarnings = FALSE)
    
    # vide le cache de R
    gc()
  }
  # on merge les shape
  shp <- list.files(path = file.path(rep_in, species, "final", tuile, i), pattern = "periodic_results_dieback.shp", full.names = TRUE, recursive = TRUE)
  listOfShp <- lapply(shp, sf::st_read)
  combinedShp <- do.call(what = sf:::rbind.sf, args = listOfShp) |> 
    dplyr::mutate(year = substr(period, 1, 4))
  sf::write_sf(combinedShp, file.path(rep_in, species, "final", tuile, i, "periodic_results_dieback.shp"))
  
  # res <- fs::dir_ls(file.path(rep_in, species, "final", tuile, i), recurse = TRUE, glob = "*k.shp") |> 
  #   tibble::tibble() 
  #   dplyr::mutate(data = purrr::map(fname, read_sf)) |>
  #   tidyr::unnest(data) |>
  #   sf::st_as_sf() |>
  #   sf::st_set_crs(2154)
  
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
