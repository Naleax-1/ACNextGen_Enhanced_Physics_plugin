# ACNextGen Native V4.3 の導入

車両の data/script.lua は不要です。Appsから共通CSP Physics Workerを起動し、外部EXE/DLLの計算結果を追加の力として渡します。CSPの物理操作許可が必要です。

V4.3ではS14（wdts_nissan_silvia_s14）／CSPビルド3465だけで横方向タイヤ補助を実験適用します。
適用マスクは2です。他の車／CSPでは候補計算までです。足回りの反力とLSDは無効のままです。
既存ヨー減衰の適用回数と追加系統の適用回数は別に表示します。

## 配布ファイル

- ACNextGenNative-v4.3-CM.zip：Content ManagerへZIPのままドラッグ＆ドロップし、Generic Modとして導入・有効化します。
- ACNextGenNative-v4.3-assettocorsa.zip：直接配置版。ZIP内のassettocorsaフォルダーの中身をゲームのassettocorsaへコピーします。

両方の実行ファイルは同じです。走行を終了してから導入し、旧Appsを退避して新版に差し替えます。実際のCM画面での導入は未検証です。候補が出ない場合は直接配置版を使います。

```text
assettocorsa/
  apps/lua/ACNextGen/
    ACNextGen.lua
    manifest.ini
    modules/observer.lua
    modules/common_bridge.lua
    modules/observer_view.lua
    modules/performance_metrics.lua
  extension/plugins/ACNextGenNative/
    bin/ACNextGenCore.dll
    bin/ACNextGenHost.exe
    common_worker.lua
    enhancement_worker.lua
    config.json
    module_manifest.json
    runtime/.keep
```

CM向けZIPでは上のapps・extensionをassettocorsa/mods/ACNextGen Native V4.3/の下へまとめます。直接配置では二重のassettocorsa/assettocorsaフォルダーを作らないでください。

## 初回走行

1. CM/CSPのLua Apps設定でACNextGenを有効にします。
2. オフライン走行を開始します。ObserverがEXEと共通Workerを自動起動します。
3. Native Host、Common Worker、Yaw Outputの状態を確認します。モデル数は51です。
4. Stopで計算と力の適用を停止します。Resumeで状態を初期化して再開します。
5. セッション終了では管理対象EXEとWorkerを終了させます。

config.jsonのphysics_modeはbounded（制限付き追加力）またはobserve（観測のみ）です。変更後はAppsを再起動します。不正・欠損設定ではobserveへ退避します。

## 状態の読み方

- Additional channels / CALIBRATION_PENDING：該当する実験適用プロファイルがなく、追加3系統は計測・候補計算までです。
- EXPERIMENTAL_APPLICATION / Configured physical mask 2：今回のS14／CSP3465でタイヤ車体補助だけを実験適用します。
- candidates：有効な出力候補のビット集合（1=足回り、2=横滑り減衰、4=後輪LSD）です。適用回数ではありません。
- Applied suspension / tyre / LSD：新しい系統ごとの完了回数です。マスク2では走行時にtyreだけが増えます。停車・出力0では増えません。

- Permission blocked：CSPが物理操作を許可していません。DLLでも許可を回避できません。
- API fault：物理API呼び出しで失敗しました。原因を確認し、Resumeで新しい世代の試行へ移ります。
- ACK：Workerが受け取ったコマンド番号です。非ゼロの力を適用した証明にはなりません。
- API calls：API呼び出し回数です。ゼロ力の接続確認も含みます。
- Applied frames：非ゼロの力を適用した物理フレーム数です。

最初に接続する効果はadditional yaw dampingです。51モデルすべてが独立の力を加えるわけではありません。純正物理へ制限付きの減衰を重ねます。オンライン、リプレイ、一時停止、古い入力、車両ID不一致、期限切れコマンドは適用を止めます。各点20 N・モーメント40 Nmまで、寿命は20 ms・8物理フレームまでです。

車両・コースのアセットやdataフォルダーは配布に含めません。旧車両専用アダプターはソース内の研究用資料として残りますが、導入には使用しません。

自動試験は実EXE/DLL・Windows共有メモリ・実Worker Luaを使用し、ゲームの物理API部分は記録用の代替です。実ゲームのAPI成功、挙動、FPSは別の証拠が必要です。詳細はREADME.mdとBRIDGE_PROTOCOL.mdを参照してください。
