ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
RUN mkdir c:\build\nginx\source &&\
powershell -Command "wget -uri 'http://nginx.org/download/nginx-1.9.3.zip' -OutFile 'c:\nginx-1.9.3.zip'" &&\
powershell -Command "Expand-Archive -Path C:\nginx-1.9.3.zip -DestinationPath C:\nginx -Force" &&\
del c:\nginx-1.9.3.zip
USER ContainerAdministrator
RUN mkdir C:\usr\share
RUN mklink /D C:\usr\share\nginx C:\nginx\nginx-1.9.3
ADD SyncHost.exe /Windows/System32/SyncHost.exe
RUN mklink C:\Windows\System32\sync.exe C:\Windows\System32\SyncHost.exe
USER ContainerUser
WORKDIR /nginx/nginx-1.9.3
EXPOSE 80
ENTRYPOINT ["nginx.exe"]
