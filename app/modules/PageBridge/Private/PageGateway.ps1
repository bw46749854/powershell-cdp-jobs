# ページゲートウェイ: 1つのセッション（タブ）に対する「操作カタログ経由の呼び出し口」。
#
#   Inject     ページスクリプトを注入し、カタログの全メソッドが揃っているか検証する
#   Invoke     Identity / Action / Query / Cleanup を1回呼ぶ
#   WaitUntil  Probe が true を返すまで待つ
#   WaitFor    Query の結果が Accept を満たすまで待つ
#   Assert     Contract の fatal が 0 になるまで待ち、warning を記録して結果を返す
#
# 呼び出し方は Get-PageOperation で Kind ごとに制限する（例: Contract を Invoke で読み捨てない）。

$script:PageWaitDefaults = @{
    WaitUntil = 10
    WaitFor = 10
    Assert = 20
}

function New-PageGatewayState {
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][object]$Catalog,
        [Parameter(Mandatory)][string[]]$ScriptPaths,
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][object]$Log
    )

    return [pscustomobject]@{
        Session = $Session
        Catalog = $Catalog
        ScriptPaths = $ScriptPaths
        JobName = $JobName
        Log = $Log
    }
}

function Resolve-PageOperationTimeout {
    param(
        [Parameter(Mandatory)][object]$Operation,
        [int]$Requested = 0,
        [Parameter(Mandatory)][int]$Fallback
    )

    if ($Requested -gt 0) { return $Requested }
    if ($Operation.TimeoutSeconds -gt 0) { return [int]$Operation.TimeoutSeconds }
    return $Fallback
}

function Resolve-PageOperationDescription {
    param(
        [Parameter(Mandatory)][object]$Operation,
        [AllowEmptyString()][string]$Requested = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Requested)) { return $Requested }
    return $Operation.Label
}

function Invoke-PageBundleInjection {
    param([Parameter(Mandatory)][object]$State)

    $script = Read-PageScriptText -Paths $State.ScriptPaths
    $expression = New-PageBundleExpression -ScriptText $script -Helper $State.Catalog.Helper -JobName $State.JobName
    $ack = Invoke-CdpEvaluate -Session $State.Session -Expression $expression -TimeoutSeconds 30
    Assert-PageBundleAck -Ack $ack -Catalog $State.Catalog
    return $ack
}

function Invoke-PageOperation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0
    )

    $definition = Get-PageOperation -Catalog $State.Catalog -Name $Operation -Use 'Invoke'
    $timeout = Resolve-PageOperationTimeout -Operation $definition -Requested $TimeoutSeconds -Fallback ([int]$State.Session.CommandTimeoutSeconds)
    $expression = New-HelperCallExpression -Helper $State.Catalog.Helper -Operation $definition -Arguments $Arguments
    $value = Invoke-CdpEvaluate -Session $State.Session -Expression $expression -TimeoutSeconds $timeout

    if ($definition.Kind -eq 'Identity') {
        Assert-PageContractScope -Result $value -Operation $definition
    }

    return $value
}

function Wait-PageOperationTrue {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [AllowEmptyString()][string]$Description = ''
    )

    $definition = Get-PageOperation -Catalog $State.Catalog -Name $Operation -Use 'WaitUntil'
    $timeout = Resolve-PageOperationTimeout -Operation $definition -Requested $TimeoutSeconds -Fallback $script:PageWaitDefaults.WaitUntil
    $expression = New-HelperCallExpression -Helper $State.Catalog.Helper -Operation $definition -Arguments $Arguments

    [void](Wait-CdpEvaluation `
        -Session $State.Session `
        -Expression $expression `
        -Accept { param($Value) $Value -eq $true } `
        -TimeoutSeconds $timeout `
        -Description (Resolve-PageOperationDescription -Operation $definition -Requested $Description))

    return $true
}

function Wait-PageOperationResult {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(),
        [Parameter(Mandatory)][scriptblock]$Accept,
        [int]$TimeoutSeconds = 0,
        [AllowEmptyString()][string]$Description = ''
    )

    $definition = Get-PageOperation -Catalog $State.Catalog -Name $Operation -Use 'WaitFor'
    $timeout = Resolve-PageOperationTimeout -Operation $definition -Requested $TimeoutSeconds -Fallback $script:PageWaitDefaults.WaitFor
    $expression = New-HelperCallExpression -Helper $State.Catalog.Helper -Operation $definition -Arguments $Arguments

    return Wait-CdpEvaluation `
        -Session $State.Session `
        -Expression $expression `
        -Accept $Accept `
        -TimeoutSeconds $timeout `
        -Description (Resolve-PageOperationDescription -Operation $definition -Requested $Description)
}

function Assert-PageOperationContract {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [AllowEmptyString()][string]$Description = ''
    )

    $definition = Get-PageOperation -Catalog $State.Catalog -Name $Operation -Use 'Assert'
    $timeout = Resolve-PageOperationTimeout -Operation $definition -Requested $TimeoutSeconds -Fallback $script:PageWaitDefaults.Assert
    $label = Resolve-PageOperationDescription -Operation $definition -Requested $Description
    $expression = New-HelperCallExpression -Helper $State.Catalog.Helper -Operation $definition -Arguments $Arguments

    # 画面描画の途中では一時的に契約を満たさないことがあるため、fatal が 0 になるまで待つ。
    # scope や形の不一致は待っても直らない設定不備なので、Accept の中で即座に例外にする。
    $assertScope = Get-Command -Name Assert-PageContractScope -CommandType Function
    $accept = {
        param($Value)
        & $assertScope -Result $Value -Operation $definition
        return ([int]$Value.fatalCount -eq 0)
    }.GetNewClosure()

    try {
        $result = Wait-CdpEvaluation -Session $State.Session -Expression $expression -Accept $accept -TimeoutSeconds $timeout -Description $label
    }
    catch {
        if ((Get-BridgeErrorCategory -ErrorObject $_) -ne 'wait-timeout') { throw }

        # 期限内に契約を満たさなかった。最後の結果で判定し直し、契約違反として詳細付きで報告する。
        $last = Invoke-CdpEvaluate -Session $State.Session -Expression $expression -TimeoutSeconds ([int]$State.Session.CommandTimeoutSeconds)
        Assert-PageContractPassed -Result $last -Operation $definition -Description $label -Log $State.Log
        return $last
    }

    Assert-PageContractPassed -Result $result -Operation $definition -Description $label -Log $State.Log
    return $result
}

function New-PageGateway {
    <#
    .SYNOPSIS
    ゲートウェイの状態をポートオブジェクト（scriptblock メンバー）に包む。
    #>
    param([Parameter(Mandatory)][object]$State)

    $inject = Get-Command -Name Invoke-PageBundleInjection -CommandType Function
    $invoke = Get-Command -Name Invoke-PageOperation -CommandType Function
    $waitUntil = Get-Command -Name Wait-PageOperationTrue -CommandType Function
    $waitFor = Get-Command -Name Wait-PageOperationResult -CommandType Function
    $assert = Get-Command -Name Assert-PageOperationContract -CommandType Function

    return [pscustomobject]@{
        Inject = {
            [CmdletBinding()] param()
            & $inject -State $State
        }.GetNewClosure()
        Invoke = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0)
            & $invoke -State $State -Operation $Operation -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
        }.GetNewClosure()
        WaitUntil = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $waitUntil -State $State -Operation $Operation -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -Description $Description
        }.GetNewClosure()
        WaitFor = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [Parameter(Mandatory)][scriptblock]$Accept, [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $waitFor -State $State -Operation $Operation -Arguments $Arguments -Accept $Accept -TimeoutSeconds $TimeoutSeconds -Description $Description
        }.GetNewClosure()
        Assert = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $assert -State $State -Operation $Operation -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -Description $Description
        }.GetNewClosure()
    }
}
