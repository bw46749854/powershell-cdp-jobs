# PlotRosterExport の操作カタログ。
# PowerShell 側の操作名 → ページヘルパー plotRosterExport のメソッド（app/browser/features/plot-roster-export.js）。
# Kind の意味と、ヘルパー未登録時の扱いは app/modules/PageBridge/Private/OperationCatalog.ps1 を参照。
@{
    Helper = 'plotRosterExport'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'greenhousePlotList.identity'; TimeoutSeconds = 3; Label = '区画一覧画面の識別' }
        CheckInitialScreen = @{ Method = 'checkInitialScreen'; Kind = 'Contract'; Scope = 'plotRosterExport.initial'; Label = '区画一覧画面の初期状態' }
        CheckExportScreen = @{ Method = 'checkExportScreen'; Kind = 'Contract'; Scope = 'plotRosterExport.exportScreen'; Label = 'CSV 出力前の画面' }
        OpenTaskMenu = @{ Method = 'openTaskMenu'; Kind = 'Action'; Label = '「操作」メニューを開く' }
        IsExportItemReady = @{ Method = 'isExportItemReady'; Kind = 'Probe'; Label = '「CSV出力」が押せる状態' }
        ClickExportItem = @{ Method = 'clickExportItem'; Kind = 'Action'; Label = '「CSV出力」のクリック' }
        CheckExportAccepted = @{ Method = 'checkExportAccepted'; Kind = 'Contract'; Scope = 'plotRosterExport.postExport'; TimeoutSeconds = 5; Label = '「CSV出力」クリック後' }
    }
}
