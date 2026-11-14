param([string]$InputDoc, [string]$OutputPdf)
$ErrorActionPreference='Stop'
$wordApp=New-Object -ComObject Word.Application
try {
 $wordApp.Visible=$false
 $wordApp.DisplayAlerts=0
 $wordApp.AutomationSecurity=3
 $document=$wordApp.Documents.Open($InputDoc,$false,$true,$false)
 try {
  $document.ExportAsFixedFormat($OutputPdf,17)
  Write-Output "PAGES=$($document.ComputeStatistics(2)) PDF=$OutputPdf"
 } finally { $document.Close(0) }
} finally { $wordApp.Quit() }
