ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD localhost.crt localhost.crt
ADD localhost.key localhost.key
ADD porter.exe porter.exe
ENTRYPOINT ["/porter.exe"]
