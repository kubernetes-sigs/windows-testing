ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD port-forward-tester.exe port-forward-tester.exe
ENTRYPOINT ["/port-forward-tester.exe"]
