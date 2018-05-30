ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
ADD portforwardtester.exe port-forward-tester.exe
ENTRYPOINT ["/port-forward-tester.exe"]
