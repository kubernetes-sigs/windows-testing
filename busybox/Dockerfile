FROM microsoft/windowsservercore:1803
WORKDIR /busybox
ADD https://github.com/jhowardmsft/busybox64/raw/master/busybox.exe busybox.exe
USER ContainerAdministrator
RUN FOR /f "tokens=*" %i IN ('busybox --list') DO mklink C:\busybox\%i.exe busybox.exe
RUN setx /M PATH "C:\busybox;%PATH%"
RUN mklink /D C:\bin C:\busybox
USER ContainerUser
ENTRYPOINT ["cmd.exe", "/s", "/c"]
