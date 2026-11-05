/*
 * モック画面の共通データ。架空の温室・区画・作付け記録を「実行日を基準に」決定的に作る。
 *
 * - 同じ日に開けば、何度開いても同じデータになる（乱数の種は固定）。
 * - 日付は実行日からの相対で作るので、いつ動かしても「先月の定植」「7日以上前の分析」が含まれる。
 * - 実在の製品・組織・人物とは関係ない。
 */
(function (global) {
    'use strict';

    function createRandom(seed) {
        // mulberry32: 小さく決定的な疑似乱数（暗号用途ではない）
        let state = seed >>> 0;
        return function next() {
            state = (state + 0x6D2B79F5) >>> 0;
            let value = state;
            value = Math.imul(value ^ (value >>> 15), value | 1);
            value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
            return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
        };
    }

    function pad(value, length) {
        return String(value).padStart(length || 2, '0');
    }

    function startOfToday() {
        const now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate());
    }

    function addDays(date, days) {
        const copy = new Date(date.getTime());
        copy.setDate(copy.getDate() + days);
        return copy;
    }

    function formatDate(date) {
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
    }

    function formatDateTime(date) {
        return formatDate(date) + ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
    }

    function stamp(date) {
        return date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate());
    }

    function pick(random, items) {
        return items[Math.floor(random() * items.length)];
    }

    const OWNERS = ['青木', '石田', '上野', '岡本', '川村', '北島', '小松', '坂口', '杉山', '田辺', '中原', '野村'];
    const CROPS = [
        { crop: 'トマト', varieties: ['桃太郎', 'ルネッサンス', 'りんか409'] },
        { crop: 'キュウリ', varieties: ['夏すずみ', 'フリーダム'] },
        { crop: 'レタス', varieties: ['シスコ', 'サウザー'] },
        { crop: 'ナス', varieties: ['千両', '筑陽'] },
        { crop: 'ピーマン', varieties: ['京波', 'みおぎ'] },
        { crop: 'イチゴ', varieties: ['よつぼし', 'かおり野'] }
    ];

    /*
     * 温室コンソールの区画（3棟 × 20区画）。
     * 土壌分析の完了と最終計測日時の差が、しきい値（既定 7 日）の前後に散らばるように作る。
     */
    function greenhousePlots() {
        const random = createRandom(20260415);
        const today = startOfToday();
        const plots = [];
        const houses = [{ code: 'GH1', letter: 'A', name: '第1温室' }, { code: 'GH2', letter: 'B', name: '第2温室' }, { code: 'GH3', letter: 'C', name: '第3温室' }];

        houses.forEach((house, houseIndex) => {
            for (let number = 1; number <= 20; number++) {
                const index = houseIndex * 20 + number;
                const measured = addDays(today, -Math.floor(random() * 3));
                measured.setHours(6 + Math.floor(random() * 12), Math.floor(random() * 60), Math.floor(random() * 60));

                let completed = '-';
                let requested = '-';
                const kind = random();
                if (kind < 0.2) {
                    completed = '-';                                    // 分析したことがない区画
                }
                else {
                    const gap = Math.floor(random() * 15);              // 0〜14 日前に分析が完了
                    const completedAt = addDays(measured, -gap);
                    completedAt.setHours(9, 0, 0);
                    completed = formatDateTime(completedAt);
                    if (random() < 0.3) requested = formatDateTime(addDays(completedAt, -2));
                }

                const crop = pick(random, CROPS);
                plots.push({
                    id: 'plot-' + pad(index, 4),
                    code: house.code + '-' + house.letter + pad(number),
                    house: house.name,
                    owner: pick(random, OWNERS),
                    status: random() < 0.9 ? '稼働中' : '休止中',
                    measured: formatDateTime(measured),
                    requested,
                    completed,
                    crop: crop.crop,
                    version: '3.' + Math.floor(random() * 3) + '.' + Math.floor(random() * 10),
                    selected: random() < 0.35
                });
            }
        });

        return plots;
    }

    /*
     * 作付け台帳の区画（第2温室の24区画）と、区画ごとの作付け記録。
     * 先月の定植・今月の定植・それより前の定植が混ざるようにし、1件だけ定植日が未記入の記録を入れる。
     */
    function ledgerPlots() {
        const random = createRandom(20260301);
        const today = startOfToday();
        const firstOfThisMonth = new Date(today.getFullYear(), today.getMonth(), 1);
        const firstOfLastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        const daysInLastMonth = Math.round((firstOfThisMonth - firstOfLastMonth) / 86400000);
        const plots = [];

        for (let number = 1; number <= 24; number++) {
            const records = [];
            const count = 1 + Math.floor(random() * 3);
            for (let position = 0; position < count; position++) {
                const crop = pick(random, CROPS);
                const when = random();
                let planted;
                if (when < 0.5) planted = addDays(firstOfLastMonth, Math.floor(random() * daysInLastMonth));      // 先月
                else if (when < 0.7) planted = addDays(firstOfThisMonth, Math.floor(random() * Math.max(1, today.getDate())));  // 今月
                else planted = addDays(firstOfLastMonth, -1 - Math.floor(random() * 90));                          // 先々月より前
                records.push({ crop: crop.crop, variety: pick(random, crop.varieties), planted: formatDate(planted) });
            }
            plots.push({
                id: 'row-' + pad(number, 3),
                code: 'GH2-B' + pad(number),
                house: '第2温室',
                owner: pick(random, OWNERS),
                area: (40 + Math.floor(random() * 40)) + ' m²',
                records
            });
        }

        plots[6].records.push({ crop: 'レタス', variety: 'シスコ', planted: '' });
        return plots;
    }

    global.MockData = { createRandom, startOfToday, addDays, formatDate, formatDateTime, stamp, greenhousePlots, ledgerPlots };
})(window);
