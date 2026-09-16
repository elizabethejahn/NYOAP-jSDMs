if("r-nao-gfs" %ni% reticulate::conda_list()$name){
reticulate::conda_create(
  "r-nao-gfs",
  packages = c(
    "python=3.12", "numpy", "pandas", "xarray", "dask",
    "netcdf4", "cfgrib", "eccodes","herbie-data","copernicusmarine"
  ),
  channel = "conda-forge"
)
# reticulate::conda_install(packages = "herbie-data", channel = "conda-forge")
}

library(reticulate)
use_condaenv("r-nao-gfs", required = TRUE)

py_run_string("from herbie import Herbie; print('Herbie import OK')")

py_run_string("import copernicusmarine")

py_config()

library(copernicusR)
# setup copernicusR environment to download environmental data
setup_copernicus(username = Sys.getenv("COPERNICUS_USERNAME"), password = Sys.getenv("COPERNICUS_PASSWORD"))
copernicus_is_ready()
