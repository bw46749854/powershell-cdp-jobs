# SoilAnalysisTargetSync の操作カタログ。
# PowerShell 側の操作名 → ページヘルパー soilAnalysisSync のメソッド（app/browser/features/soil-analysis-sync*.js）。
# 「土壌分析を依頼」をクリックする操作は意図的に存在しない。
@{
    Helper = 'soilAnalysisSync'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'greenhousePlotList.identity'; TimeoutSeconds = 3; Label = '区画一覧画面の識別' }
        CheckScreen = @{ Method = 'checkScreen'; Kind = 'Contract'; Scope = 'soilAnalysisSync.screen'; Label = '区画一覧画面の契約' }
        CheckList = @{ Method = 'checkList'; Kind = 'Contract'; Scope = 'soilAnalysisSync.list'; Label = '区画一覧の表の契約' }
        PrepareScope = @{ Method = 'prepareScope'; Kind = 'Action'; TimeoutSeconds = 20; Label = '操作に使う範囲（ペイン）の確定' }
        ReadVisibleRows = @{ Method = 'readVisibleRows'; Kind = 'Query'; TimeoutSeconds = 10; Label = '表示中の行の読み取り' }
        SyncSelection = @{ Method = 'syncSelection'; Kind = 'Action'; TimeoutSeconds = 20; Label = '選択チェックを目的の状態にする' }
        CheckAnalysisMenu = @{ Method = 'checkAnalysisMenu'; Kind = 'Contract'; Scope = 'soilAnalysisSync.postSelection'; Label = '「土壌分析を依頼」の有効化' }
        ScrollToTop = @{ Method = 'scrollToTop'; Kind = 'Action'; TimeoutSeconds = 10; Label = '一覧の先頭へ移動' }
        ScrollDown = @{ Method = 'scrollDown'; Kind = 'Action'; TimeoutSeconds = 10; Label = '一覧を下へスクロール' }
    }
}
