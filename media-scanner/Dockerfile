FROM klieber/docker-perl

MAINTAINER Kyle Lieber <klieberuni@gmail.com>

RUN apt-get -qq update
RUN apt-get install -y libimage-exiftool-perl libav-tools imagemagick handbrake-cli
RUN apt-get clean

COPY . /app
RUN carton install

ENTRYPOINT ["carton","exec","/app/media-scanner.pl"]
