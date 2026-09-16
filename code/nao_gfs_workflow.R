# Workflow: forecast a daily/weekly NAO index from archived NOAA GFS Z500 fields.
#
# Default index:
#   NOAA PSL-style NAO proxy = standardized 500-hPa height anomaly contrast
#   between the subtropical North Atlantic and Iceland/Greenland sector.
#
# Python environment setup, once:
#   install.packages(c("reticulate", "dplyr", "purrr", "readr", "tibble"))
#   reticulate::conda_create(
#     "r-nao-gfs",
#     packages = c(
#       "python=3.11", "numpy", "pandas", "xarray", "dask",
#       "netcdf4", "cfgrib", "eccodes"
#     ),
#     channel = "conda-forge"
#   )
#   reticulate::conda_install(packages ="herbie-data", channel = "conda-forge")

use_condaenv("r-nao-gfs", required = TRUE)

py_run_string('
from pathlib import Path
import math
import os

import numpy as np
import pandas as pd
import xarray as xr


def _coord_name(obj, candidates):
    for name in candidates:
        if name in obj.coords:
            return name
        if name in obj.dims:
            return name
    raise ValueError(f"None of these coordinates found: {candidates}")


def _z500_var_name(ds):
    for name in ["gh", "hgt", "z"]:
        if name in ds.data_vars:
            return name
    if len(ds.data_vars) == 1:
        return list(ds.data_vars)[0]
    raise ValueError(f"Could not identify Z500 variable from {list(ds.data_vars)}")


def _select_if_dimension(da, coord_name, value):
    """Select a level only when coord_name is an indexable dimension."""
    if coord_name not in da.coords and coord_name not in da.dims:
        return da
    if coord_name in da.dims:
        coord = da[coord_name]
        if coord.size > 1:
            return da.sel({coord_name: value})
        return da.isel({coord_name: 0}, drop=True)
    return da


def _standardize_longitudes(da):
    lon_name = _coord_name(da, ["longitude", "lon"])
    lon = da[lon_name]
    if float(lon.min()) < 0:
        da = da.assign_coords({lon_name: (lon % 360)})
        da = da.sortby(lon_name)
    return da


def _lat_subset(da, lat_min, lat_max):
    lat_name = _coord_name(da, ["latitude", "lat"])
    lat = da[lat_name]
    if float(lat[0]) > float(lat[-1]):
        return da.sel({lat_name: slice(lat_max, lat_min)})
    return da.sel({lat_name: slice(lat_min, lat_max)})


def _lon_subset(da, lon_min, lon_max):
    da = _standardize_longitudes(da)
    lon_name = _coord_name(da, ["longitude", "lon"])
    lon_min = lon_min % 360
    lon_max = lon_max % 360
    if lon_min <= lon_max:
        return da.sel({lon_name: slice(lon_min, lon_max)})
    left = da.sel({lon_name: slice(lon_min, 360)})
    right = da.sel({lon_name: slice(0, lon_max)})
    return xr.concat([left, right], dim=lon_name)


def area_mean(da, lat_min, lat_max, lon_min, lon_max):
    da = _lat_subset(da, lat_min, lat_max)
    da = _lon_subset(da, lon_min, lon_max)
    lat_name = _coord_name(da, ["latitude", "lat"])
    lon_name = _coord_name(da, ["longitude", "lon"])
    weights = np.cos(np.deg2rad(da[lat_name]))
    return da.weighted(weights).mean(dim=[lat_name, lon_name])


def psl_nao_contrast_from_z500(da):
    """Positive values mean high subtropical Z500 relative to the Icelandic sector."""
    south = area_mean(da, 35, 45, -70, -10)
    north = area_mean(da, 55, 70, -70, -10)
    return south - north


def fetch_gfs_z500(init_date, fxx, cycle="00", product="pgrb2.0p25", save_dir="data/gfs"):
    from herbie import Herbie

    init_ymd = pd.Timestamp(init_date).strftime("%Y-%m-%d")
    dt = f"{init_ymd} {cycle}:00"
    H = Herbie(
        dt,
        model="gfs",
        product=product,
        fxx=int(fxx),
        save_dir=save_dir
    )

    try:
        ds = H.xarray(":HGT:500 mb:")
    except TypeError:
        ds = H.xarray(searchString=":HGT:500 mb:")

    zname = _z500_var_name(ds)
    da = ds[zname]
    da = _select_if_dimension(da, "isobaricInhPa", 500)
    da = _select_if_dimension(da, "level", 500)
    da = da.squeeze(drop=True)

    if "valid_time" in ds.coords:
        valid_time = pd.Timestamp(ds["valid_time"].values)
    else:
        valid_time = pd.Timestamp(dt) + pd.Timedelta(hours=int(fxx))

    return da, valid_time


def gfs_psl_nao_raw(init_date, end_date, cycle="00", include_init=False,
                    product="pgrb2.0p25", save_dir="data/gfs"):
    init = pd.Timestamp(init_date)
    end = pd.Timestamp(end_date)
    first_fxx = 0 if include_init else 24
    last_fxx = int((end - init).total_seconds() / 3600)
    if last_fxx < first_fxx:
        raise ValueError("end_date must be after init_date")

    rows = []
    for fxx in range(first_fxx, last_fxx + 1, 24):
        da, valid_time = fetch_gfs_z500(
            init_date=init,
            fxx=fxx,
            cycle=cycle,
            product=product,
            save_dir=save_dir
        )
        contrast = psl_nao_contrast_from_z500(da)
        rows.append({
            "init_date": init.date().isoformat(),
            "cycle": cycle,
            "fxx": fxx,
            "valid_time": valid_time.isoformat(),
            "nao_raw_gpm": float(contrast.values)
        })
    return pd.DataFrame(rows)


def _open_reanalysis_z500(year):
    url = (
        "https://psl.noaa.gov/thredds/dodsC/"
        f"Datasets/ncep.reanalysis.dailyavgs/pressure/hgt.{int(year)}.nc"
    )
    ds = xr.open_dataset(url)
    da = ds["hgt"]
    if "level" in da.coords:
        da = da.sel(level=500)
    return da


def build_psl_nao_climatology(year_start=1981, year_end=2010,
                              cache_file="data/nao_psl_climatology_1981_2010.csv"):
    cache = Path(cache_file)
    if cache.exists():
        return pd.read_csv(cache)

    rows = []
    for year in range(int(year_start), int(year_end) + 1):
        da = _open_reanalysis_z500(year)
        contrast = psl_nao_contrast_from_z500(da)
        tmp = pd.DataFrame({
            "date": pd.to_datetime(contrast["time"].values),
            "nao_raw_gpm": np.asarray(contrast.values, dtype=float)
        })
        rows.append(tmp)

    base = pd.concat(rows, ignore_index=True)
    base = base[base["date"].dt.strftime("%m-%d") != "02-29"].copy()
    base["month_day"] = base["date"].dt.strftime("%m-%d")

    daily_mean = (
        base.groupby("month_day", as_index=False)["nao_raw_gpm"]
        .mean()
        .rename(columns={"nao_raw_gpm": "clim_mean_gpm"})
    )
    base = base.merge(daily_mean, on="month_day", how="left")
    scale = float((base["nao_raw_gpm"] - base["clim_mean_gpm"]).std(ddof=1))
    daily_mean["clim_sd_gpm"] = scale

    cache.parent.mkdir(parents=True, exist_ok=True)
    daily_mean.to_csv(cache, index=False)
    return daily_mean


def forecast_nao_window(init_date, end_date, cycle="00", include_init=False,
                        product="pgrb2.0p25", save_dir="data/gfs",
                        clim_cache="data/nao_psl_climatology_1981_2010.csv",
                        clim_year_start=1981, clim_year_end=2010):
    raw = gfs_psl_nao_raw(
        init_date=init_date,
        end_date=end_date,
        cycle=cycle,
        include_init=include_init,
        product=product,
        save_dir=save_dir
    )
    clim = build_psl_nao_climatology(
        year_start=clim_year_start,
        year_end=clim_year_end,
        cache_file=clim_cache
    )

    raw["valid_date"] = pd.to_datetime(raw["valid_time"]).dt.date.astype(str)
    raw["month_day"] = pd.to_datetime(raw["valid_time"]).dt.strftime("%m-%d")
    out = raw.merge(clim, on="month_day", how="left")
    out["nao_index"] = (out["nao_raw_gpm"] - out["clim_mean_gpm"]) / out["clim_sd_gpm"]
    return out


def summarize_nao_windows(windows, cycle="00", include_init=False,
                          product="pgrb2.0p25", save_dir="data/gfs",
                          clim_cache="data/nao_psl_climatology_1981_2010.csv",
                          clim_year_start=1981, clim_year_end=2010):
    daily = []
    for row in windows:
        daily.append(forecast_nao_window(
            init_date=row["init_date"],
            end_date=row["end_date"],
            cycle=cycle,
            include_init=include_init,
            product=product,
            save_dir=save_dir,
            clim_cache=clim_cache,
            clim_year_start=clim_year_start,
            clim_year_end=clim_year_end
        ))

    daily = pd.concat(daily, ignore_index=True)
    weekly = (
        daily.groupby(["init_date", "cycle"], as_index=False)
        .agg(
            window_start=("valid_date", "min"),
            window_end=("valid_date", "max"),
            n_days=("nao_index", "size"),
            nao_mean=("nao_index", "mean"),
            nao_sd=("nao_index", "std"),
            nao_min=("nao_index", "min"),
            nao_max=("nao_index", "max")
        )
    )
    return {
        "daily": daily.to_dict(orient="records"),
        "weekly": weekly.to_dict(orient="records")
    }
')


nao_windows <- tibble::tribble(
  ~init_date,    ~end_date,
  "2024-08-01", "2024-08-08",
  "2024-08-08", "2024-08-15",
  "2024-08-15", "2024-08-23",
  "2024-08-23", "2024-08-31"
)


run_nao_forecast_windows <- function(
    windows = nao_windows,
    cycle = "00",
    include_init = FALSE,
    save_dir = here("data/gfs"),
    clim_cache = here("data/environmental/nao_psl_climatology_1981_2010.csv"),
    out_dir = here("data/gfs/outputs")) {
  
  py_windows <- purrr::transpose(windows)
  
  res <- py$summarize_nao_windows(
    windows = py_windows,
    cycle = cycle,
    include_init = include_init,
    save_dir = save_dir,
    clim_cache = clim_cache
  )
  
  daily <- py_to_r(res[["daily"]]) %>%
    dplyr::bind_rows() %>%
    mutate(
      init_date = as.Date(init_date),
      valid_date = as.Date(valid_date)
    )
  
  weekly <- py_to_r(res[["weekly"]]) %>%
    dplyr::bind_rows() %>%
    mutate(
      init_date = as.Date(init_date),
      window_start = as.Date(window_start),
      window_end = as.Date(window_end)
    )
  
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(daily, file.path(out_dir, "nao_gfs_daily.csv"))
  readr::write_csv(weekly, file.path(out_dir, "nao_gfs_weekly.csv"))
  
  list(daily = daily, weekly = weekly)
}


# Example:
res <<- run_nao_forecast_windows()
res$weekly
