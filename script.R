## variables input
species <- "picea_abies"
rep_in <- "/media/pascal/orange/data/"
date_start <- "2022-07-05"
date_end <- as.character(Sys.Date())

## Recuperation de la zone interet avec code FRT ONF
# code foret a modifier pour le calul de la zone d'interet
iidtn_frt <- c("F22145S", "F22180B", "F22242L")

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

#' @title s2_list
#'
#' @param time_interval Time interval
#' @param time_period Time period
#' @param level Level
#' @param maxcloud Max cloud cover
#' @param collection Collection
#' @param path_to_download Path to the project
#' @param tiles Tiles
#' @param download Download
#' @param project_name Project name
#' @param extract Extract
#'
#' @return List of products
#' @export
#'
#' @importFrom theiaR TheiaCollection
s2_list <- function(tiles = NULL,
                    time_interval = NULL,
                    time_period = "full", # temporal parameters
                    level = "l2a",
                    maxcloud = 101,
                    collection = "SENTINEL",
                    path_to_download = "~",
                    download = TRUE,
                    project_name = NULL,
                    extract = FALSE) {
  # search theiaR path
  # myauth, ce fichier contient deux lignes, la premiere est l'ID pour
  # se connecter et la deuxieme, le mot de passe. inscription sur
  # https://sso.theia-land.fr/theia/register/register.xhtml
  theia_download <- find.package("theiaR")
  myauth <- file.path(theia_download, "auth_theia.txt")

  # checks on dates
  # TODO add checks on format
  if (length(time_interval) == 1) {
    time_interval <- rep(time_interval, 2)
  }
  # split time_interval in case of seasonal download
  time_intervals <- if (time_period == "full") {
    data.frame(
      "start" = strftime(time_interval[1], "%Y-%m-%d"),
      "end" = strftime(time_interval[2], "%Y-%m-%d"),
      stringsAsFactors = FALSE
    )
  } else if (time_period == "seasonal") {
    data.frame(
      "start" = strftime(seq(time_interval[1], time_interval[2], by = "year"), "%Y-%m-%d"),
      "end" = strftime(rev(seq(time_interval[2], time_interval[1], by = "-1 year")), "%Y-%m-%d"),
      stringsAsFactors = FALSE
    )
  }

  # set level
  lev <- switch(level,
    l1c = "LEVEL1C",
    l2a = "LEVEL2A",
    l3a = "LEVEL3A",
    "LEVEL2A"
  )

  # set collection
  col <- switch(collection,
    landsat = "LANDSAT",
    spotworldheritage = "SpotWorldHeritage",
    sentinel2 = "SENTINEL2",
    snow = "Snow",
    venus = "VENUS",
    "SENTINEL2"
  )

  # create a list containing the query
  if (level == "l3a") {
    myquery <- list(
      collection = col,
      tile = tiles,
      level = lev,
      start.date = time_intervals$start,
      end.date = time_intervals$end
    )
  } else {
    myquery <- list(
      collection = col,
      tile = tiles,
      level = lev,
      start.date = time_intervals$start,
      end.date = time_intervals$end
    )
  }

  # connexion au serveur THEIA
  mycollection <- tryCatch(
    theiaR::TheiaCollection$new(
      query = myquery,
      dir.path = file.path(path_to_download, project_name, "s2zip"),
      check = TRUE
    ),
    error = function(e) print("No tiles matching search criteria!")
  )

  if (download) {
    # telechargement des dalles si elles ne sont pas encore telechargees
    files <- mycollection$status
    # w <- getOption("warn")
    # on.exit(options("warn" = w))
    # options("warn" = -1)
    for (f in seq(1:nrow(files))) {
      if (files$correct[f] == TRUE) {
        message(paste(files$tile[f], ".zip is already downloaded ! ("), f, "/", nrow(files), ")")
      } else {
        message(paste(files$tile[f], ".zip is being downloaded...("), f, "/", nrow(files), ")")
        tryCatch(mycollection$download(auth = myauth),
          error = function(e) message(paste(files$tile[f], "did not downloaded ! ("), f, "/", nrow(files), ")")
        )
      }
    } # end for
  } # endif

  if (extract) {
    mycollection$extract()
    dir.create(file.path(path_to_download, project_name, "extract"))
    system(paste0("mv \`ls -d ", path_to_download, "/", project_name, "/s2zip/*/\` ", path_to_download, "/", project_name, "/extract"))
  }

  # affichage du statut des dalles telechargees
  return(mycollection$status)
}

resu <- s2_list(
  tiles = c("T31TFN"),
  # time_interval = c("2015-01-01", as.character(Sys.Date())),
  time_interval = c(date_start, date_end),
  time_period = "full",
  level = "l2a",
  maxcloud = 100,
  collection = "sentinel2",
  # path_to_download = "/home/rstudio/data",
  path_to_download = rep_in,
  project_name = species,
  download = TRUE,
  extract = TRUE
)

# 1/ Step 1 - Calcul de l'indice de végétation et des masques :
# system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract -o ", rep_in, "/", species, "/calc -n -1 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --ignored_period ['11-01','05-01']"))
system(paste0("fordead masked_vi -i ", rep_in, "/", species, "/extract -o ", rep_in, "/", species, "/calc -n -1 --compress_vi --lim_perc_cloud 0.45 --interpolation_order 0 --sentinel_source THEIA --soil_detection --vi CRSWIR --extent_shape_path ", file.path(rep_in, species, "extent.shp")))

# 2/ Step 2 - Apprentissage du modèle :
system(paste0("fordead train_model -o ", rep_in, "/", species, "/calc --nb_min_date 10 --min_last_date_training ", date_start, " --max_last_date_training ", as.character(as.Date(date_start) + 900)))

# 3/ Step 3 - Détection du dépérissement :
system(paste0("fordead dieback_detection -o ", rep_in, "/", species, "/calc --threshold_anomaly 0.16 --stress_index_mode mean"))

# 4/ Step 4 - Calcul du masque forêt à partir d'OSO (17 = résineux):
system(paste0("fordead forest_mask -o ", rep_in, "/", species, "/calc -f OSO --path_oso /home/pascal/fordead_data/OCS_2021.tif --list_code_oso 17"))

# 5/ Step 5 - Export des résultats :
system(paste0("fordead export_results -o ", rep_in, "/", species, "/calc --frequency M -t 0.2 -t 0.265 -c '0-Anomalie faible' -c '1-Anomalie moyenne' -c '2-Anomalie forte'"))
