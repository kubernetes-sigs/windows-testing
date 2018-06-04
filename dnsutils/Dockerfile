FROM atuvenie/busybox:1.24
USER ContainerAdministrator
ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')); \
choco feature disable --name showDownloadProgress
ADD hostname.exe /busybox/hostname
RUN powershell -Command choco install bind-toolsonly -y
ENTRYPOINT ["cmd.exe", "/s", "/c"]
