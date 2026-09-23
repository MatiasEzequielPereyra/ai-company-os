param(
    [Parameter(Mandatory = $true)][string]$JsonPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath
)

$ErrorActionPreference = "Stop"

function Get-PropertyValue {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-SchemaNode {
    param(
        [object]$Value,
        [object]$Schema,
        [string]$Path = "$"
    )

    $type = [string](Get-PropertyValue $Schema "type")

    if (-not [string]::IsNullOrWhiteSpace($type)) {
        switch ($type) {
            "object" {
                if ($null -eq $Value -or ($Value -is [string]) -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Management.Automation.PSCustomObject] -and $Value -isnot [hashtable])) {
                    throw "$Path must be an object."
                }
            }
            "array" {
                if ($null -eq $Value -or $Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
                    throw "$Path must be an array."
                }
            }
            "string" {
                if ($Value -isnot [string]) { throw "$Path must be a string." }
            }
            "integer" {
                if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64]) {
                    throw "$Path must be an integer."
                }
            }
            "boolean" {
                if ($Value -isnot [bool]) { throw "$Path must be a boolean." }
            }
        }
    }

    $enumValues = Get-PropertyValue $Schema "enum"
    if ($null -ne $enumValues) {
        $matched = $false
        foreach ($candidate in @($enumValues)) {
            if ([string]$candidate -ceq [string]$Value) { $matched = $true; break }
        }
        if (-not $matched) { throw "$Path has value '$Value' outside the allowed enum." }
    }

    if ($type -eq "string") {
        $minLength = Get-PropertyValue $Schema "minLength"
        if ($null -ne $minLength -and ([string]$Value).Length -lt [int]$minLength) {
            throw "$Path must have at least $minLength characters."
        }

        $pattern = [string](Get-PropertyValue $Schema "pattern")
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and ([string]$Value) -notmatch $pattern) {
            throw "$Path does not match required pattern '$pattern'."
        }
    }

    if ($type -eq "array") {
        $items = @($Value)
        $minItems = Get-PropertyValue $Schema "minItems"
        if ($null -ne $minItems -and $items.Count -lt [int]$minItems) {
            throw "$Path must contain at least $minItems item(s)."
        }

        $itemSchema = Get-PropertyValue $Schema "items"
        if ($null -ne $itemSchema) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                Assert-SchemaNode -Value $items[$i] -Schema $itemSchema -Path ($Path + "[" + $i + "]")
            }
        }
    }

    if ($type -eq "object") {
        $required = @(Get-PropertyValue $Schema "required")
        foreach ($requiredName in $required) {
            if ($null -eq $Value.PSObject.Properties[[string]$requiredName]) {
                throw "$Path is missing required property '$requiredName'."
            }
        }

        $properties = Get-PropertyValue $Schema "properties"
        if ($null -ne $properties) {
            foreach ($schemaProperty in $properties.PSObject.Properties) {
                $actual = $Value.PSObject.Properties[$schemaProperty.Name]
                if ($null -ne $actual) {
                    Assert-SchemaNode -Value $actual.Value -Schema $schemaProperty.Value -Path ($Path + "." + $schemaProperty.Name)
                }
            }
        }

        $additionalProperties = Get-PropertyValue $Schema "additionalProperties"
        if ($additionalProperties -eq $false -and $null -ne $properties) {
            $allowed = @($properties.PSObject.Properties.Name)
            foreach ($actualProperty in $Value.PSObject.Properties) {
                if ($allowed -notcontains $actualProperty.Name) {
                    throw "$Path contains unsupported property '$($actualProperty.Name)'."
                }
            }
        }
    }
}

if (-not (Test-Path $JsonPath -PathType Leaf)) { throw "JSON file not found: $JsonPath" }
if (-not (Test-Path $SchemaPath -PathType Leaf)) { throw "Schema file not found: $SchemaPath" }

try { $value = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "Invalid JSON in $($JsonPath): $($_.Exception.Message)" }

try { $schema = Get-Content $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "Invalid JSON schema in $($SchemaPath): $($_.Exception.Message)" }

Assert-SchemaNode -Value $value -Schema $schema

[PSCustomObject]@{
    Valid = $true
    JsonPath = $JsonPath
    SchemaPath = $SchemaPath
}
