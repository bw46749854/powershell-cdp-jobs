'use strict';

// PowerShell が組み立てたページ呼び出し式（PageBridge の HelperCall）を Node.js 上で実際に評価する。
// 標準入力: [{ name, expression, helpers }] の JSON。helpers は window.__pagekit.helpers に置く
//            ヘルパー定義（メソッド名 → 戻り値 / { throws: "message" }）。null ならヘルパー未登録。
// 標準出力: [{ name, ok, value, error }] の JSON。

const chunks = [];
process.stdin.on('data', chunk => chunks.push(chunk));
process.stdin.on('end', async () => {
    const cases = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const results = [];

    for (const testCase of [].concat(cases)) {
        const window = {};
        if (testCase.helpers) {
            const helper = {};
            for (const [name, behavior] of Object.entries(testCase.helpers)) {
                helper[name] = function (...args) {
                    if (behavior && behavior.throws) {
                        throw new Error(behavior.throws);
                    }
                    return { returned: behavior, args, self: this === helper };
                };
            }
            window.__pagekit = { helpers: { [testCase.helper]: helper } };
        }

        try {
            const evaluate = new Function('window', `return ${testCase.expression};`);
            const value = await evaluate(window);
            results.push({ name: testCase.name, ok: true, value });
        }
        catch (error) {
            results.push({ name: testCase.name, ok: false, error: String(error && error.message) });
        }
    }

    process.stdout.write(JSON.stringify(results));
});
