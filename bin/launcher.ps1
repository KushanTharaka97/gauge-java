Param(
  [String]$TaskName # The name of the task to run
)

$DefaultDuildDir = "gauge_bin"
$PluginDir = Get-Location
$global:classpath = $env:gauge_custom_classpath
Set-Location $env:GAUGE_PROJECT_ROOT

function AddRunnerInClassPath {
  $global:classpath = $global:classpath + "$PluginDir\*" + ";" + "$PluginDir\libs\*"
}

function GetAdditionalPath() {
  param(
    $DirNames
  )
  if ("$DirNames" -eq "") {
    return ""
  }
  $libs = ""
  foreach ($dir in $DirNames.Split(",")){
    $lib = Join-Path (Get-Location) $dir
    $libs = "$lib;$libs"
  }
  return $libs 
}

function ListFiles {
  $dirs = "src"
  $files = ""
  if ("$env:gauge_custom_compile_dir" -ne "") {
    $dirs = $env:gauge_custom_compile_dir
  }
  foreach ($dir in $dirs.Split(",")) {
    $items = Get-ChildItem -Recurse -File -Include "*.java" -Path $dir | Select-Object FullName
    $files = $items.FullName.Trim() + "`n" + $files.Trim()
  }
  return $files
}

function BuildProject() {
  param(
    $classpath
  )
  Remove-Item -Recurse -Force $DefaultDuildDir -ErrorAction SilentlyContinue
  mkdir $DefaultDuildDir > $null
  $files = ListFiles
  $random = (New-Guid).ToString()
  $targetFile = Join-Path "$env:TEMP" "$random.txt"
  Write-Output $files.Trim() | Out-File -FilePath $targetFile -Encoding default -NoNewline
  javac -cp `"$global:classpath`" -encoding UTF-8 -d gauge_bin "@$targetFile"
  Remove-Item -Force $targetFile
}

function AddClassPathRequiredForExecution() {
  $additional_classpath = GetAdditionalPath "$env:gauge_additional_libs"
  if ("$additional_classpath" -ne "" ) {
    $global:classpath = "$global:classpath;$additional_classpath"
  }

  $user_classpath = GetAdditionalPath $env:gauge_custom_build_path
  if ("$user_classpath" -ne "" ) {
    $global:classpath = $global:classpath + ";" + $user_classpath
  } else {
    if ("$env:SHOULD_BUILD_PROJECT" -ne "false") {
      BuildProject
      $buildDir = Resolve-Path -Path $DefaultDuildDir
      $global:classpath = $global:classpath + ";" + $buildDir
    }
  }
}

$tasks = @{ }
$tasks.Add('init', {
    if ("$global:classpath" -eq "" ) { AddRunnerInClassPath }
    $env:CLASSPATH = $global:classpath
    java com.thoughtworks.gauge.GaugeRuntime --init
    exit
  })

$tasks.Add('start', {
    if ("$global:classpath" -eq "") {
      AddRunnerInClassPath
      AddClassPathRequiredForExecution
    }
    $env:CLASSPATH = $global:classpath
    if ("$env:GAUGE_DEBUG_OPTS" -ne "" ) {
      $debugArgs = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=$env:GAUGE_DEBUG_OPTS,timeout=25000"
      Write-Output "`nRunner Ready for Debugging"
    } 
    java  "-Dfile.encoding=UTF-8" $debugArgs $gauge_jvm_args com.thoughtworks.gauge.GaugeRuntime --start
    exit
  })

if ($tasks.ContainsKey($TaskName)) {
  Invoke-Command $tasks.Get_Item($TaskName)
}
else {
  Write-Output "Options: [init | start]"
}