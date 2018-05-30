ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD main.exe /no-snat-test.exe
ENTRYPOINT ["/no-snat-test.exe"]
