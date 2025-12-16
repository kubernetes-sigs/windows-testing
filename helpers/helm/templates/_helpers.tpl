{{/*
Expand the name of the chart.
*/}}
{{- define "webhook.name" -}}
{{- if eq .Values.webhookType "hyperv" -}}
hyperv-webhook
{{- else if eq .Values.webhookType "hpc" -}}
hpc-webhook
{{- else -}}
{{ .Values.webhookType }}-webhook
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "webhook.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "webhook.name" . }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "webhook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "webhook.labels" -}}
helm.sh/chart: {{ include "webhook.chart" . }}
{{ include "webhook.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
webhook-type: {{ .Values.webhookType }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "webhook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "webhook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "webhook.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "webhook.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace name
*/}}
{{- define "webhook.namespace" -}}
{{- if .Values.namespace.name }}
{{- .Values.namespace.name }}
{{- else }}
{{- printf "%s-webhook" .Values.webhookType }}
{{- end }}
{{- end }}

{{/*
Get the image repository
Priority:
1. Full repository path if explicitly set
2. Registry + webhookType-webhook (constructed from registry value)
*/}}
{{- define "webhook.imageRepository" -}}
{{- if .Values.deployment.image.repository }}
{{- .Values.deployment.image.repository }}
{{- else }}
{{- printf "%s/%s-webhook" .Values.deployment.image.registry .Values.webhookType }}
{{- end }}
{{- end }}

{{/*
Get the certificate issuer name
*/}}
{{- define "webhook.certIssuerName" -}}
{{- if .Values.certificate.certManager.issuerRef.name }}
{{- .Values.certificate.certManager.issuerRef.name }}
{{- else }}
{{- printf "%s-webhook-selfsigned-issuer" .Values.webhookType }}
{{- end }}
{{- end }}
