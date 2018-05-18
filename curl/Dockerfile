ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE AS download
ENV CURL_VERSION 7.57.0
WORKDIR /curl
ADD https://skanthak.homepage.t-online.de/download/curl-$CURL_VERSION.cab curl.cab
RUN expand /R curl.cab /F:* .

FROM $BASE_IMAGE
RUN mkdir C:\curl && setx /M PATH "C:\curl;%PATH%"
COPY --from=download /curl/AMD64/ /curl
COPY --from=download /curl/CURL.LIC /curl
ENTRYPOINT ["curl.exe"]
