FROM rocker/geospatial:4.3.2

LABEL source="https://github.com/pobsteta/rstudio_fordead"
LABEL maintainer="Pascal Obstetar <pascal.obstetar@gmail.com>"

ENV FOLDER="/home/rstudio"
COPY . $FOLDER
RUN chown -R rstudio:rstudio $FOLDER

WORKDIR $FOLDER
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libsodium-dev \
    python3-distutils \
    python3-pip \
    python3-apt \
    && rm -rf /var/lib/apt/lists/* \
    && R -q -e 'install.packages("curl")'
RUN pip install -r requirements.txt
RUN git clone https://gitlab.com/fordead/fordead_package.git
RUN cd fordead_package
RUN pip install /home/rstudio/fordead_package




