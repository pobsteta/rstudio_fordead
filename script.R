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
filtre <- ows4R::OGCFilter$new(do.call(ows4R::Or$new, lapply(iidtn_frt, function(val){ows4R::PropertyIsEqualTo$new("iidtn_frt", val)})))
# filtre <- OGCFilter$new(PropertyIsEqualTo$new("iidtn_frt", iidtn_frt))
frt_data <- frt$getFeatures(Filter = filtre)

## Etendu de la zone d'étude
extent <- frt_data

  
#' @title s2_list
#'
#' @param spatial_extent Spatial extent
#' @param time_interval Time interval
#' @param time_period Time period
#' @param level Level
#' @param maxcloud Max cloud cover
#' @param collection Collection
#' @param path_to_download Path to the project
#' @param tiles Tiles
#' @param download Download
#' @param project_name Project name
#'
#' @return List of products
#' @export
#'
#' @importFrom theiaR TheiaCollection
s2_list <- function(spatial_extent = NULL,
                    tiles = NULL,
                    time_interval = NULL,
                    time_period = "full", # temporal parameters
                    level = "l2a",
                    maxcloud = 101,
                    collection = "SENTINEL",
                    path_to_download = "~",
                    download = TRUE,
                    project_name = NULL) {
  # search theiaR path
  # myauth, ce fichier contient deux lignes, la premiere est l'ID pour
  # se connecter et la deuxieme, le mot de passe. inscription sur
  # https://sso.theia-land.fr/theia/register/register.xhtml
  theia_download <- find.package("theiaR")
  myauth <- file.path(theia_download, "auth_theia.txt")

  if (is.null(spatial_extent)) {
    message("Spatial_extent is NULL !")
    return(NULL)
  } else {
    spatext <- spatial_extent |>
      sf::st_geometry() |>
      sf::st_bbox()
  }

  # pass lat,lon if the bounding box is a point or line; latmin,latmax,lonmin,
  # lonmax if it is a rectangle
  if (spatext["xmin"] == spatext["xmax"] || spatext["ymin"] == spatext["ymax"]) {
    lon <- mean(spatext["xmin"], spatext["xmax"])
    lat <- mean(spatext["ymin"], spatext["ymax"])
    lonmi <- lonma <- latmi <- latma <- NULL
  } else {
    lonmi <- spatext["xmin"]
    lonma <- spatext["xmax"]
    latmi <- spatext["ymin"]
    latma <- spatext["ymax"]
    lon <- lat <- NULL
  }

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
      level = lev,
      latmin = latmi,
      latmax = latma,
      lonmin = lonmi,
      lonmax = lonma,
      start.date = time_intervals$start,
      end.date = time_intervals$end
    )
  } else {
    myquery <- list(
      collection = col,
      level = lev,
      latmin = latmi,
      latmax = latma,
      lonmin = lonmi,
      lonmax = lonma,
      start.date = time_intervals$start,
      end.date = time_intervals$end
    )
  }

  # connexion au serveur THEIA
  mycollection <- tryCatch(
    theiaR::TheiaCollection$new(
      query = myquery,
      dir.path = file.path(path_to_download, project_name),
      check = TRUE
    ),
    error = function(e) print("No tiles matching search criteria!")
  )

  if (class(mycollection)[1] == "TheiaCollection") {
    # filter mycollection with tiles
    out <- mycollection$status |>
      dplyr::filter(grepl(paste(tiles, collapse = "|"), tile))
  } else {
    message("No tiles matching search criteria!")
    return(NULL)
  }

  if (download) {
    # telechargement des dalles si elles ne sont pas encore telechargees
    files <- out
    w <- getOption("warn")
    on.exit(options("warn" = w))
    options("warn" = -1)
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

  # affichage du statut des dalles a telecharger
  return(out)
}

resu <- s2_list(
   spatial_extent = extent |> sf::st_transform(4326) |> sf::st_geometry(),
   tiles = c("31TFN"),
   time_interval = c("2015-01-01", "2022-12-31"),
   time_period = "full",
   level = "l2a",
   maxcloud = 100,
   collection = "sentinel2",
   path_to_download = "/home/rstudio/data",
   project_name = "picea_abies",
   download = TRUE
 )  
