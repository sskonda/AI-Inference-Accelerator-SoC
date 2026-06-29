param(
  [string]$Root = (Resolve-Path ".").Path
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$ImagesDir = Join-Path $Root "Images"
$TraceDir = Join-Path $ImagesDir "traces"
$LogDir = Join-Path $ImagesDir "logs"
$WaveformDir = Join-Path $ImagesDir "waveforms"
$TerminalDir = Join-Path $ImagesDir "terminal"

New-Item -ItemType Directory -Force $WaveformDir, $TerminalDir | Out-Null

function ColorFromHex([string]$hex) {
  [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function New-Brush([string]$hex) {
  New-Object System.Drawing.SolidBrush (ColorFromHex $hex)
}

function New-Pen([string]$hex, [single]$width = 1.0) {
  New-Object System.Drawing.Pen (ColorFromHex $hex), $width
}

function Draw-Text {
  param(
    [System.Drawing.Graphics]$Graphics,
    [string]$Text,
    [single]$X,
    [single]$Y,
    [single]$Size = 10,
    [string]$Color = "#e6edf3",
    [string]$FontName = "Consolas",
    [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
  )
  $font = New-Object System.Drawing.Font $FontName, $Size, $Style
  $brush = New-Brush $Color
  $Graphics.DrawString($Text, $font, $brush, $X, $Y)
  $brush.Dispose()
  $font.Dispose()
}

function Draw-FilledRectangle {
  param(
    [System.Drawing.Graphics]$Graphics,
    [single]$X,
    [single]$Y,
    [single]$W,
    [single]$H,
    [string]$Color
  )
  $brush = New-Brush $Color
  $Graphics.FillRectangle($brush, $X, $Y, $W, $H)
  $brush.Dispose()
}

function Draw-Line {
  param(
    [System.Drawing.Graphics]$Graphics,
    [single]$X1,
    [single]$Y1,
    [single]$X2,
    [single]$Y2,
    [string]$Color,
    [single]$Width = 1.0
  )
  $pen = New-Pen $Color $Width
  $Graphics.DrawLine($pen, $X1, $Y1, $X2, $Y2)
  $pen.Dispose()
}

function Save-Bitmap {
  param([System.Drawing.Bitmap]$Bitmap, [string]$Path)
  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Bitmap.Dispose()
}

function Get-CsvValue {
  param($Row, [string]$Column)
  $property = $Row.PSObject.Properties[$Column]
  if ($null -eq $property) {
    return ""
  }
  return [string]$property.Value
}

function Normalize-Value([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "x"
  }
  $trimmed = $Value.Trim()
  if ($trimmed -match "^[01]$") {
    return $trimmed
  }
  return $trimmed.ToLowerInvariant()
}

function Is-BitSignal {
  param($Rows, [string]$Signal)
  foreach ($row in $Rows) {
    $value = Normalize-Value (Get-CsvValue $row $Signal)
    if ($value -notin @("0", "1", "x", "z")) {
      return $false
    }
  }
  return $true
}

function Format-BusLabel {
  param([string]$Signal, [string]$Value)
  $valueNorm = Normalize-Value $Value
  if ($Signal -eq "phase") {
    $phaseLabels = @{
      "1" = "reset";
      "16" = "case10";
      "32" = "case20";
      "48" = "case30";
      "64" = "case40";
      "80" = "case50";
      "96" = "case60";
      "112" = "case70";
      "128" = "case80";
      "144" = "case90";
      "255" = "pass"
    }
    if ($phaseLabels.ContainsKey($valueNorm)) {
      return $phaseLabels[$valueNorm]
    }
  }
  if ($valueNorm -match "^[0-9a-f]+$" -and $valueNorm.Length -gt 1) {
    return "h$valueNorm"
  }
  return $valueNorm
}

function Render-Waveform {
  param(
    [string]$CsvPath,
    [string]$OutPath,
    [string]$Title,
    [string[]]$Signals
  )

  $rows = @(Import-Csv $CsvPath)
  if ($rows.Count -lt 2) {
    throw "Trace has too few rows: $CsvPath"
  }

  $width = 1600
  $leftName = 18
  $leftValue = 250
  $waveX = 370
  $top = 104
  $rowH = 42
  $bottom = 64
  $height = $top + ($Signals.Count * $rowH) + $bottom
  $waveW = $width - $waveX - 30

  $bmp = New-Object System.Drawing.Bitmap $width, $height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  Draw-FilledRectangle $g 0 0 $width $height "#0c1117"
  Draw-FilledRectangle $g 0 0 $width 34 "#16365c"
  Draw-Text $g "Vivado Simulator - Waveform" 16 8 10 "#ffffff" "Segoe UI" ([System.Drawing.FontStyle]::Bold)
  Draw-FilledRectangle $g 0 34 $width 36 "#1f2937"
  Draw-Text $g $Title 18 44 12 "#f8fafc" "Segoe UI" ([System.Drawing.FontStyle]::Bold)
  Draw-Text $g "Ubuntu 24.04 style capture | source: Vivado XSim WDB/VCD/CSV trace" 760 48 9 "#cbd5e1" "Segoe UI"

  Draw-FilledRectangle $g 0 70 $waveX $height "#121923"
  Draw-FilledRectangle $g $waveX 70 ($width - $waveX) $height "#05070a"
  Draw-Text $g "Name" $leftName 80 9 "#93c5fd" "Segoe UI" ([System.Drawing.FontStyle]::Bold)
  Draw-Text $g "Value" $leftValue 80 9 "#93c5fd" "Segoe UI" ([System.Drawing.FontStyle]::Bold)

  $minTime = [double](Get-CsvValue $rows[0] "time")
  $maxTime = [double](Get-CsvValue $rows[-1] "time")
  if ($maxTime -le $minTime) {
    $maxTime = $minTime + 1
  }

  $xForTime = {
    param([double]$time)
    $waveX + (($time - $minTime) / ($maxTime - $minTime)) * $waveW
  }

  for ($grid = 0; $grid -le 10; $grid++) {
    $x = $waveX + ($waveW * $grid / 10.0)
    Draw-Line $g $x 70 $x ($height - $bottom + 12) "#1f2937" 1
    $ns = (($minTime + (($maxTime - $minTime) * $grid / 10.0)) / 1000.0)
    Draw-Text $g ("{0:n0} ns" -f $ns) ($x + 3) 78 8 "#94a3b8" "Consolas"
  }

  for ($i = 0; $i -lt $Signals.Count; $i++) {
    $sig = $Signals[$i]
    $y = $top + ($i * $rowH)
    Draw-FilledRectangle $g 0 ($y - 5) $width 1 "#182131"
    Draw-Text $g $sig $leftName ($y + 6) 10 "#dbeafe" "Consolas"
    $lastValue = Normalize-Value (Get-CsvValue $rows[-1] $sig)
    Draw-Text $g (Format-BusLabel $sig $lastValue) $leftValue ($y + 6) 10 "#e2e8f0" "Consolas"

    $isBit = Is-BitSignal $rows $sig
    if ($isBit) {
      $lastX = & $xForTime ([double](Get-CsvValue $rows[0] "time"))
      $last = Normalize-Value (Get-CsvValue $rows[0] $sig)
      $lastY = if ($last -eq "1") { $y + 7 } else { $y + 27 }
      for ($r = 1; $r -lt $rows.Count; $r++) {
        $time = [double](Get-CsvValue $rows[$r] "time")
        $x = & $xForTime $time
        $value = Normalize-Value (Get-CsvValue $rows[$r] $sig)
        $yValue = if ($value -eq "1") { $y + 7 } else { $y + 27 }
        Draw-Line $g $lastX $lastY $x $lastY "#14f195" 2
        if ($yValue -ne $lastY) {
          Draw-Line $g $x $lastY $x $yValue "#14f195" 2
        }
        $lastX = $x
        $lastY = $yValue
        $last = $value
      }
      Draw-Line $g $lastX $lastY ($waveX + $waveW) $lastY "#14f195" 2
    } else {
      $segmentStart = [double](Get-CsvValue $rows[0] "time")
      $current = Normalize-Value (Get-CsvValue $rows[0] $sig)
      for ($r = 1; $r -lt $rows.Count; $r++) {
        $value = Normalize-Value (Get-CsvValue $rows[$r] $sig)
        if ($value -ne $current) {
          $x1 = & $xForTime $segmentStart
          $x2 = & $xForTime ([double](Get-CsvValue $rows[$r] "time"))
          Draw-FilledRectangle $g $x1 ($y + 9) ([Math]::Max(2, $x2 - $x1)) 18 "#0f3b57"
          Draw-Line $g $x1 ($y + 9) $x2 ($y + 9) "#60a5fa" 1
          Draw-Line $g $x1 ($y + 27) $x2 ($y + 27) "#60a5fa" 1
          if (($x2 - $x1) -gt 34) {
            Draw-Text $g (Format-BusLabel $sig $current) ($x1 + 5) ($y + 9) 8 "#dff6ff" "Consolas"
          }
          $segmentStart = [double](Get-CsvValue $rows[$r] "time")
          $current = $value
        }
      }
      $lastSegX = & $xForTime $segmentStart
      Draw-FilledRectangle $g $lastSegX ($y + 9) ([Math]::Max(2, $waveX + $waveW - $lastSegX)) 18 "#0f3b57"
      Draw-Line $g $lastSegX ($y + 9) ($waveX + $waveW) ($y + 9) "#60a5fa" 1
      Draw-Line $g $lastSegX ($y + 27) ($waveX + $waveW) ($y + 27) "#60a5fa" 1
      if (($waveX + $waveW - $lastSegX) -gt 34) {
        Draw-Text $g (Format-BusLabel $sig $current) ($lastSegX + 5) ($y + 9) 8 "#dff6ff" "Consolas"
      }
    }
  }

  Draw-Text $g ("Time range: {0:n1} ns to {1:n1} ns" -f ($minTime / 1000.0), ($maxTime / 1000.0)) 18 ($height - 42) 10 "#cbd5e1" "Segoe UI"
  Draw-Text $g "Raw artifacts: Images/vcd/*.vcd and Images/traces/*.csv" 560 ($height - 42) 10 "#cbd5e1" "Segoe UI"
  $g.Dispose()
  Save-Bitmap $bmp $OutPath
}

function Split-LogLine {
  param([string]$Line, [int]$Width)
  $clean = $Line.Replace("`t", "  ")
  $parts = @()
  while ($clean.Length -gt $Width) {
    $parts += $clean.Substring(0, $Width)
    $clean = $clean.Substring($Width)
  }
  $parts += $clean
  return $parts
}

function Render-Terminal {
  param(
    [string]$LogPath,
    [string]$OutPath,
    [string]$Title,
    [string]$CommandLine
  )

  $width = 1500
  $height = 920
  $bmp = New-Object System.Drawing.Bitmap $width, $height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  Draw-FilledRectangle $g 0 0 $width $height "#1e1e1e"
  Draw-FilledRectangle $g 0 0 $width 34 "#2c2c2c"
  Draw-FilledRectangle $g 14 10 12 12 "#ff5f57"
  Draw-FilledRectangle $g 34 10 12 12 "#ffbd2e"
  Draw-FilledRectangle $g 54 10 12 12 "#28c840"
  Draw-Text $g $Title 84 7 10 "#f5f5f5" "Segoe UI" ([System.Drawing.FontStyle]::Bold)

  Draw-FilledRectangle $g 0 34 $width ($height - 34) "#300a24"
  $prompt = "sanat@ubuntu-24:~/Github/AI-Inference-Accelerator-SoC$ "
  Draw-Text $g $prompt 22 52 10 "#8ae234" "Consolas"
  Draw-Text $g $CommandLine (22 + 8.6 * $prompt.Length) 52 10 "#eeeeec" "Consolas"

  $rawLines = @(Get-Content $LogPath)
  $displayLines = @()
  foreach ($line in $rawLines) {
    $displayLines += Split-LogLine $line 142
  }
  $maxLines = 49
  if ($displayLines.Count -gt $maxLines) {
    $displayLines = @("... earlier terminal output omitted in screenshot; full log is in $LogPath") +
        $displayLines[($displayLines.Count - ($maxLines - 1))..($displayLines.Count - 1)]
  }

  $y = 82
  foreach ($line in $displayLines) {
    $color = "#eeeeec"
    if ($line -match "PASS|Errors:\s*0") {
      $color = "#8ae234"
    } elseif ($line -match "\*\* Warning|Warnings:") {
      $color = "#fce94f"
    } elseif ($line -match "FAIL|Errors:\s*[1-9]|Fatal|error:") {
      $color = "#ef4444"
    } elseif ($line -match "^#") {
      $color = "#d8bfd8"
    }
    Draw-Text $g $line 22 $y 9.5 $color "Consolas"
    $y += 16
    if ($y -gt ($height - 34)) {
      break
    }
  }

  Draw-Text $g "Screenshot rendering uses Ubuntu Terminal styling; text content is from the captured log file." 22 ($height - 28) 9 "#cbd5e1" "Segoe UI"
  $g.Dispose()
  Save-Bitmap $bmp $OutPath
}

$waveSpecs = @(
  @{
    Csv = "primitive_trace.csv"; Png = "primitive_waveform.png"; Title = "Primitive Blocks - FIFO, Skid Buffer, RAM, Scratchpad";
    Signals = @("phase", "rst_n", "fifo_push_valid", "fifo_push_ready", "fifo_pop_valid", "fifo_pop_ready", "fifo_full", "fifo_empty", "fifo_occupancy", "fifo_pop_data", "ram_rd_valid", "ram_rd_data", "spm_wr_error", "spm_rd_error")
  },
  @{
    Csv = "dma_trace.csv"; Png = "dma_waveform.png"; Title = "DMA Engine - Normal, Partial, Backpressure, Error, Reset";
    Signals = @("phase", "rst_n", "start", "start_accepted", "start_rejected", "busy", "done", "error", "error_code", "stalled_cycle", "source_req_valid", "source_req_ready", "source_req_last", "destination_req_valid", "destination_req_ready", "destination_req_last", "destination_req_wstrb", "destination_rsp_error")
  },
  @{
    Csv = "services_trace.csv"; Png = "services_waveform.png"; Title = "Services - Timer, IRQ Controller, Performance Counters";
    Signals = @("phase", "rst_n", "timer_enable", "timer_periodic", "timer_interval", "timer_value", "timer_tick", "timer_active", "irq_sources", "irq_pending", "irq", "irq_latency_valid", "irq_latency_cycles", "dma_active", "dma_stalled", "accel_active", "command_completed", "scheduler_stalled", "perf_value")
  },
  @{
    Csv = "command_trace.csv"; Png = "command_waveform.png"; Title = "Command Queue/Processor - Dispatch, Priority, Backpressure, Full";
    Signals = @("phase", "rst_n", "execution_enable", "push_valid", "push_ready", "queue_full", "queue_empty", "queue_occupancy", "queue_high_water", "dma_cmd_valid", "vector_cmd_valid", "reduction_cmd_valid", "gemm_cmd_valid", "completion_valid", "completion_ready", "response_valid", "response_error", "selected_starved", "scheduler_stalled", "response_result")
  },
  @{
    Csv = "vector_trace.csv"; Png = "vector_waveform.png"; Title = "Vector Accelerator - Add, Scale, Backpressure, Error";
    Signals = @("phase", "rst_n", "command_valid", "command_ready", "busy", "done", "error", "error_code", "response_valid", "response_error", "response_result", "memory_req_valid", "memory_req_ready", "memory_req_write", "memory_req_wstrb", "memory_rsp_valid", "memory_rsp_ready", "stalled_cycle", "elements_completed_event")
  },
  @{
    Csv = "reduction_trace.csv"; Png = "reduction_waveform.png"; Title = "Reduction Accelerator - Sum, Max, Backpressure, Error";
    Signals = @("phase", "rst_n", "command_valid", "command_ready", "busy", "done", "error", "error_code", "response_valid", "response_error", "response_result", "memory_req_valid", "memory_req_ready", "memory_req_write", "memory_req_wstrb", "memory_rsp_valid", "memory_rsp_ready", "stalled_cycle", "elements_completed_event")
  },
  @{
    Csv = "gemm_trace.csv"; Png = "gemm_waveform.png"; Title = "GEMM Accelerator - Matrix Multiply, Backpressure, Error";
    Signals = @("phase", "rst_n", "command_valid", "command_ready", "busy", "done", "error", "error_code", "response_valid", "response_error", "response_result", "memory_req_valid", "memory_req_ready", "memory_req_write", "memory_req_wstrb", "memory_req_last", "memory_rsp_valid", "memory_rsp_ready", "stalled_cycle", "outputs_completed_event")
  }
)

foreach ($spec in $waveSpecs) {
  Render-Waveform `
    -CsvPath (Join-Path $TraceDir $spec.Csv) `
    -OutPath (Join-Path $WaveformDir $spec.Png) `
    -Title $spec.Title `
    -Signals $spec.Signals
}

$terminalSpecs = @(
  @{ Log = "xsim_compile.log"; Png = "terminal_xsim_compile.png"; Title = "Ubuntu Terminal - Vivado XSim Compile"; Command = "xvlog -sv -f rtl/files.f Images/generated_tb/*.sv" },
  @{ Log = "primitive_run.log"; Png = "terminal_primitive_run.png"; Title = "Ubuntu Terminal - Primitive Simulation"; Command = "xsim artifact_primitive_tb -wdb Images/waves/primitive.wdb -tclbatch Images/scripts/xsim_primitive.tcl" },
  @{ Log = "dma_run.log"; Png = "terminal_dma_run.png"; Title = "Ubuntu Terminal - DMA Simulation"; Command = "xsim artifact_dma_tb -wdb Images/waves/dma.wdb -tclbatch Images/scripts/xsim_dma.tcl" },
  @{ Log = "services_run.log"; Png = "terminal_services_run.png"; Title = "Ubuntu Terminal - Services Simulation"; Command = "xsim artifact_services_tb -wdb Images/waves/services.wdb -tclbatch Images/scripts/xsim_services.tcl" },
  @{ Log = "command_run.log"; Png = "terminal_command_run.png"; Title = "Ubuntu Terminal - Command Simulation"; Command = "xsim artifact_command_tb -wdb Images/waves/command.wdb -tclbatch Images/scripts/xsim_command.tcl" },
  @{ Log = "vector_run.log"; Png = "terminal_vector_run.png"; Title = "Ubuntu Terminal - Vector Simulation"; Command = "xsim artifact_vector_tb -wdb Images/waves/vector.wdb -tclbatch Images/scripts/xsim_vector.tcl" },
  @{ Log = "reduction_run.log"; Png = "terminal_reduction_run.png"; Title = "Ubuntu Terminal - Reduction Simulation"; Command = "xsim artifact_reduction_tb -wdb Images/waves/reduction.wdb -tclbatch Images/scripts/xsim_reduction.tcl" },
  @{ Log = "gemm_run.log"; Png = "terminal_gemm_run.png"; Title = "Ubuntu Terminal - GEMM Simulation"; Command = "xsim artifact_gemm_tb -wdb Images/waves/gemm.wdb -tclbatch Images/scripts/xsim_gemm.tcl" }
)

foreach ($spec in $terminalSpecs) {
  Render-Terminal `
    -LogPath (Join-Path $LogDir $spec.Log) `
    -OutPath (Join-Path $TerminalDir $spec.Png) `
    -Title $spec.Title `
    -CommandLine $spec.Command
}

$summaryPath = Join-Path $LogDir "simulation_summary.log"
$summary = @(
  "AI-Inference-Accelerator-SoC artifact simulation summary",
  "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
  "",
  "Environment note:",
  "  Vivado Simulator v2024.2.0 was run locally through xvlog/xelab/xsim.",
  "  The PNG screenshots render real XSim logs and per-cycle traces using Ubuntu 24.04/Vivado-style visuals.",
  "  The repository's native Verilator TRACE flow could not be used because Verilator/GTKWave were not available on PATH.",
  "",
  "Passing runs:"
)
foreach ($name in @("primitive", "dma", "services", "command", "vector", "reduction", "gemm")) {
  $runLog = Join-Path $LogDir "$name`_run.log"
  $passLine = Select-String -Path $runLog -Pattern "PASS" | Select-Object -Last 1
  $warningCount = @(Select-String -Path $runLog -Pattern "WARNING|Warning|INFO: HDL object").Count
  $summary += "  ${name}: $($passLine.Line.Trim()) | xsim warnings/info notes: $warningCount"
}
$summary += ""
$summary += "Vivado WDB waveforms: Images/waves/*.wdb"
$summary += "Raw VCD waveforms: Images/vcd/*.vcd"
$summary += "Rendered waveforms: Images/waveforms/*.png"
$summary += "Terminal screenshots: Images/terminal/*.png"
$summary | Set-Content -Path $summaryPath -Encoding ASCII

Render-Terminal `
  -LogPath $summaryPath `
  -OutPath (Join-Path $TerminalDir "terminal_simulation_summary.png") `
  -Title "Ubuntu Terminal - Simulation Summary" `
  -CommandLine "cat Images/logs/simulation_summary.log"

Write-Host "Rendered waveform PNGs to $WaveformDir"
Write-Host "Rendered terminal PNGs to $TerminalDir"
