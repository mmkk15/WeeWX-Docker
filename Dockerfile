FROM nginx
LABEL maintainer="martinwiest"
ENV WVERSION="weewx-5.2.0" 
ENV WSOURCE="http://weewx.com/downloads/$WVERSION.tgz"
ENV PATH="$PATH:/home/weewx/bin"
WORKDIR /home/weewx
RUN apt-get update -y && apt-get install -y  --no-install-recommends \
	python3-pil python3-cheetah python3-mysqldb python3-pip \
	python3-configobj python3-usb python3-paho-mqtt \
	python3-ephem usbutils ftp curl wget busybox-syslogd procps gnupg \
	python3-smbus i2c-tools rtl-sdr rtl-433 && \
	apt-get autoremove && \
	wget $WSOURCE && tar xzvf $WVERSION.tgz --strip-components=1 && \
	rm -rf /var/lib/apt/lists/* $WVERSION.ta && \
	mkdir public_html
COPY src/*  /docker-entrypoint.d/
VOLUME ["/home/weewx/config"]
EXPOSE 80/tcp
