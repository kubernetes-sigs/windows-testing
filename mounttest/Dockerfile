ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE

COPY mt.exe /mounttest
COPY filePermissions.ps1 /filePermissions.ps1
ENTRYPOINT ["/mounttest"]
