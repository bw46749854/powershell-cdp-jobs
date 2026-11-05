/*
 * 機能: 区画ごとの作付け記録 CSV の取得（PlantingRecordExport）— ヘルパーの組み立て
 * ヘルパー名: plantingRecordExport（app/modules/PlantingRecordExport/PageOperations.psd1 と対応）
 * 部品: screen.ledgerPlotList + feature.plantingRecordExport.grid + feature.plantingRecordExport.detail
 */
(function (kit) {
    'use strict';

    kit.define('plantingRecordExport', [
        'screen.ledgerPlotList',
        'feature.plantingRecordExport.grid',
        'feature.plantingRecordExport.detail'
    ]);
})(window.__pagekit);
