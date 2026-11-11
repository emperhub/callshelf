# callshelf — GUI for rotate.ps1.
#
# Runs under the signed Windows PowerShell host, so it starts on machines where
# Smart App Control blocks freshly compiled, unsigned .exe files. The rotation
# itself stays in rotate.ps1 next to this file.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $root 'rotate.ps1'
if (-not (Test-Path -LiteralPath $script)) {
  [System.Windows.Forms.MessageBox]::Show(
    "ไม่พบ rotate.ps1 ในโฟลเดอร์เดียวกับแอพ`n$root",
    'callshelf',
    'OK',
    'Error') | Out-Null
  exit 1
}

$ink = [System.Drawing.Color]::FromArgb(13, 19, 23)
$soft = [System.Drawing.Color]::FromArgb(57, 69, 76)
$muted = [System.Drawing.Color]::FromArgb(100, 113, 121)
$blue = [System.Drawing.Color]::FromArgb(23, 64, 206)
$blueDeep = [System.Drawing.Color]::FromArgb(11, 42, 143)
$paper = [System.Drawing.Color]::FromArgb(233, 237, 239)
$panel = [System.Drawing.Color]::FromArgb(242, 245, 246)
$ok = [System.Drawing.Color]::FromArgb(10, 122, 80)
$bad = [System.Drawing.Color]::FromArgb(162, 67, 11)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'callshelf — เปลี่ยน IP'
$form.ClientSize = New-Object System.Drawing.Size(470, 380)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $paper
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'callshelf'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$title.ForeColor = $ink
$title.SetBounds(22, 16, 220, 32)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'เปลี่ยน IP ขาออกผ่าน Cloudflare WARP'
$subtitle.ForeColor = $muted
$subtitle.SetBounds(24, 50, 420, 20)
$form.Controls.Add($subtitle)

$ipValue = New-Object System.Windows.Forms.Label
$ipValue.Text = '—'
$ipValue.Font = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.FontStyle]::Bold)
$ipValue.ForeColor = $blueDeep
$ipValue.SetBounds(22, 86, 426, 34)
$form.Controls.Add($ipValue)

$modeValue = New-Object System.Windows.Forms.Label
$modeValue.Text = 'กำลังอ่านสถานะ…'
$modeValue.ForeColor = $muted
$modeValue.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$modeValue.SetBounds(24, 122, 426, 20)
$form.Controls.Add($modeValue)

$rotateButton = New-Object System.Windows.Forms.Button
$rotateButton.Text = 'เปลี่ยน IP'
$rotateButton.SetBounds(22, 152, 160, 44)
$rotateButton.BackColor = $blue
$rotateButton.ForeColor = [System.Drawing.Color]::White
$rotateButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$rotateButton.FlatAppearance.BorderColor = $blueDeep
$rotateButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$form.Controls.Add($rotateButton)

$autoCheck = New-Object System.Windows.Forms.CheckBox
$autoCheck.Text = 'หมุนอัตโนมัติทุก'
$autoCheck.SetBounds(200, 160, 130, 24)
$autoCheck.ForeColor = $soft
$form.Controls.Add($autoCheck)

$autoMinutes = New-Object System.Windows.Forms.NumericUpDown
$autoMinutes.Minimum = 1
$autoMinutes.Maximum = 720
$autoMinutes.Value = 10
$autoMinutes.SetBounds(332, 158, 58, 26)
$form.Controls.Add($autoMinutes)

$minuteLabel = New-Object System.Windows.Forms.Label
$minuteLabel.Text = 'นาที'
$minuteLabel.SetBounds(394, 160, 50, 22)
$minuteLabel.ForeColor = $muted
$form.Controls.Add($minuteLabel)

$statusValue = New-Object System.Windows.Forms.Label
$statusValue.Text = ''
$statusValue.ForeColor = $ok
$statusValue.SetBounds(24, 208, 426, 22)
$form.Controls.Add($statusValue)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.SetBounds(22, 236, 426, 120)
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.BackColor = $panel
$logBox.ForeColor = $soft
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($logBox)

$state = @{ job = $null; mode = 'status' }

function Write-Log([string]$text) {
  $stamp = (Get-Date).ToString('HH:mm:ss')
  $logBox.AppendText("$stamp  $text`r`n")
}

function Set-Status([string]$text, [bool]$isBad) {
  $statusValue.Text = $text
  $statusValue.ForeColor = $(if ($isBad) { $bad } else { $ok })
}

function Start-Work([bool]$doRotate) {
  if ($state.job) { return }
  $state.mode = $(if ($doRotate) { 'rotate' } else { 'status' })
  $rotateButton.Enabled = $false
  $rotateButton.Text = 'กำลังเปลี่ยน…'
  Set-Status $(if ($doRotate) { 'กำลังเปลี่ยน IP…' } else { 'กำลังอ่านสถานะ…' }) $false

  $state.job = Start-Job -ScriptBlock {
    param($path, $rotate)
    if ($rotate) { & $path -Rotate -Json } else { & $path -Json }
  } -ArgumentList $script, $doRotate
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if (-not $state.job) { return }
    $jobState = $state.job.State
    if ($jobState -eq 'Running' -or $jobState -eq 'NotStarted') { return }

    $raw = Receive-Job $state.job -ErrorAction SilentlyContinue
    Remove-Job $state.job -Force -ErrorAction SilentlyContinue
    $state.job = $null

    $rotateButton.Enabled = $true
    $rotateButton.Text = 'เปลี่ยน IP'

    $json = ($raw | Out-String).Trim()
    $data = $null
    try { $data = $json | ConvertFrom-Json } catch { }

    if (-not $data) {
      Set-Status 'อ่านผลจาก rotate.ps1 ไม่ได้' $true
      Write-Log 'อ่านผลไม่ได้'
      return
    }

    if ($state.mode -eq 'status') {
      if ($data.ok -and $data.ip) {
        $ipValue.Text = [string]$data.ip
        if ($data.mode -eq 'warp-proxy') {
          $modeValue.Text = 'WARP proxy mode · ทราฟฟิกอื่นของเครื่องไม่เปลี่ยนเส้นทาง'
        } elseif ($data.mode -eq 'full-tunnel') {
          $modeValue.Text = 'WARP full tunnel'
        } else {
          $modeValue.Text = [string]$data.mode
        }
        Set-Status '' $false
      } else {
        $modeValue.Text = 'อ่านสถานะไม่ได้'
        Set-Status $(if ($data.error) { [string]$data.error } else { 'WARP ไม่ตอบ' }) $true
      }
      return
    }

    if ($data.ok -and $data.after) {
      $ipValue.Text = [string]$data.after
      Set-Status ("{0} → {1}" -f $data.before, $data.after) $false
      Write-Log ("เปลี่ยนแล้ว: {0} → {1}" -f $data.before, $data.after)
    } else {
      $message = $(if ($data.error) { [string]$data.error } else { 'IP ยังเดิม ลองกดอีกครั้ง' })
      Set-Status $message $true
      Write-Log "ไม่สำเร็จ: $message"
    }
  })
$timer.Start()

$rotateButton.Add_Click({ Start-Work $true })

$autoTimer = New-Object System.Windows.Forms.Timer
$autoTimer.Interval = 600000
$autoTimer.Add_Tick({ Start-Work $true })

function Update-Auto {
  $autoTimer.Stop()
  if (-not $autoCheck.Checked) { return }
  $autoTimer.Interval = [int]$autoMinutes.Value * 60000
  $autoTimer.Start()
  Write-Log ("เปิดหมุนอัตโนมัติทุก {0} นาที" -f $autoMinutes.Value)
}

$autoCheck.Add_CheckedChanged({ Update-Auto })
$autoMinutes.Add_ValueChanged({ Update-Auto })

$form.Add_Shown({ Start-Work $false })

# When the launcher starts powershell with -WindowStyle Hidden, Windows passes
# that show state to the first window this process creates - which is the form.
# Show it explicitly so the app never starts invisible.
$showSig = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);'
$native = Add-Type -MemberDefinition $showSig -Name Win -Namespace Native -PassThru

$form.Add_FormClosing({
    $timer.Stop()
    $autoTimer.Stop()
    if ($state.job) {
      Stop-Job $state.job -ErrorAction SilentlyContinue
      Remove-Job $state.job -Force -ErrorAction SilentlyContinue
      $state.job = $null
    }
  })

$form.Show()
$native::ShowWindow($form.Handle, 5) | Out-Null
$native::SetForegroundWindow($form.Handle) | Out-Null

[System.Windows.Forms.Application]::Run($form)
