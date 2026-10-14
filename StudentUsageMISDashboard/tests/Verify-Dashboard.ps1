param([string]$BaseUrl = 'http://localhost:5277')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Get-Content (Join-Path $root 'appsettings.json') -Raw | ConvertFrom-Json
$connection = New-Object System.Data.SqlClient.SqlConnection $config.ConnectionStrings.DefaultConnection
$checks = 0
function Assert($condition, [string]$message) {
    if (!$condition) { throw "FAIL: $message" }
    $script:checks++
}
function Query([string]$sql, $case) {
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    if ($case) {
        [void]$command.Parameters.AddWithValue('@From', [datetime]$case.From)
        [void]$command.Parameters.AddWithValue('@To', [datetime]$case.To)
        [void]$command.Parameters.AddWithValue('@Type', $case.Type)
    }
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $table = New-Object System.Data.DataTable
    [void]$adapter.Fill($table)
    $command.Dispose()
    $adapter.Dispose()
    return ,$table
}
function Near($actual, $expected, $message) {
    Assert ([math]::Abs([double]$actual - [double]$expected) -lt 0.000002) $message
}
function BadRequest([string]$query) {
    try { Invoke-WebRequest "$BaseUrl/Home/Report?$query" -UseBasicParsing | Out-Null; throw 'Expected HTTP 400' }
    catch { Assert ($_.Exception.Response.StatusCode.value__ -eq 400) "Invalid report rejected: $query" }
}
try {
    $connection.Open()
    Assert ($connection.Database -eq 'StudentUsageMISDB') 'Expected database'
    $metadata = Query 'SELECT MIN(UsageDate) FirstDate, MAX(UsageDate) LastDate FROM dbo.StudentUsage' $null
    $first = ([datetime]$metadata.Rows[0].FirstDate).ToString('yyyy-MM-dd')
    $last = ([datetime]$metadata.Rows[0].LastDate).ToString('yyyy-MM-dd')
    $cases = @(
        @{ Name='Default'; From=$first; To=$last; Type='All'; Unit='Minutes'; Divisor=60; Default=$true },
        @{ Name='Video week hours'; From='2026-09-01'; To='2026-09-07'; Type='Video'; Unit='Hours'; Divisor=3600 },
        @{ Name='PDF single day seconds'; From='2026-09-15'; To='2026-09-15'; Type='PDF'; Unit='Seconds'; Divisor=1 },
        @{ Name='Empty range'; From='2026-10-01'; To='2026-10-14'; Type='All'; Unit='Minutes'; Divisor=60 }
    )
    $where = "u.UsageDate BETWEEN @From AND @To AND (@Type = 'All' OR u.UsageType = @Type)"
    foreach ($case in $cases) {
        $query = "From=$($case.From)&To=$($case.To)&UsageType=$($case.Type)&Unit=$($case.Unit)"
        $url = if ($case.Default) { "$BaseUrl/" } else { "$BaseUrl/?$query" }
        $response = Invoke-WebRequest $url -UseBasicParsing
        Assert ($response.StatusCode -eq 200) "$($case.Name): HTTP 200"
        $match = [regex]::Match($response.Content, '<script type="application/json" id="dashboard-data">(.*?)</script>', 'Singleline')
        Assert $match.Success "$($case.Name): chart payload present"
        $data = $match.Groups[1].Value | ConvertFrom-Json
        Assert ($data.unit -eq $case.Unit) "$($case.Name): duration unit"
        $totals = Query "SELECT COUNT(*) Records, COALESCE(SUM(u.UsageSeconds),0) Seconds, COUNT(DISTINCT CASE WHEN u.UsageSeconds>0 THEN u.StudentId END) Students FROM dbo.StudentUsage u WHERE $where" $case
        $registrations = Query 'SELECT (SELECT COUNT(*) FROM dbo.Schools) Schools, COUNT(*) Students, SUM(CASE WHEN IsActive=1 THEN 1 ELSE 0 END) Active FROM dbo.Students' $null
        foreach ($entry in @(@('schools',$registrations.Rows[0].Schools), @('students',$registrations.Rows[0].Students), @('active',$registrations.Rows[0].Active), @('using',$totals.Rows[0].Students), @('duration',([decimal]$totals.Rows[0].Seconds / $case.Divisor)))) {
            $kpi = [regex]::Match($response.Content, ('data-kpi="' + $entry[0] + '">([^<]+)'))
            Assert $kpi.Success "$($case.Name): $($entry[0]) card present"
            $value = [decimal]::Parse($kpi.Groups[1].Value, [cultureinfo]'en-IN')
            Assert ([math]::Abs($value - [decimal]$entry[1]) -le 0.0051) "$($case.Name): $($entry[0]) agrees with SQL"
        }
        $students = Query "SELECT s.StudentId, COALESCE(SUM(u.UsageSeconds),0) Seconds FROM dbo.Students s LEFT JOIN dbo.StudentUsage u ON u.StudentId=s.StudentId AND $where GROUP BY s.StudentId" $case
        $buckets = @(0,0,0,0,0,0)
        foreach ($student in $students.Rows) {
            $seconds = $student.Seconds
            $index = if ($seconds -le 0) {0} elseif ($seconds -le 300) {1} elseif ($seconds -le 900) {2} elseif ($seconds -le 1800) {3} elseif ($seconds -le 2700) {4} else {5}
            $buckets[$index]++
        }
        for ($i=0; $i -lt 6; $i++) { Assert ($data.buckets[$i].value -eq $buckets[$i]) "$($case.Name): bucket $i agrees with SQL" }
        $grouped = @{}
        $grouped.district = Query "SELECT d.DistrictName Name, COUNT(DISTINCT CASE WHEN u.UsageSeconds>0 THEN s.StudentId END) Students, COALESCE(SUM(u.UsageSeconds),0) Seconds, COUNT(DISTINCT s.StudentId) Registered FROM dbo.Districts d LEFT JOIN dbo.Blocks b ON b.DistrictId=d.DistrictId LEFT JOIN dbo.Clusters c ON c.BlockId=b.BlockId LEFT JOIN dbo.Schools sc ON sc.ClusterId=c.ClusterId LEFT JOIN dbo.Students s ON s.SchoolId=sc.SchoolId LEFT JOIN dbo.StudentUsage u ON u.StudentId=s.StudentId AND $where GROUP BY d.DistrictId,d.DistrictName ORDER BY d.DistrictName" $case
        $grouped.school = Query "SELECT CONCAT(d.DistrictName,N' / ',sc.SchoolCode,N' / ',sc.SchoolName) Name, COUNT(DISTINCT CASE WHEN u.UsageSeconds>0 THEN s.StudentId END) Students, COALESCE(SUM(u.UsageSeconds),0) Seconds, COUNT(DISTINCT s.StudentId) Registered FROM dbo.Schools sc JOIN dbo.Clusters c ON c.ClusterId=sc.ClusterId JOIN dbo.Blocks b ON b.BlockId=c.BlockId JOIN dbo.Districts d ON d.DistrictId=b.DistrictId LEFT JOIN dbo.Students s ON s.SchoolId=sc.SchoolId LEFT JOIN dbo.StudentUsage u ON u.StudentId=s.StudentId AND $where GROUP BY sc.SchoolId,sc.SchoolCode,sc.SchoolName,d.DistrictName ORDER BY d.DistrictName,sc.SchoolName" $case
        foreach ($kind in @('daily','monthly','yearly')) {
            $expression = switch ($kind) { 'daily' {'CONVERT(char(10),u.UsageDate,23)'} 'monthly' {'CONVERT(char(7),u.UsageDate,23)'} 'yearly' {'CONVERT(char(4),YEAR(u.UsageDate))'} }
            $grouped[$kind] = Query "SELECT $expression Name, COUNT(DISTINCT CASE WHEN u.UsageSeconds>0 THEN u.StudentId END) Students, COALESCE(SUM(u.UsageSeconds),0) Seconds FROM dbo.StudentUsage u WHERE $where GROUP BY $expression ORDER BY 1" $case
        }
        Assert ($data.districts.Count -eq $grouped.district.Rows.Count) "$($case.Name): district chart row count"
        for ($i=0; $i -lt $grouped.district.Rows.Count; $i++) {
            Assert ($data.districts[$i].name -eq $grouped.district.Rows[$i].Name) "$($case.Name): district label"
            Near $data.districts[$i].value ($grouped.district.Rows[$i].Seconds / $case.Divisor) "$($case.Name): district chart usage"
        }
        Assert ($data.daily.Count -eq $grouped.daily.Rows.Count) "$($case.Name): daily chart row count"
        for ($i=0; $i -lt $grouped.daily.Rows.Count; $i++) {
            Assert ($data.daily[$i].date -eq $grouped.daily.Rows[$i].Name) "$($case.Name): daily chart date"
            Assert ($data.daily[$i].students -eq $grouped.daily.Rows[$i].Students) "$($case.Name): daily chart students"
            Near $data.daily[$i].usage ($grouped.daily.Rows[$i].Seconds / $case.Divisor) "$($case.Name): daily chart usage"
        }
        foreach ($kind in @('district','daily','school','monthly','yearly')) {
            $csvResponse = Invoke-WebRequest "$BaseUrl/Home/Report?kind=$kind&$query" -UseBasicParsing
            $text = [text.encoding]::UTF8.GetString($csvResponse.RawContentStream.ToArray()).TrimStart([char]0xfeff)
            Assert ($csvResponse.Headers['Content-Type'] -match 'text/csv') "$($case.Name): $kind CSV content type"
            Assert ($text -match [regex]::Escape("$($case.From),$($case.To),`"$($case.Type)`",$($case.Unit)")) "$($case.Name): $kind CSV filters"
            $rows = @(($text -split '\r?\n' | Select-Object -Skip 3 | Where-Object { $_ -ne '' }) | ConvertFrom-Csv)
            Assert ($rows.Count -eq $grouped[$kind].Rows.Count) "$($case.Name): $kind CSV row count"
            for ($i=0; $i -lt $rows.Count; $i++) {
                $properties = @($rows[$i].PSObject.Properties)
                $expected = $grouped[$kind].Rows[$i]
                Assert ($properties[0].Value -eq $expected.Name) "$($case.Name): $kind CSV name"
                Assert ([int]$rows[$i].'Students with usage' -eq $expected.Students) "$($case.Name): $kind CSV students"
                $duration = [decimal]::Parse($rows[$i].("Usage ($($case.Unit.ToLowerInvariant()))"), [cultureinfo]::InvariantCulture)
                Near $duration ($expected.Seconds / $case.Divisor) "$($case.Name): $kind CSV duration"
                if ($kind -in @('district','school')) { Assert ([int]$rows[$i].'Registered students' -eq $expected.Registered) "$($case.Name): $kind CSV registered" }
            }
        }
        Write-Output ("PASS: {0} | {1} records | {2} students with usage | {3:N2} {4}" -f $case.Name,$totals.Rows[0].Records,$totals.Rows[0].Students,($totals.Rows[0].Seconds/$case.Divisor),$case.Unit)
    }
    foreach ($query in @('kind=unknown', 'kind=school&From=2026-09-30&To=2026-09-01', 'kind=daily&UsageType=Invalid', 'kind=school&Unit=Invalid', 'kind=school&From=bad-date')) { BadRequest $query }
    $invalid = Invoke-WebRequest "$BaseUrl/?From=2026-09-30&To=2026-09-01" -UseBasicParsing
    Assert ($invalid.Content -match 'From date must be on or before To date') 'Invalid dates display an error'
    $logo = Invoke-WebRequest "$BaseUrl/images/Logo-Gshala.svg" -UseBasicParsing
    Assert ($logo.StatusCode -eq 200) 'Logo available'
    Write-Output "PASS: $checks assertions against StudentUsageMISDB and HTTP endpoints."
} finally { $connection.Dispose() }
