FROM perl:5.18.2

RUN apt-get update
RUN apt-get install -y libimage-exiftool-perl libav-tools imagemagick

RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm Carton

COPY . /usr/src/media-tools
WORKDIR /usr/src/media-tools

RUN carton install --deployment

ENTRYPOINT ["carton","exec","/usr/src/media-tools/media-scanner.pl"]
