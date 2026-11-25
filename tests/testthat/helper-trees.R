write_r_files <- function(dir, files) {
  for (nm in names(files)) {
    writeLines(files[[nm]], file.path(dir, nm))
  }
}

all_names <- function(node) c(node$name, unlist(lapply(node$calls, all_names)))

child_names <- function(node) vapply(node$calls, `[[`, character(1), "name")
