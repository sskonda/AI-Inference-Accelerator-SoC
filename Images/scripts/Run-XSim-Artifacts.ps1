param(
  [string]$Root = (Resolve-Path ".").Path,
  [string]$VivadoBin = "C:\Xilinx\Vivado\2024.2\bin"
)

$ErrorActionPreference = "Stop"

$ImagesDir = Join-Path $Root "Images"
$LogDir = Join-Path $ImagesDir "logs"
$WaveDir = Join-Path $ImagesDir "waves"
$VcdDir = Join-Path $ImagesDir "vcd"
$TraceDir = Join-Path $ImagesDir "traces"
$ScriptDir = Join-Path $ImagesDir "scripts"

New-Item -ItemType Directory -Force $LogDir, $WaveDir, $VcdDir, $TraceDir | Out-Null

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"

if (!(Test-Path $xvlog) -or !(Test-Path $xelab) -or !(Test-Path $xsim)) {
  throw "Vivado simulator tools were not found under $VivadoBin"
}

$sources = @(
  "-f", "rtl/files.f",
  "sim/common/protocol_compile_top.sv",
  "sim/verilator/primitive_test_top.sv",
  "sim/verilator/dma_test_top.sv",
  "sim/verilator/services_test_top.sv",
  "sim/verilator/command_test_top.sv",
  "sim/verilator/vector_test_top.sv",
  "sim/verilator/reduction_test_top.sv",
  "sim/verilator/gemm_test_top.sv",
  "Images/generated_tb/artifact_primitive_tb.sv",
  "Images/generated_tb/artifact_dma_tb.sv",
  "Images/generated_tb/artifact_services_tb.sv",
  "Images/generated_tb/artifact_command_tb.sv",
  "Images/generated_tb/artifact_vector_tb.sv",
  "Images/generated_tb/artifact_reduction_tb.sv",
  "Images/generated_tb/artifact_gemm_tb.sv"
)

Push-Location $Root
try {
  & $xvlog -sv @sources -log (Join-Path $LogDir "xsim_compile.log")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $tops = @("primitive", "dma", "services", "command", "vector", "reduction", "gemm")
  foreach ($name in $tops) {
    $top = "artifact_${name}_tb"
    & $xelab -debug typical --timescale 1ns/1ps -top $top -snapshot $top -log (Join-Path $LogDir "${name}_elab.log")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $runTcl = "Images/scripts/xsim_${name}.tcl"
    @(
      "source Images/scripts/run_xsim_artifacts.tcl",
      "run_artifact $top Images/vcd/${name}.vcd"
    ) | Set-Content -Path $runTcl -Encoding ASCII

    $runLog = Join-Path $LogDir "${name}_run.log"
    & $xsim $top -wdb "Images/waves/${name}.wdb" -tclbatch $runTcl -log $runLog
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (Select-String -Path $runLog -Pattern "^FAIL|Fatal|ERROR:" -Quiet) {
      throw "XSim run reported a failure for $top; see $runLog"
    }
    if (!(Select-String -Path $runLog -Pattern "PASS artifact_${name}_tb" -Quiet)) {
      throw "XSim run did not report PASS for $top; see $runLog"
    }
  }
} finally {
  Pop-Location
}
