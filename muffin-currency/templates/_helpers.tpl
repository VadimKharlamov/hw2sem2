{{/*
Expand the name of the chart.
*/}}
{{- define "muffin-currency.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "muffin-currency.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "muffin-currency.labels" -}}
app: {{ include "muffin-currency.name" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "muffin-currency.selectorLabels" -}}
app: {{ include "muffin-currency.name" . }}
{{- end }}