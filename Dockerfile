FROM nginx
LABEL maintainer="martinwiest"
ENV WVERSION="weewx-5.2.0" 
ENV WSOURCE="http://weewx.com/downloads/$WVERSION.tgz"
ENV PATH="$PATH:/home/weewx/bin"
WORKDIR /home/weewx
RUN apt-get update -y && apt-get install -y --no-install-recommends \
	python3-pil python3-cheetah python3-mysqldb python3-pip \
	python3-configobj python3-usb python3-paho-mqtt \
	python3-ephem usbutils ftp curl wget busybox-syslogd procps gnupg \
	python3-smbus gnupg && \
	apt-get autoremove && \
	wget -qO - https://weewx.com/keys.html | sudo gpg --dearmor --output /etc/apt/trusted.gpg.d/weewx.gpg \
	echo "deb [arch=all] https://weewx.com/apt/python3 buster main" | sudo tee /etc/apt/sources.list.d/weewx.list \
	apt-get update \
	apt-get -y install weewx \
	mkdir public_html
COPY src/*  /docker-entrypoint.d/
VOLUME ["/home/weewx/config"]
EXPOSE 80/tcp
