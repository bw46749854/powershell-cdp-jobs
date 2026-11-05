# 実行時の設定。ジョブの実装（どのモジュール・どのスクリプトか）は jobs.psd1 に書く。
#
# パスについて
#   キー名が *Path / *Directory の値はパスとして扱う。
#   相対パスはプロジェクトのルート（app フォルダーの1つ上）を基準にする。%USERPROFILE% などの環境変数は展開される。
#   区切り文字は \ と / のどちらでもよい。
#
# 値の意味・変えてよい範囲は docs/guides/configuration.md を参照。
@{
    Common = @{
        Browser = @{
            # リモートデバッグを有効にしたブラウザ（--remote-debugging-port=9222）のタブ一覧の URL
            DebuggerUrl = 'http://localhost:9222/json'
            ConnectTimeoutSeconds = 15
            CommandTimeoutSeconds = 30
        }

        Logging = @{
            Level = 'Info'          # Debug / Info / Warning / Error
            Console = $true
            File = $false           # $true にすると Directory に <ジョブ名>_<実行ID>.log を書く
            Directory = 'logs'
        }
    }

    Jobs = @{
        # 温室コンソールの区画一覧を CSV 出力して、日付入りの名前で保存する
        PlotRosterExport = @{
            TempDirectory = 'work/weekly/tmp/plot_roster_export'   # 実行のたびに空にする
            DownloadDirectory = 'work/weekly/downloads'
            DownloadedFilePattern = '^.+\.csv$'
            OutputFileNameTemplate = 'plot_roster_{0}.csv'        # {0} = 実行日（MMdd）
            DownloadTimeoutSeconds = 120
            DownloadStableSeconds = 2
            MenuTimeoutSeconds = 10
        }

        # 区画一覧 CSV をもとに、温室コンソールの「土壌分析の対象」チェックを整合させる
        SoilAnalysisTargetSync = @{
            InputCsvPath = '%USERPROFILE%\Downloads\plot_roster.csv'   # 単独で動かすときの入力。週次の連携では上書きされる
            OutputDirectory = 'work/weekly/downloads'
            CsvErrorFileName = 'soil_analysis_csv_errors.csv'
            FailureCsvFileName = 'soil_analysis_sync_failures.csv'
            DaysThreshold = 7
            MaxScanLoops = 500
            StallLimit = 5
        }

        # 作付け台帳の区画を1つずつ開き、作付け記録 CSV を区画コード付きの名前で保存する
        PlantingRecordExport = @{
            TempDirectory = 'work/monthly/tmp'                 # 月次の連携では実行ごとのディレクトリで上書きされる
            DownloadDirectory = 'work/monthly/downloads'       # 同上
            DownloadFilePrefix = 'planting_'                   # 台帳がダウンロードさせる CSV の名前の先頭
            FailureCsvFileName = 'failed_planting_exports.csv' # DownloadFilePrefix で始まらない名前にする
            DownloadTimeoutSeconds = 120
            DownloadStableSeconds = 2
            DetailCloseWaitSeconds = 3
            MaxScanLoops = 500
            StallLimit = 2
        }

        # 作付け記録 CSV から、先月に定植した作付けを1つの CSV にまとめる
        LastMonthPlantingDigest = @{
            TargetDirectory = 'work/monthly/downloads'   # 月次の連携では実行ごとのディレクトリで上書きされる
            OutputCsvFileName = 'last_month_plantings.csv'
            FailureCsvFileName = 'last_month_plantings_failures.csv'
            FileNamePattern = '^.+_(GH\d-[A-Z]\d{2})\.csv$'   # グループ1 = 区画コード
            RequiredHeaders = @(
                '作物名'
                '品種'
                '定植日'
            )
        }

        # 週次: PlotRosterExport → SoilAnalysisTargetSync
        WeeklySoilAnalysisSync = @{
        }

        # 月次: PlantingRecordExport → LastMonthPlantingDigest（実行ごとに RunRootDirectory/yyyyMMdd_HHmmss を作る）
        MonthlyPlantingReport = @{
            RunRootDirectory = 'work/monthly/runs'
        }
    }
}
