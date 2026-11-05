# ジョブ定義: ジョブ名 → 実装（どのモジュールのどのコマンドを、どのページスクリプトで動かすか）。
#
#   Module      : app からの相対パス（*.psm1）
#   Command     : ジョブコマンド（Context を1つ受け取り、New-JobResult の結果を1つ返す）
#   UsesBrowser : ブラウザを使うか（$true / $false を必ず明示する）
#   Browser     : UsesBrowser = $true のときだけ指定する
#       Operations : 操作カタログ（PowerShell の操作名 → ページヘルパーのメソッド）
#       Scripts    : ページへ注入するスクリプト（この順で連結して1回で評価する）
#
# 実行時の値（ディレクトリ・タイムアウト・閾値など）は settings.psd1 に書く。ここには書かない。
# 詳しくは docs/guides/configuration.md を参照。
@{
    Jobs = @{
        PlotRosterExport = @{
            Module = 'modules/PlotRosterExport/PlotRosterExport.psm1'
            Command = 'Invoke-PlotRosterExportJob'
            UsesBrowser = $true
            Browser = @{
                Operations = 'modules/PlotRosterExport/PageOperations.psd1'
                Scripts = @(
                    'browser/kernel/pagekit.js'
                    'browser/screens/greenhouse-plot-list.js'
                    'browser/features/plot-roster-export.js'
                )
            }
        }

        SoilAnalysisTargetSync = @{
            Module = 'modules/SoilAnalysisTargetSync/SoilAnalysisTargetSync.psm1'
            Command = 'Invoke-SoilAnalysisTargetSyncJob'
            UsesBrowser = $true
            Browser = @{
                Operations = 'modules/SoilAnalysisTargetSync/PageOperations.psd1'
                Scripts = @(
                    'browser/kernel/pagekit.js'
                    'browser/screens/greenhouse-plot-list.js'
                    'browser/features/soil-analysis-sync.table.js'
                    'browser/features/soil-analysis-sync.js'
                )
            }
        }

        PlantingRecordExport = @{
            Module = 'modules/PlantingRecordExport/PlantingRecordExport.psm1'
            Command = 'Invoke-PlantingRecordExportJob'
            UsesBrowser = $true
            Browser = @{
                Operations = 'modules/PlantingRecordExport/PageOperations.psd1'
                Scripts = @(
                    'browser/kernel/pagekit.js'
                    'browser/screens/ledger-plot-list.js'
                    'browser/features/planting-record-export.grid.js'
                    'browser/features/planting-record-export.detail.js'
                    'browser/features/planting-record-export.js'
                )
            }
        }

        LastMonthPlantingDigest = @{
            Module = 'modules/LastMonthPlantingDigest/LastMonthPlantingDigest.psm1'
            Command = 'Invoke-LastMonthPlantingDigestJob'
            UsesBrowser = $false
        }

        WeeklySoilAnalysisSync = @{
            Module = 'modules/JobChains/JobChains.psm1'
            Command = 'Invoke-WeeklySoilAnalysisSyncJob'
            UsesBrowser = $false
        }

        MonthlyPlantingReport = @{
            Module = 'modules/JobChains/JobChains.psm1'
            Command = 'Invoke-MonthlyPlantingReportJob'
            UsesBrowser = $false
        }
    }
}
