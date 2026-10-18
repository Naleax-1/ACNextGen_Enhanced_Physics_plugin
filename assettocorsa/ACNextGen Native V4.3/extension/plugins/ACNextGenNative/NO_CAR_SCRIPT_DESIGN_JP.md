# 車両データ無編集で動かすACNextGen

2026-10-13。主構成の条件を「車両のdata/script.luaを追加せず、車両データを編集しない」とする。V3.1の車両専用アダプターは任意の研究用経路とし、配布版の本体が依存する構成へは進めない。

V4.0実装状況：共通Workerの起動・入力取得・世代付きコマンド受信・追加ヨー減衰の適用経路を実装済みです。実EXE/DLLと実Worker Luaの自動経路試験は通過しました。API部分は代替を使っているため、実CSPでの受信と応答の確認は未完了です。車両専用アダプターはV4配布ZIPに含めません。

## 判断

車両データ無編集で追加力を加える経路はある。導入済みCSP SDKのPhysics Workerは、車両番号を指定したphysics.addForceとphysics.addWheelTorqueを公開している。共通のAppsから起動でき、車両ごとにscript.luaを置く必要はない。

ただし「任意の車両・任意のコース・任意のセッションで、何の設定もせず必ず使える」とは現時点で保証できない。physics.allowed()の許可が必要で、公式SDKは拡張物理とトラック側の許可設定を条件にしている。車両の編集を避けることと、コースやCSPの設定も一切不要にすることは別の要件である。

## 推奨する構成

```text
共通Observer（開始・停止・再開・権限表示）
  ├─ EXE／DLL：51モデル、低速の状態更新、追加量の集約
  └─ CSP Physics Worker：物理時刻の入力と軽い適用処理
                 ↕ 期限付き・世代付きの共有メモリ
             EXE／DLL
```

- Appsは共通の起動入口とObserver。モデルのC++計算はDLLに維持する。
- Workerの薄いLua接続は共通配置する。車両のdataには配置しない。
- 本体は特定S14のIDへ固定せず、そのセッションの操作車両へ接続する。車両変更時はモデルと通信世代をリセットする。
- 車両専用cphys_packetの有無を本体の動作条件から外す。
- physics.allowed()がfalseなら原因と必要な設定を表示する。計算中という表示を力の適用中と混同しない。

これは次の接続設計であり、現在のV3.1へWorkerによる追加力適用を実装したという報告ではない。V3.1は51モデル計算が主機能で、追加力・FFBは未接続。

## 難所

### 許可条件

導入済みSDKのphysics.allowed()は、物理へ影響できない場合はraycast以外が利用できないと記述している。公式SDKにはsurfaces.iniの[_SCRIPTING_PHYSICS]と拡張トラック物理の設定例がある。実行するApps／Workerの許可は実際のCSP環境で確認する。DLLから接続しても許可条件が自動的に消えるとは考えない。

### 入力の更新時刻と単位

Workerは約333Hzだが、ac.getCar()、ac.getCarPhysics()等の通常状態は描画フレームの更新周期である。Worker内で読むだけでは物理周期の最新値にはならない。

physics.getBodyTransform、physics.getPointVelocity、physics.getWheelAngularSpeedを物理周期の入力に使う。通常状態にもスリップ、タイヤ荷重、fx/fy/mz等のフィールドがあるため、全て取得不能と決めつけない。ただしその値の利用可否、更新時刻、座標、単位は確認が必要。特に通常StateWheelのslipAngle／camberはSDKにdegreesと記述されており、モデルやcphys側の値へそのまま流用しない。

取得できない物理周期の入力を必要とする効果は、推定の根拠を定義するか、その効果を停止する。同時刻の純正力が確認できない状態で、モデル総力から純正力を引いた残差を作らない。

### 計算速度

現在の51モデルは1更新平均約46msの模擬測定結果。333Hzの周期は約3msで、全51個をWorker内で毎回計算する構成にはできない。

51モデルの状態更新と、物理周期に必要な小さな計算を分ける。後者は必要な現象に絞った固定型C++の高速経路として実装する。Workerは最新の入力と追加量を検査して適用する。約20Hzの出力を物理周期で繰り返すだけでは、タイヤ等の高速な現象が再現できるとは認定しない。

### 二重加算と適用方向

純正タイヤ総力、総サスペンション力、総駆動トルクへモデル総量を再度加えない。追加現象の所有者、単位、座標、作用点、反力を定義する。Stop、通信失効、モデル異常で追加量を解除する。

保存されているProbeログには80N・最大8物理フレームでの限定試験があるが、軸漏れ比約0.4255も記録されている。これを長時間の安定性や全軸の校正済みという証明には使わない。SDKのdtスケーリング記述と保存ログの挙動にも差があるため、適用器の単位・積分方法を実環境で再確認する。

## 代替案

| 案 | 車両編集 | 条件・評価 |
|---|---|---|
| 共通Physics Worker＋DLL | 不要 | 推奨。CSPの許可と入力範囲の制約を確認する |
| 許可が得られるコース環境を用意して共通Workerを使う | 不要 | 現実的な検証経路。コース側の設定作業は必要になり得る |
| 標準共有メモリ＋DLLの計算・観測 | 不要 | 現在動作するが、これだけではゲームへ追加力を適用できない |
| 純正物理へ直接接続する独自ネイティブフック | 不要にできる可能性 | 今回確認したSDKでは公開されたC++直接操作入口を確認できていない。解析・更新追従・互換性の負担が大きく、主案へ採用しない |

## 次の実装順

1. 共通Observerでphysics.allowed()、Worker API、セッションを事前確認する。
2. 車両無編集の共通Worker入力を、現在のホストへ接続する。既存の標準共有メモリを補完し、更新時刻と単位を表示する。
3. 操作車両の切り替え、Stop／Resume、セッション終了、失効を確認する。
4. 1現象の高速計算と追加量の契約を実装し、1軸・有限時間から実測する。
5. 車両ごとのファイル追加なしで車両を切り替え、再現試験を広げる。

## 確認した資料

- 導入済みextension/internal/lua-sdk/ac_apps/lib.lua：startPhysicsWorker、allowed、トラック許可の説明。
- 導入済みextension/internal/lua-sdk/ac_background_pw/lib.lua：getBodyTransform、getPointVelocity、getWheelAngularSpeed、addForce、addWheelTorque、通常状態の更新周期と単位。
- ローカルACPhysicsWorkerProbe/physics_worker_probe_v1_5_1_report.txt：過去の限定試験結果。今回、新たな実走・力の適用試験はしていない。
- https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/ac_background_pw.lua
- https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/common/ac_physics_unrestricted.lua
