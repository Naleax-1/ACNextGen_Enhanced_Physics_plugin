# ACNextGen Native V4.3：車体への力の単位確認とタイヤ補助の部分接続

## 損傷処理の更新候補（2026-10-17）

候補版の `model_damage_policy` は `event_root_v1` です。
衝撃による基本損傷は `damage_event` が担当し、`impact_sensor` のROOT推定値は
認められた衝撃への補正に参加します。停車中のROOT値だけでは損傷を加算しません。
同じ車両の走行中にObserverでStop→Resumeした場合、車体・四輪の損傷値を保持し、
停止前の衝撃や一時出力は破棄します。熱など、他のモデル状態の保持は未対応です。
この処理は独立したEXE/DLLと合成入力で確認した段階で、実衝突の校正・検証は未完了です。
新しい車輪トルク経路の有効化や、51モジュール全体の物理反映完了を意味しません。

V4.3で車体へのN入力とワールド座標の応答を実ゲームで対照測定しました。
今回のS14／CSPビルド3465で、車輪位置に作用する追加横滑り減衰だけを実験適用します。
足回りの車輪側反力とRWD後輪間のLSDトルクは校正待ちで、物理適用を無効に保ちます。
担当モデルのstateを直接読み、熱・損傷・車輪監査で制限します。
実EXE/DLL・Windows共有メモリ・Worker Luaの経路はAPI模擬試験で確認しています。
他の車両／CSPビルドでは3系統とも候補計算と計測までで、実験適用は行いません。
既存のヨー減衰とは別に状態・適用回数を表示します。51件全体の物理反映完了ではありません。
詳しい仕様はENHANCEMENT_CHANNELS.md、全51件の計画はACTUATION_PLAN_JP.mdを参照してください。

V4.0は実ゲームでゼロ力コマンドのAPI受信を確認し、ユーザーから非ゼロのAPPLIED FRAMES増加と体感上の問題がないことを報告いただきました。その版を日時付きCM ZIPとして固定しています。

V4.1は数値同値性を維持した計算負荷削減（同一入力でV4.0より約13.2%短縮）と、実走FPS・フレーム時間の記録を追加した開発版です。新DLLの実走比較はこれから行います。PERFORMANCE_CAPTURE.mdに測定手順を記載しています。

現行版は共通CSP Physics Workerを入口にします。各車両のdata/script.luaは不要です。51モデルを外部C++ DLLで計算し、最初の適用効果は制限付きadditional yaw dampingです。最新の導入方法はINSTALL_DISTRIBUTION_JP.md、英語仕様はREADME.mdとBRIDGE_PROTOCOL.mdを参照してください。実EXE/DLL・共有メモリ・Worker Luaの経路試験は通過しました。実ゲームのAPI成功とFPSは別途確認が必要です。

以下はV3.1の履歴です。車両専用script.luaの説明は現行版の必須条件ではありません。

## V3.1：外部強化物理・全51モデル

純正AC物理を土台にして追加現象を重ねる方針。51個のC++モデルを統合し、V3.1では実行負荷を削減した。車両を動かす追加力・FFBの接続を完了した製品とはまだ区別する。

## 配置

| 場所 | 役割 |
|---|---|
| ソースのsrc/modules | 全51個のC++計算モジュール |
| assettocorsa/extension/plugins/ACNextGenNative/bin | ACNextGenCore.dllとACNextGenHost.exe |
| assettocorsa/extension/plugins/ACNextGenNative/runtime | 状態・Stop/Resume・生存通知 |
| assettocorsa/apps/lua/ACNextGen | オブザーバーと自動起動の入口 |
| content/cars/wdts_nissan_silvia_s14_acnextgen_native_test/data/script.lua | 車両物理状態を読む接続アダプター |

DLLをこのフォルダーへ置くだけでゲームがロードする仕組みではない。オブザーバーがEXEを起動し、そのEXEがDLLを明示的にロードする。計算モジュールのLuaをAppsへ戻さない。元Luaはreferenceに比較・再生成用として保存してあり、DLLはLua VM、Luaバイトコード、Luaソースを実行しない。

## 操作

1. ACを再起動し、オフライン走行を開始する。EXEとモデルは自動で開始する構成。
2. 見出し「ACNextGen Native V3.1 / external enhancement / 51 C++ models」、RUNNING_NATIVE_MODELS、Native framesの増加、selected modules 51を確認する。
3. Stopで計算を一時停止、Resumeで再開。EXEが終了していた場合もResumeが起動を要求する。再開時にモデル状態は初期化する。
4. Module statusを展開すると、51個の状態をスクロールして確認できる。画面を閉じるだけではEXEを終了しない。
5. 車両専用入力を使う場合は「WDT Silvia S14 - ACNextGen Native TEST」を選ぶ。Input source: cphys_packetを確認する。通常のWDT Silviaではstandard_shared_memoryになる。
6. セッション終了でEXEへ終了要求。AC終了はCSPのJob連動、スクリプト終了もCSPの寿命連動を使う。制御更新が止まると1.5秒でモデル停止、3秒で管理対象EXE終了。制御が届かなかった起動は5秒で終了。

初回セッションではac.onSessionStartが呼ばれないためupdateで開始を検出する。古いstatus.jsonの初回読み取りだけでは生存とみなさず、heartbeatが進むことを確認する。オンラインでは自動開始を拒否する。

現在のForce applicationはOFF。計算開始と追加物理の有効化は別の操作段階であり、Stop/Resumeは今は計算を制御する。CSP内でのV3自動起動・終了と、実車の追加力は実走行で未検証。

## 全51個の統合

元のmoduleDefsにあり、元ファイルが存在する51個を元の登録順で接続した。共有信号はC++ Runtime内で受け渡す。後段から前段へ戻る信号は前回値になる元の順序を維持する。元Appsはモジュールごとに混合レートだったが、今回のホストは統合モデル更新。元のApps全体との時系列同等性までは認定していない。

| 分野 | 含まれる計算 |
|---|---|
| 荷重・サスペンション | 荷重移動、接地入力、ダンパー、履歴、ばね、ばね上質量、重量配分、アーム、キャスター、コンプライアンス |
| タイヤ・路面 | 接触核と応答、カーカス、接触品質、状態、記憶、熱、動力学、力、コンプライアンス、荷重経路、路面解釈 |
| 駆動・姿勢 | LSD、drivetrain、ねじれ、タイヤホップ、滑り回復、ヨーモーメント予算 |
| 車体・熱 | 熱、質量バランス、ロール、車体エネルギー、フレックス、仮想慣性 |
| 操舵・ブレーキ | 操舵動力学、機構、ブレーキ系、フェード、ロック |
| 損傷・統合・監査 | 損傷状態とイベント、衝撃センサー、車両状態、physics信号Hub、wheel_audit |

元で無効だったsteering_mechanism、impact_sensorも計算対象へ追加した。steering_mechanismのapplyFFBは元の既定falseを維持する。EXEから実FFB APIは呼ばない。

impact_stateは登録名だけあり、元Luaが存在しないため追加していない。欠落名をmanifestと画面に表示する。observerはApps側、native_shadowとphysics_worker_bridgeは旧通信系なので新方式へ統合。diff_lsd_observerは元の登録外の診断用ファイルであり、モデル数へ水増ししない。ngp_core相当は共通C++実装。

全リスト・元ファイルSHA256・追加41個・除外理由はmodule_manifest.json。enhancement_catalogue.jsonには信号入出力のリテラル接頭辞を記録してある。これは静的な文字列抽出であり、動的キー・別名・キー配列を含む完全な依存図ではない。

## 入力と外部強化の考え方

通常入力はOriginal ACのacpmf_physics/graphics/staticを読み取り専用で取得する。物理packetの進行とlive状態を確認する。標準のwheelSlipをスリップ比や角へ流用しない。今回ブレーキ温度、タイヤ摩耗・汚れ、気温・路面温度、ピット状態も取得する。

実験車両では車両専用APIのスリップ角・比、荷重、純正Fx/Fy/Mz、ダンパー速度、エンジントルクを読む。456-byte payloadとcommit、checksum、epoch、sequence、時刻・有限値の検査を行う。標準MMFの車両名は32文字で切れるため、オブザーバーの完全なac.getCarID(0)と先頭32文字を照合して完全IDを使う。不一致の車両にcphysを混ぜない。

確認済みのlive mass、入力の単位と座標、cphysの実CSP受信には残る確認がある。取得できない値は元モデルのフォールバックになる。全51個のRUNNINGは、全入力が実測されていることを意味しない。

外部強化では、まず純正にない追加現象を明確な単位・座標で扱う。残差を使う場合は同じ時刻・単位・座標のnative力との差を定義する。純正と重複するタイヤ総力、総ダンパー力、総駆動トルクをそのまま追加しない。ForcelessTyresなどによる全面置換はこの方針では使わない。

## 検証と性能

元Luaのロード→initを各モジュールごとに行う順序まで合わせて比較する。後段モジュールのトップレベルexportが前段のinitへ影響するため、全部ロードしてからinitするテスト構成は使用しない。

- model_equivalence.json：51個の元LuaとC++の同じ入力・更新順での比較。
- model_equivalence_configured_car.json：実験車両のINIを読み込む既定設定での比較。
- lifecycle_validation.json：実Windows EXE/DLLと隔離したAC/CSP形式MMFによるStop/Resume、EXE終了・再起動、制御失効、車両名照合、checksum拒否。
- observer_validation.json：Lua 5.1 mockで自動開始・終了・再開・オンライン拒否・古い状態拒否・2操作ボタン。
- installed_validation.json：配置ファイルhash、Appsモデル数0、元車両143ファイル不変。

V3.1ではローカル変数を生成時に解決し、実行時の名前探索をなくした。ローカル宣言がない分岐では環境を確保せず、文字列定数を共有し、テーブル検索でのキー複製も削減する。全信号を返すngp2_step/ngp2_snapshotは検証用として維持し、ホストはngp2_step_modelsとngp2_observer_snapshotを使う。通常のstatus.jsonは51状態と表示用5信号だけを5Hzで書く。全信号を省略しても51モデル内部の計算・信号受け渡しは変わらない。

クロージャーから保持されない関数の呼び出し環境はスタックに置き、8個以下のローカル領域はヒープ確保しない。保持される環境は共有所有を維持する。両方の経路を生成器の比較試験で確認する。

ホストの共有メモリ確認は200Hz、モデルは従来通り最大20Hz。プロセス優先度をBelow Normalにして、CPU競合時はゲーム側を優先する。負荷削減の検証はreports/performance_comparison.jsonに旧版→新版→新版→旧版の同一入力比較として記録する。ゲームFPSはこの試験では測定していない。

汎用Value/Tableは残る。高頻度の物理制御へ進むにはさらに固定型のホットパスが必要。ホストは物理スレッドの外で実験計算し、過負荷でも毎回モデルを再作成しない。dt制限・モデル内の上限があるため、遅い更新を物理制御として正しいと認定しない。

Stop/Resumeによる状態リセット、元Appsとの更新レートの違い、欠損入力、モデル出力の物理的意味は次段階の確認対象。コード移植の比較が通ることと、追加物理が実車で適切に働くことを分ける。

## ビルドと戻し方

Windows x64、Zig 0.14.1、C++17。build.ps1は-O2/-g0のreleaseビルドで、fast-mathは使用せずffp-contract=off。Pythonの開発依存はrequirements-dev.txt。nlohmann/json 3.12.0を同梱する。

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
# 生成済みC++はGitに含む。変更・再生成する場合だけ実行する。
.\.venv\Scripts\python.exe tools/translate.py
.\build.ps1 -Zig C:\tools\zig\zig.exe
.\Test.ps1 -Python .\.venv\Scripts\python.exe -Zig C:\tools\zig\zig.exe
```

tools/translate.pyはreference/registry.jsonとreference/*.luaだけから生成する。バックアップやゲーム本体を参照しない。Test.ps1の通常試験はゲーム未起動で実行できる。既定INIを使う追加比較は-AcRootと-CarIDを両方指定する。生成器のスコープ、クロージャー、再帰、可変長引数、同時代入、文字列/数値キーはtest_translator.pyでLua 5.1と比較する。

配置はadapters/ACNextGen.lua・manifest.iniをapps/lua/ACNextGenへ、observer.luaをそのmodulesへ、DLL/EXEをextension/plugins/ACNextGenNative/binへ置く。plugin直下にruntimeフォルダーとmodule_manifest.jsonも必要。既存の同名Appsがある場合は先に退避し、旧モデルを同時実行しない。車両専用アダプターは実験車両のコピーにだけ導入する。一般車両での起動は標準共有メモリの観測・モデル計算に限定される。

tools/update_installation.pyとverify_installation.pyはこのPCのreports/installation.json・test_car.jsonを使う既設環境用。これらのローカル記録はGitへ含めない。新規導入へそのまま流用しない。

更新前のソース・DLL/EXEはローカルのbackupsへ保管する。元車両は変更しない。Gitではbackups、build、ゲーム車両、実行中の状態、個人環境の導入記録を除外する。開発順序はROADMAP_JP.md、提案の控えはIDEAS_JP.mdへ記録する。

## 一次資料

- 車両物理スクリプト：https://github.com/ac-custom-shaders-patch/acc-extension-config/wiki/Cars-%E2%80%93-Physics-scripts
- MMF制約：https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/common/ac_extras_connectmmf.lua
- EXE寿命連動：https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/common/os.lua
- Original AC共有メモリ形式：https://github.com/ac-custom-shaders-patch/acc-extension-apps/blob/master/apps/python/AccExtHelper/sim_info.py

旧V3の配置前計測：全step平均約73.67 ms、p99約116.56 ms。比較条件とV3.1の測定結果はreportsのJSONを正とする。実CSP走行のFPSや車両応答は別途検証する。

今回の同条件比較は旧経路76.85 ms→V3.1軽量経路46.41 ms（平均、約39.6%短縮）。条件・p99・限界・実走比較の手順はPERFORMANCE_JP.mdを参照する。
# 校正の追加情報

V4.3で車体への力の単位とワールド座標の応答を対照測定した。新しい力経路の
余分なdt乗算を除き、S14／CSPビルド3465で横方向タイヤ補助だけを実験適用する。
足回り反力・LSDは校正待ち。51現象の全面的な反映は引き続き開発中。

V4.2には、明示的な開発リクエストでのみ動く有限時間の校正Workerを追加した。
通常の自動起動では校正入力は出ない。実ゲームで車体入力と後輪対向入力の記録を
取得したが、単位の倍率は未確定で、3系統の通常適用は無効のまま。
CMの拡張物理を有効にした現在の車両を用いた。車両script.luaは使用せず、
利用者が編集したボディ剛性は保持する。詳細はCALIBRATION_JP.md。
