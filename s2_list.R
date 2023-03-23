#' @title s2_list
#'
#' @param orbit Orbit
#' @param time_interval Time interval
#' @param time_period Time period
#' @param level Level
#' @param platform Plateform
#' @param maxcloud Max cloud cover
#' @param collection Collection
#' @param path_to_download Path to the project
#' @param tiles Tiles
#' @param download Download
#' @param project_name Project name
#' @param extract Extract files
#'
#' @return List of products
#' @export
#'
#' @importFrom theiaR TheiaCollection
s2_list <- function(tiles = NULL,
                    orbit = NULL, # spatial parameters
                    time_interval = NULL,
                    time_period = "full", # temporal parameters
                    level = "l2a",
                    platform = "s2a",
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
  
  # create a list containing the query
  myquery <- list(
    collection = "SENTINEL2",
    level = lev,
    tile = tiles,
    max.clouds = maxcloud,
    start.date = time_intervals$start,
    end.date = time_intervals$end
  )
  
  # connexion au serveur THEIA
  mycollection <- tryCatch(
    theiaR::TheiaCollection$new(
      query = myquery,
      dir.path = file.path(path_to_download, project_name, "s2zip", tiles),
      check = TRUE
    ),
    error = function(e) print("No tiles matching search criteria!")
  )
  
  if (class(mycollection)[1] == "TheiaCollection") {
    out <- mycollection$status 
  } else {
    message("No tiles matching search criteria!")
    return(NULL)
  }
  
  if (download) {
    # telechargement des dalles si elles ne sont pas encore telechargees
    files <- out
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
    files <- mycollection$status
    tryCatch(mycollection$extract(dest.dir = file.path(path_to_download, project_name, "extract", tiles)),
             error = function(e) message(paste(files$tile[f], "did not extracted !"))
    )
  } # endif
  
  # affichage du statut des dalles a telecharger
  return(mycollection$status)
}