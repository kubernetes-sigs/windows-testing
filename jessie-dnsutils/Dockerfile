ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
USER ContainerAdministrator
ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')); \
choco feature disable --name showDownloadProgress
ADD hostname.exe /busybox/hostname.exe
RUN powershell -Command choco install bind-toolsonly --version 9.10.3 -y
ENTRYPOINT ["cmd.exe", "/s", "/c"]
