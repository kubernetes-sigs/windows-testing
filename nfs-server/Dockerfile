ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE

USER ContainerAdministrator
RUN powershell -Command \
wget -uri 'https://kent.dl.sourceforge.net/project/winnfsd/WinNFSd/2.0/WinNFSd-2.0.zip' -OutFile 'C:\WinNFSd-2.0.zip'; \
Expand-Archive -Path C:\WinNFSd-2.0.zip -DestinationPath C:\WinNFSd -Force; \
Remove-Item 'C:\WinNFSd-2.0.zip'; \
mkdir C:\exports; \
mkdir C:\usr\sbin

EXPOSE 2049
WORKDIR /WinNFSd
ADD start.ps1 /WinNFSd/start.ps1
ADD rpc.nfsd /usr/sbin/rpc.nfsd

ENTRYPOINT ["powershell.exe", "/WinNFSd/start.ps1"]