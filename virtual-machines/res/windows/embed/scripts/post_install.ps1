param(
    [Parameter(Mandatory=$true)]
    [string]$Step
)

Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$postInstallMainTaskName = 'PostInstall_Main'

function Log {
    param([string]$message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

function Invoke-Checked {
    param([scriptblock]$Action)
    $global:LASTEXITCODE = 0
    $result = & $Action
    if ($result -is [System.Diagnostics.Process]) {
        if ($result.ExitCode -ne 0) {
            throw "Exit code $($result.ExitCode)"
        }
    }
    $lex = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($lex -and $lex.Value -ne 0) {
        throw "Exit code $($lex.Value)"
    }
}

function Find-SeedDrive {
    foreach ($letter in 'DEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()) {
        if (Test-Path -LiteralPath "${letter}:\autounattend.xml") {
            return "${letter}:"
        }
    }
    throw 'Seed drive not found'
}

function Find-VirtioGuestTools {
    foreach ($letter in 'DEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()) {
        $drivePath = "${letter}:\virtio-win-guest-tools.exe"
        if (Test-Path -LiteralPath $drivePath) {
            return $drivePath
        }
    }
    throw 'VirtIO guest tools not found'
}

function AppendMachinePath {
    param([string]$path)
    $old = [Environment]::GetEnvironmentVariable('PATH', [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable('PATH', "$old;$path", [EnvironmentVariableTarget]::Machine)
    $Env:PATH = "${env:PATH};$path"
}

function Load-Config {
    param([string]$path)
    return Get-Content -Path $path | ConvertFrom-Json
}

$steps = @(
    @{ Name = 'Bootstrap'; Action = {}; Shutdown = $false; Last = $false }
    @{ Name = 'Set Windows edition'; Action = {
        # DISM may return non-zero exit code
        & DISM /online /Set-Edition:$($config.activationEdition) /ProductKey:$($config.activationKey) /AcceptEula
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Disable diagnostics reporting'; Action = {
        # Disables the "Send Diagnostic data to Microsoft" screen.
        New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -Name 'OOBE' | Out-Null
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -Value 1 -Type DWord
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Set up clock'; Action = {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -Value 1 -Type DWord
        Invoke-Checked { & tzutil /s 'UTC' }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Set hostname'; Action = {
        Rename-Computer -NewName gitea-runner-windows-2025 -Force
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Uninstall Windows Defender'; Action = {
        Uninstall-WindowsFeature -Name Windows-Defender
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Schedule main stage'; Action = {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -Step Main"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName $postInstallMainTaskName -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel 'Highest' | Out-Null
    }; Shutdown = $false; Last = $false }
    @{ Name = 'End of bootstrap stage'; Action = {}; Shutdown = $false; Last = $true }
    @{ Name = 'Main'; Action = {}; Shutdown = $false; Last = $false }
    @{ Name = 'Remove main stage scheduled task'; Action = {
        Unregister-ScheduledTask -TaskName $postInstallMainTaskName -Confirm:$false
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install VirtIO'; Action = {
        $installArgs = @(
            '/install'
            '/passive'
            '/quiet'
            '/norestart'
        )
        $drivePath = Find-VirtioGuestTools
        Invoke-Checked { Start-Process -FilePath $drivePath -ArgumentList $installArgs -Wait -PassThru }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Set up network profile'; Action = {
        $profile = Get-NetConnectionProfile
        if ($profile) {
            Set-NetConnectionProfile -Name $profile.Name -NetworkCategory Private
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install PowerShell (pwsh)'; Action = {
        $version = '7.6.3'
        $filename = "PowerShell-$version-win-x64.msi"
        $url = "https://github.com/PowerShell/PowerShell/releases/download/v$version/$filename"
        $hashSha256 = '4f574fddb567f4d0756094424a1e4e2b2bbdde21de9f0965c0f988d24dc658e4'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/package'
            $installerPath
            '/quiet'
            '/qn'
            'ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=0'
            'ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=0'
            'ENABLE_PSREMOTING=1'
            'REGISTER_MANIFEST=0'
            'USE_MU=1'
            'ENABLE_MU=1'
            'ADD_PATH=1'
            'DISABLE_TELEMETRY=1'
        )
        Invoke-Checked { Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru }
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
        # Make the command available immediately
        $pwshDir = "$Env:ProgramFiles\PowerShell\7"
        $Env:PATH = "$Env:PATH;$pwshDir"
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Set up SSH Server'; Action = {
        $pwshParams = @{
            Path         = 'HKLM:\SOFTWARE\OpenSSH'
            Name         = 'DefaultShell'
            Value        = (Get-Command pwsh.exe).Source
            PropertyType = 'String'
            Force        = $true
        }
        New-ItemProperty @pwshParams | Out-Null

        # Copy default sshd config
        New-Item -ItemType Directory -Path "$Env:ProgramData\ssh" -Force | Out-Null
        Copy-Item "$Env:SystemRoot\System32\OpenSSH\sshd_config_default" "$Env:ProgramData\ssh\sshd_config"

        # Authorize SSH public key
        Add-Content -Path $Env:ProgramData\ssh\administrators_authorized_keys -Value $($config.sshPublicKey)

        # Enable public key authentication
        (Get-Content -Path $Env:ProgramData\ssh\sshd_config) -replace '^#?PubkeyAuthentication .*', 'PubkeyAuthentication yes' | Set-Content -Path "$Env:ProgramData\ssh\sshd_config"

        # Disable password authentication
        (Get-Content -Path $Env:ProgramData\ssh\sshd_config) -replace '^#?PasswordAuthentication .*', 'PasswordAuthentication no' | Set-Content -Path "$Env:ProgramData\ssh\sshd_config"

        # Set up firewall
        if (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue) {
            Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True
        } else {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        }

        # Set up service
        Set-Service -Name sshd -StartupType Automatic
        Start-Service sshd
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Disable Administrator account'; Action = {
        Disable-LocalUser -Name 'Administrator'
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Disable local account logon'; Action = {
        $csharpCode = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath "lsa.cs") -Raw
        Add-Type -TypeDefinition $csharpCode -Language CSharp
        $err = [LsaWrapper]::SetRight("Everyone", "SeDenyInteractiveLogonRight")
        if ($err -ne 0) {
            throw "Failed to change logon rights ($err)"
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Set Windows product key'; Action = {
        Add-Content -Path "$Env:SystemRoot\System32\drivers\etc\hosts" -Value "$($config.activationServerIp) $($config.activationServer)"
        Invoke-Checked { & cscript //nologo "$Env:WINDIR\System32\slmgr.vbs" /skms $($config.activationServer) }
        Invoke-Checked { & cscript //nologo "$Env:WINDIR\System32\slmgr.vbs" /ipk $($config.activationKey) }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Microsoft Visual C++ Redistributable for Visual Studio 2017-2026'; Action = {
        $filename = 'VC_redist.x64.exe'
        $url = "https://download.visualstudio.microsoft.com/download/pr/ebdab8e5-1d7b-4d9f-a11b-cbb1720c3b12/843068991DAAA1F73AD9F6239BCE4D0F6A07A51F18C37EA2A867E9BECA71295C/$filename" # 'https://aka.ms/vc14/vc_redist.x64.exe'
        $hashSha256 = '843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/install'
            '/quiet'
        )
        Invoke-Checked { Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru }
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install 7-Zip'; Action = {
        $version = '26.02'
        $filename = "7z$($version.Replace('.', ''))-x64.exe"
        $url = "https://github.com/ip7z/7zip/releases/download/$version/$filename"
        $hashSha256 = '6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/S'
        )
        Invoke-Checked { Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru }
        $7zipDir = "$Env:ProgramFiles\7-Zip"
        AppendMachinePath -Path $7zipDir
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Git'; Action = {
        $version = '2.55.0.2'
        $tag = "v2.55.0.windows.2"
        $filename = "Git-$version-64-bit.exe"
        $url = "https://github.com/git-for-windows/git/releases/download/$tag/$filename"
        $hashSha256 = '74300da8dfe0d844c5449ffb809662f8eeac47916f83730c879c4084890c6c0e'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/VERYSILENT'
            '/NORESTART'
        )
        Invoke-Checked { Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru }
        AppendMachinePath -Path "$Env:ProgramFiles\Git\cmd"
        # Add bash and other tools bundled with Git to PATH
        AppendMachinePath -Path "$Env:ProgramFiles\Git\bin"
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Node.js'; Action = {
        $version = '24.18.0'
        $filename = "node-v$version-x64.msi"
        $url = "https://nodejs.org/dist/v$version/$filename"
        $hashSha256 = 'e30cd4ca15529583afe0efc978f1ae3ab3a93c2400c222d0752d17900552ebb3'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/package'
            $installerPath
            '/quiet'
            '/qn'
        )
        Invoke-Checked { Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru }
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Ninja'; Action = {
        $version = '1.13.2'
        $filename = 'ninja-win.zip'
        $url = "https://github.com/ninja-build/ninja/releases/download/v$version/$filename"
        $hashSha256 = '07fc8261b42b20e71d1720b39068c2e14ffcee6396b76fb7a795fb460b78dc65'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $archivePath = $drivePath
        if (-not (Test-Path -Path $archivePath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $archivePath = $tempPath
        }
        if ((Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $ninjaDir = 'C:\tools\ninja'
        New-Item -Path $ninjaDir -ItemType 'Directory' | Out-Null
        Expand-Archive -Path $archivePath -DestinationPath $ninjaDir -Force
        AppendMachinePath -Path $ninjaDir
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install CMake'; Action = {
        $version = '4.4.0'
        $filename = "cmake-$version-windows-x86_64.msi"
        $url = "https://github.com/Kitware/CMake/releases/download/v$version/$filename"
        $hashSha256 = '82db53fcb8f38be541a26093489f39d5ed79b71b53cd121fc32a022a6bf310b1'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/package'
            $installerPath
            '/quiet'
            '/qn'
        )
        Invoke-Checked { Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru }
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Python'; Action = {
        $version = '3.14.6'
        $filename = "python-$version-amd64.exe"
        $url = "https://www.python.org/ftp/python/$version/$filename"
        $hashSha256 = '14b3e9a710a3fcf0bd9b55ab6b60412bd91227563f813fc49040cabc0209e0bd'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $installerPath = $drivePath
        if (-not (Test-Path -Path $installerPath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $installerPath = $tempPath
        }
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '/quiet'
            'CompileAll=1'
            'Include_doc=0'
            'Include_test=0'
            'InstallAllUsers=1'
            'PrependPath=1'
            'Shortcuts=0'
        )
        Invoke-Checked { Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru }
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install MinGW'; Action = {
        #  GCC 15.2.0 (with POSIX threads) + MinGW-w64 14.0.0 (MSVCRT) - release 7
        $url = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/15.2.0posix-14.0.0-msvcrt-r7/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64msvcrt-14.0.0-r7.zip'
        $filename = Split-Path -Path $url -Leaf
        $hashSha256 = '9cd587d91ee7910dd8f9087e4bf9ac6b59a7ee594e1360601ba8a05355b9cefa'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $archivePath = $drivePath
        if (-not (Test-Path -Path $archivePath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $archivePath = $tempPath
        }
        if ((Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $mingwBinDir = 'C:\mingw64\bin'
        Expand-Archive -Path $archivePath -DestinationPath 'C:\' -Force
        AppendMachinePath -Path $mingwBinDir
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Gitea Runner'; Action = {
        $version = '1.0.8-sl.1'
        $filename = "gitea-runner-v$version-windows-4.0-amd64.exe.xz"
        $url = "https://github.com/gar-virt/gitea-runner/releases/download/v$version/$filename"
        $hashSha256 = '95e732097440a4b61cb6e6bf46f52de0bceb10c8c824e52f4495efdae2dfe2b4'
        $drivePath = Join-Path -Path $seedToolsDir -ChildPath $filename
        $tempPath = Join-Path -Path $Env:TEMP -ChildPath $filename
        $archivePath = $drivePath
        if (-not (Test-Path -Path $archivePath)) {
            (New-Object System.Net.WebClient).DownloadFile($url, $tempPath)
            $archivePath = $tempPath
        }
        if ((Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower() -ne $hashSha256) { throw 'Hash mismatch' }
        $runnerDir = 'C:\tools\runner'
        Invoke-Checked { & 7z x "-o$runnerDir" $archivePath }
        $runnerExe = Get-ChildItem -Path $runnerDir -Filter 'gitea-runner-*.exe'
        Rename-Item -LiteralPath $runnerExe.FullName -NewName 'gitea-runner.exe'
        AppendMachinePath -Path $runnerDir
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'Install Visual Studio 2026 Build Tools'; Action = {
        $cacheDir = Join-Path -Path $seedToolsDir -ChildPath 'vs_build_tools'
        $installerPath = Join-Path -Path $cacheDir -ChildPath 'vs_BuildTools.exe'
        $cacheHashSha256 = '07b09afd416dc05c781f171c881c23e42907eeb8d812fa1d2993dffb9323c869'
        if ((Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower() -ne $cacheHashSha256) { throw 'Hash mismatch' }
        $installArgs = @(
            '--quiet'
            '--wait'
            '--norestart'
            '--noWeb'
            '--add Microsoft.VisualStudio.Workload.VCTools'
            '--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
            '--add Microsoft.VisualStudio.Component.Windows11SDK.26100'
        )
        Invoke-Checked { Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru }
    }; Shutdown = $false; Last = $false }
    @{ Name = 'End of main stage'; Action = {}; Shutdown = $true; Last = $true }
)

$logPath = "$Env:WINDIR\Setup\Scripts\post_install.log"
Start-Transcript -Path $logPath -Append

$lastStep = $null
$errored = $false

try {
    $seedDrive = Find-SeedDrive
    $seedToolsDir = Join-Path -Path $seedDrive -ChildPath 'tools'
    $config = Load-Config (Join-Path -Path $seedDrive -ChildPath 'config.json')

    $stepStartIndex = [Array]::FindIndex($steps, [Predicate[object]]{ $args[0].Name -eq $Step })
    if ($stepStartIndex -eq -1) {
        throw "Invalid step name: $Step"
    }

    for ($stepIndex = $stepStartIndex; $stepIndex -lt $steps.Length; ++$stepIndex) {
        $lastStep = $steps[$stepIndex]
        Log "Step $($stepIndex + 1)/$($steps.Length): $($lastStep.Name)"
        try {
            & $lastStep.Action
            if ($lastStep.Last) {
                break
            }
        } catch {
            Log "Failed: $($lastStep.Name) - $($_.Exception.Message)"
            $errored = $true
            break
        }
    }
} catch {
    $errored = $true
    Log "Exception: $($_.Exception.Message)"
} finally {
    if (-not $errored -and $lastStep) {
        switch ($lastStep.Shutdown) {
            $false {}
            $true {
                Log 'Shutting down the computer.'
                Stop-Computer -Force
            }
            'Restart' {
                Log 'Restarting the computer.'
                Restart-Computer -Force
            }
        }
    }
    Stop-Transcript
    $exitCode = if ($errored) { 1 } else { 0 }
    exit $exitCode
}
