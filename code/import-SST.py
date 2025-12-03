import copernicusmarine

copernicusmarine.subset(
  dataset_id="cmems_mod_glo_phy-thetao_anfc_0.083deg_P1D-m",
  dataset_version="202406",
  variables=["thetao"],
  minimum_longitude=-74.262999,
  maximum_longitude=-71.389711,
  minimum_latitude=39.803091,
  maximum_latitude=41.431287,
  start_datetime="2022-06-01T00:00:00",
  end_datetime="2025-11-11T00:00:00",
  minimum_depth=0.49402499198913574,
  maximum_depth=0.49402499198913574,
  coordinates_selection_method="strict-inside",
  netcdf_compression_level=1,
  disable_progress_bar=True,
)
