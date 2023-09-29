FROM rocker/rstudio:4.3.1

LABEL source="https://github.com/pobsteta/rstudio_fordead"
LABEL maintainer="Pascal Obstetar <pascal.obstetar@gmail.com>"

ENV FOLDER="/home/rstudio"
COPY . $FOLDER
RUN chown -R rstudio:rstudio $FOLDER

WORKDIR $FOLDER
RUN chmod +x $FOLDER/install_geospatial.sh
RUN $FOLDER/install_geospatial.sh
RUN rm $FOLDER/install_geospatial.sh
RUN rm $FOLDER/install2.r
RUN mv $FOLDER/auth_theia.txt /usr/local/lib/R/site-library/theiaR
RUN pip install numpy fiona geopandas rasterio xarray scipy dask pathlib rioxarray path plotly==5.9.0 netcdf4 matplotlib
RUN git clone https://gitlab.com/fordead/fordead_package.git
RUN cd fordead_package
RUN pip install /home/rstudio/fordead_package




