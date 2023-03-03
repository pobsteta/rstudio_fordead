FROM rocker/rstudio:4.2.2

LABEL source="https://github.com/pobsteta/rstudio_fordead"

MAINTAINER Pascal Obstetar <pascal.obstetar@gmail.com>

ENV FOLDER="/home/rstudio"
COPY . $FOLDER
RUN chown -R rstudio:rstudio $FOLDER

WORKDIR $FOLDER
RUN chmod +x $FOLDER/install_geospatial.sh
RUN $FOLDER/install_geospatial.sh
RUN rm $FOLDER/install_geospatial.sh
RUN rm $FOLDER/install2.r
RUN mv $FOLDER/auth_theia.txt /usr/local/lib/R/site-library/theiaR/

