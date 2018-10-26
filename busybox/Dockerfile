ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM e2eteam/curl:1803 AS prep
FROM $BASE_IMAGE

COPY --from=prep /curl/ /curl
WORKDIR /busybox
ADD busybox.exe busybox.exe
USER ContainerAdministrator
RUN FOR /f "tokens=*" %i IN ('busybox --list') DO mklink C:\busybox\%i.exe busybox.exe
RUN setx /M PATH "C:\busybox;C:\curl\;%PATH%"
RUN mklink /D C:\bin C:\busybox
RUN mkdir C:\tmp
USER ContainerUser
ENTRYPOINT ["cmd.exe", "/s", "/c"]
