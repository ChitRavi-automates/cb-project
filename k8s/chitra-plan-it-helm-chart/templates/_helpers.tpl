{{- /*
Common template helpers for the plan-it chart.
Keep a single definition per template name to avoid "multiple definition" errors.
*/ -}}

{{- /* Chart & name helpers */ -}}
{{- define "plan-it.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "plan-it.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /* Fullname helper: releaseName-nameOverride or releaseName-chartName */ -}}
{{- define "plan-it.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
  {{- $name := default .Chart.Name .Values.nameOverride -}}
  {{- if contains $name .Release.Name -}}
    {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- /* Labels and selector helpers */ -}}
{{- define "plan-it.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plan-it.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "plan-it.labels" -}}
helm.sh/chart: {{ include "plan-it.chart" . }}
{{ include "plan-it.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- /* service account helper */ -}}
{{- define "plan-it.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "plan-it.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{- default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
