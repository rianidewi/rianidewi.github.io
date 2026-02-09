param([string]$RepoRoot = (Get-Location).Path,[switch]$Push,[string]$Message = 'Publish update')

$ErrorActionPreference = 'Stop'

function Get-YamlValue($lines, $key) {
  $pattern = "^\s*$key\s*:\s*(.+?)\s*$"
  foreach ($line in $lines) {
    if ($line -match $pattern) {
      return $Matches[1]
    }
  }
  return $null
}

function HtmlEncode([string]$text) {
  if ($null -eq $text) { return '' }
  return ($text -replace '&', '&amp;') -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}

function Normalize-PathUrl([string]$url) {
  if ([string]::IsNullOrWhiteSpace($url)) { return '' }
  $value = $url.Trim()
  if ($value.StartsWith('/portfolio/')) {
    $value = $value.Substring('/portfolio/'.Length)
  }
  if ($value.StartsWith('/')) { $value = $value.TrimStart('/') }
  return $value
}

$root = Resolve-Path $RepoRoot
$repoPath = $root.Path
$demoPortal = Join-Path $repoPath 'demo-portal'
$templatePath = Join-Path $demoPortal 'src/main/resources/templates/index.html'
$appConfigPath = Join-Path $demoPortal 'src/main/resources/application.yml'
$stylesSrc = Join-Path $demoPortal 'src/main/resources/static/styles.css'
$imagesSrc = Join-Path $demoPortal 'src/main/resources/static/images'
$previewsSrc = Join-Path $demoPortal 'src/main/resources/static/images/previews'
$resumeDir = Join-Path $repoPath 'resume'
$indexOut = Join-Path $repoPath 'index.html'

if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
if (-not (Test-Path $appConfigPath)) { throw "Missing config: $appConfigPath" }

$yaml = Get-Content -Path $appConfigPath
$url = Get-YamlValue $yaml 'url'
$user = Get-YamlValue $yaml 'username'
$pass = Get-YamlValue $yaml 'password'
if (-not $url -or -not $user -or -not $pass) {
  throw "Database config missing in application.yml"
}

$jarPath = Join-Path $repoPath 'tools/lib/postgresql.jar'
if (-not (Test-Path $jarPath)) {
  $jarUrl = 'https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.3/postgresql-42.7.3.jar'
  Invoke-WebRequest -Uri $jarUrl -OutFile $jarPath
}

$javaSrc = Join-Path $repoPath 'tools/ExportProjects.java'
$javaOutDir = Join-Path $repoPath 'tools/bin'
New-Item -ItemType Directory -Path $javaOutDir -Force | Out-Null

$javaClass = Join-Path $javaOutDir 'ExportProjects.class'
$needsCompile = -not (Test-Path $javaClass) -or ((Get-Item $javaSrc).LastWriteTime -gt (Get-Item $javaClass).LastWriteTime)
if ($needsCompile) {
  & javac -cp $jarPath -d $javaOutDir $javaSrc
}

$projectJson = & java -cp "$jarPath;$javaOutDir" ExportProjects $url $user $pass
$projects = $projectJson | ConvertFrom-Json

$active = $projects | Where-Object { $_.status -ne 'ARCHIVED' }
$personal = $active | Where-Object { $_.type -eq 'PERSONAL' }
$experience = $active | Where-Object { $_.type -eq 'EXPERIENCE' }

function Sort-Projects($list) {
  return $list | Sort-Object @{Expression = { if ($_.sortOrder -eq $null) { [int]::MaxValue } else { $_.sortOrder } }}, @{Expression = { $_.id }; Descending = $true }
}

$personal = Sort-Projects $personal
$experience = Sort-Projects $experience

$personalHtml = New-Object System.Text.StringBuilder
if ($personal.Count -eq 0) {
  $null = $personalHtml.AppendLine('          <article class="project-card has-preview">')
  $null = $personalHtml.AppendLine('            <div class="project-preview">')
  $null = $personalHtml.AppendLine('              <img src="images/previews/coming-soon.svg" alt="Coming soon preview" referrerpolicy="no-referrer" loading="lazy" />')
  $null = $personalHtml.AppendLine('            </div>')
  $null = $personalHtml.AppendLine('            <h3>Coming Soon</h3>')
  $null = $personalHtml.AppendLine('            <p>')
  $null = $personalHtml.AppendLine('              Placeholder for a personal project showcase.')
  $null = $personalHtml.AppendLine('            </p>')
  $null = $personalHtml.AppendLine('            <div class="chip-row">')
  $null = $personalHtml.AppendLine('              <span>Personal</span>')
  $null = $personalHtml.AppendLine('              <span>In Progress</span>')
  $null = $personalHtml.AppendLine('            </div>')
  $null = $personalHtml.AppendLine('            <span class="card-link">Details Soon</span>')
  $null = $personalHtml.AppendLine('          </article>')
} else {
  foreach ($p in $personal) {
    $title = HtmlEncode $p.title
    $summary = HtmlEncode $p.summary
    $tags = @()
    if ($p.tags) {
      $tags = $p.tags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    $tagAttr = ($p.tags ?? '').ToLower()
    $preview = Normalize-PathUrl $p.previewImage
    if (-not $preview) { $preview = 'images/previews/coming-soon.svg' }
    $sourceUrl = Normalize-PathUrl $p.sourceUrl
    $demoUrl = $p.demoUrl
    $isPreview = $false
    if ($sourceUrl -match '^preview/') { $isPreview = $true }

    $null = $personalHtml.AppendLine("          <article class=\"project-card has-preview\" data-tags=\"$tagAttr\">")
    $null = $personalHtml.AppendLine('            <div class="project-preview">')
    $null = $personalHtml.AppendLine("              <img src=\"$preview\" alt=\"$title preview\" referrerpolicy=\"no-referrer\" loading=\"lazy\" />")
    $null = $personalHtml.AppendLine('            </div>')
    $null = $personalHtml.AppendLine("            <h3>$title</h3>")
    $null = $personalHtml.AppendLine("            <p>$summary</p>")
    if ($tags.Count -gt 0) {
      $null = $personalHtml.AppendLine('            <div class="chip-row">')
      foreach ($tag in $tags) {
        $null = $personalHtml.AppendLine("              <span>$(HtmlEncode $tag)</span>")
      }
      $null = $personalHtml.AppendLine('            </div>')
    }
    if ($sourceUrl -or $demoUrl) {
      $null = $personalHtml.AppendLine('            <div class="card-actions">')
      if ($sourceUrl) {
        if ($isPreview) {
          $null = $personalHtml.AppendLine("              <a class=\"icon-btn code\" href=\"$sourceUrl\" title=\"Preview\" aria-label=\"Preview\">")
          $null = $personalHtml.AppendLine('                <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">')
          $null = $personalHtml.AppendLine('                  <path d="M8 5v14l11-7-11-7z"/>')
          $null = $personalHtml.AppendLine('                </svg>')
          $null = $personalHtml.AppendLine('              </a>')
        } else {
          $null = $personalHtml.AppendLine("              <a class=\"icon-btn code\" href=\"$sourceUrl\" title=\"Open Source Code\" aria-label=\"Open Source Code\">&lt;/&gt;</a>")
        }
      }
      if ($demoUrl) {
        $null = $personalHtml.AppendLine("              <a class=\"icon-btn github\" href=\"$demoUrl\" target=\"_blank\" rel=\"noopener\" title=\"GitHub Repo\" aria-label=\"GitHub Repo\">")
        $null = $personalHtml.AppendLine('                <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">')
        $null = $personalHtml.AppendLine('                  <path d="M12 .6a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2.2c-3.3.7-4-1.4-4-1.4-.6-1.4-1.4-1.8-1.4-1.8-1.2-.8.1-.8.1-.8 1.3.1 2 1.4 2 1.4 1.2 2 3.1 1.4 3.9 1.1.1-.9.5-1.4.8-1.7-2.7-.3-5.5-1.3-5.5-6.1 0-1.4.5-2.6 1.3-3.5-.1-.3-.6-1.6.1-3.3 0 0 1-.3 3.6 1.3a12.5 12.5 0 0 1 6.6 0c2.5-1.6 3.6-1.3 3.6-1.3.7 1.7.2 3 .1 3.3.8.9 1.3 2 1.3 3.5 0 4.8-2.8 5.8-5.5 6.1.5.4.9 1.1.9 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .6z"/>')
        $null = $personalHtml.AppendLine('                </svg>')
        $null = $personalHtml.AppendLine('              </a>')
      }
      $null = $personalHtml.AppendLine('            </div>')
    }
    $null = $personalHtml.AppendLine('          </article>')
  }
}

$experienceHtml = New-Object System.Text.StringBuilder
foreach ($p in $experience) {
  $title = HtmlEncode $p.title
  $summary = HtmlEncode $p.summary
  $tags = @()
  if ($p.tags) {
    $tags = $p.tags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
  $sourceUrl = Normalize-PathUrl $p.sourceUrl
  $demoUrl = $p.demoUrl
  $slug = $p.slug

  $null = $experienceHtml.AppendLine('          <article class="project-card">')
  $null = $experienceHtml.AppendLine("            <h3>$title</h3>")
  $null = $experienceHtml.AppendLine("            <p>$summary</p>")
  if ($tags.Count -gt 0) {
    $null = $experienceHtml.AppendLine('            <div class="chip-row">')
    foreach ($tag in $tags) {
      $null = $experienceHtml.AppendLine("              <span>$(HtmlEncode $tag)</span>")
    }
    $null = $experienceHtml.AppendLine('            </div>')
  }
  $null = $experienceHtml.AppendLine('            <div class="card-actions">')
  if ($slug) {
    $null = $experienceHtml.AppendLine("              <a class=\"icon-btn code\" href=\"demo/workflows/$slug.html\" title=\"Preview\" aria-label=\"Preview\">&lt;/&gt;</a>")
  } elseif ($sourceUrl) {
    $null = $experienceHtml.AppendLine("              <a class=\"icon-btn code\" href=\"$sourceUrl\" title=\"Open Source Code\" aria-label=\"Open Source Code\">&lt;/&gt;</a>")
  } else {
    $null = $experienceHtml.AppendLine('              <span class="icon-btn disabled" title="Details soon" aria-label="Details soon">…</span>')
  }
  if ($slug) {
    $null = $experienceHtml.AppendLine("              <a class=\"icon-btn demo\" href=\"demo/workflows/$slug.html\" title=\"Try Demo\" aria-label=\"Try Demo\">")
    $null = $experienceHtml.AppendLine('                <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">')
    $null = $experienceHtml.AppendLine('                  <path d="M8 5v14l11-7-11-7z"/>')
    $null = $experienceHtml.AppendLine('                </svg>')
    $null = $experienceHtml.AppendLine('              </a>')
  }
  if ($demoUrl) {
    $null = $experienceHtml.AppendLine("              <a class=\"icon-btn github\" href=\"$demoUrl\" target=\"_blank\" rel=\"noopener\" title=\"GitHub Repo\" aria-label=\"GitHub Repo\">")
    $null = $experienceHtml.AppendLine('                <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">')
    $null = $experienceHtml.AppendLine('                  <path d="M12 .6a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2.2c-3.3.7-4-1.4-4-1.4-.6-1.4-1.4-1.8-1.4-1.8-1.2-.8.1-.8.1-.8 1.3.1 2 1.4 2 1.4 1.2 2 3.1 1.4 3.9 1.1.1-.9.5-1.4.8-1.7-2.7-.3-5.5-1.3-5.5-6.1 0-1.4.5-2.6 1.3-3.5-.1-.3-.6-1.6.1-3.3 0 0 1-.3 3.6 1.3a12.5 12.5 0 0 1 6.6 0c2.5-1.6 3.6-1.3 3.6-1.3.7 1.7.2 3 .1 3.3.8.9 1.3 2 1.3 3.5 0 4.8-2.8 5.8-5.5 6.1.5.4.9 1.1.9 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .6z"/>')
    $null = $experienceHtml.AppendLine('                </svg>')
    $null = $experienceHtml.AppendLine('              </a>')
  }
  $null = $experienceHtml.AppendLine('            </div>')
  $null = $experienceHtml.AppendLine('          </article>')
}

$template = Get-Content -Path $templatePath -Raw
$template = $template -replace ' xmlns:th="http://www.thymeleaf.org"',''
$template = $template -replace '\s+th:[a-zA-Z-]+="[^"]*"',''
$template = $template -replace '/portfolio/',''
$template = $template -replace 'href="demo"','href="demo/index.html"'
$template = $template -replace 'href="resume"','href="' + $(
  $resumeFile = Get-ChildItem -Path $resumeDir -Filter *.pdf | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($resumeFile) { 'resume/' + [uri]::EscapeDataString($resumeFile.Name) } else { 'resume' }
) + '"'

function Replace-Section($html, $startMarker, $endMarker, $replacement) {
  $start = $html.IndexOf($startMarker)
  if ($start -lt 0) { throw "Start marker not found" }
  $end = $html.IndexOf($endMarker, $start)
  if ($end -lt 0) { throw "End marker not found" }
  $before = $html.Substring(0, $start + $startMarker.Length)
  $after = $html.Substring($end)
  return $before + "\n" + $replacement + "\n" + $after
}

$personalStart = '<div class="project-grid personal-grid">'
$personalEnd = '</div>' + "`n" + "`n" + '        <div class="section-divider"></div>'
$template = Replace-Section $template $personalStart $personalEnd $personalHtml.ToString().TrimEnd()

$experienceStart = '<div class="project-grid experience-grid">'
$experienceEnd = '</div>' + "`n" + '        <div class="load-more">'
$template = Replace-Section $template $experienceStart $experienceEnd $experienceHtml.ToString().TrimEnd()

$template | Set-Content -Path $indexOut -Encoding UTF8

Copy-Item -Path $stylesSrc -Destination (Join-Path $repoPath 'styles.css') -Force
Copy-Item -Path $imagesSrc -Destination (Join-Path $repoPath 'images') -Recurse -Force

Write-Host "Static site updated."`n`nif ($Push) {`n  & git add index.html styles.css images resume`n  & git commit -m $Message`n  & git push`n  Write-Host "Pushed to GitHub."`n}

