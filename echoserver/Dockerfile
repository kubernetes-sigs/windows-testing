ARG BASE_IMAGE=e2eteam/busybox:1.24
FROM $BASE_IMAGE

# RUN mkdir C:\build\openresty\source
RUN powershell -Command "wget -uri 'https://openresty.org/download/openresty-1.13.6.2-win64.zip' -OutFile 'C:\busybox\openresty-1.13.6.2-win64.zip'"
RUN powershell -Command "Expand-Archive -Path C:\busybox\openresty-1.13.6.2-win64.zip -DestinationPath C:\busybox\openresty -Force"
RUN powershell -Command "Remove-Item 'C:\busybox\openresty-1.13.6.2-win64.zip'"

USER ContainerAdministrator
ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')); \
choco feature disable --name showDownloadProgress
RUN powershell -Command choco install openssl.light -y

USER ContainerUser

RUN mkdir C:\busybox\openresty\openresty-1.13.6.2-win64\certs

ADD run.sh /busybox/openresty/openresty-1.13.6.2-win64/run.sh
ADD nginx.conf /busybox/openresty/openresty-1.13.6.2-win64/conf/nginx.conf
ADD template.lua /busybox/openresty/openresty-1.13.6.2-win64/lua/template.lua

WORKDIR /busybox/openresty/openresty-1.13.6.2-win64
EXPOSE 80 443 8080 8443
ENTRYPOINT ["/bin/sh", "/busybox/openresty/openresty-1.13.6.2-win64/run.sh"]