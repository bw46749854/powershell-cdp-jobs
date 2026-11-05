# PlantingRecordExport の操作カタログ。
# PowerShell 側の操作名 → ページヘルパー plantingRecordExport のメソッド（app/browser/features/planting-record-export*.js）。
@{
    Helper = 'plantingRecordExport'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'ledgerPlotList.identity'; TimeoutSeconds = 3; Label = '区画一覧画面の識別' }
        CheckScreen = @{ Method = 'checkScreen'; Kind = 'Contract'; Scope = 'plantingExport.screen'; Label = '区画一覧画面の契約' }
        CheckList = @{ Method = 'checkList'; Kind = 'Contract'; Scope = 'plantingExport.list'; Label = '区画一覧の表の契約' }
        ReadTotalCount = @{ Method = 'readTotalCount'; Kind = 'Query'; Label = '一覧の件数の読み取り' }
        ReadVisibleRows = @{ Method = 'readVisibleRows'; Kind = 'Query'; Label = '表示中の行の読み取り' }
        ReadSelectedRow = @{ Method = 'readSelectedRow'; Kind = 'Query'; Label = '選択中の行が対象の区画になるまで' }
        OpenDetail = @{ Method = 'openDetail'; Kind = 'Action'; Label = '区画詳細を開く' }
        IsDetailReadyFor = @{ Method = 'isDetailReadyFor'; Kind = 'Probe'; TimeoutSeconds = 20; Label = '区画詳細に対象の区画が表示されるまで' }
        CheckOpenedDetail = @{ Method = 'checkOpenedDetail'; Kind = 'Contract'; Scope = 'plantingExport.openedDetail'; Label = '開いた区画詳細の契約' }
        OpenPlantingTab = @{ Method = 'openPlantingTab'; Kind = 'Action'; Label = '作付け記録タブを開く' }
        CheckPlantingTab = @{ Method = 'checkPlantingTab'; Kind = 'Contract'; Scope = 'plantingExport.plantingTab'; Label = '作付け記録タブの契約' }
        ReadDetailPlotCode = @{ Method = 'readDetailPlotCode'; Kind = 'Query'; Label = '区画詳細の区画コード' }
        ClickPlantingCsv = @{ Method = 'clickPlantingCsv'; Kind = 'Action'; Label = '作付け記録の CSV 出力' }
        CloseDetail = @{ Method = 'closeDetail'; Kind = 'Cleanup'; Label = '区画詳細を閉じる' }
        IsDetailClosed = @{ Method = 'isDetailClosed'; Kind = 'Probe'; Label = '区画詳細が閉じるまで' }
        ScrollToTop = @{ Method = 'scrollToTop'; Kind = 'Action'; Label = '一覧の先頭へ移動' }
        ScrollDown = @{ Method = 'scrollDown'; Kind = 'Action'; Label = '一覧を下へスクロール' }
    }
}
