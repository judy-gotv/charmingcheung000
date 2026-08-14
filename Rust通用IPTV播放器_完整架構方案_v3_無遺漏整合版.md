# Rust 通用 IPTV 播放器跨平台完整架構方案 —— v3 無遺漏整合版

版本：v3　制定日期：2026-08-14
目標平台：Android 手機／Android TV（第一階段）→ iOS／iPadOS／tvOS／macOS／Windows／Linux（後續階段）
產品定位：真正通用型 IPTV 播放客戶端（類似 TiviMate、IPTV Smarters Pro 定位），使用者自帶第三方供應商訂閱，會員系統與私有伺服器對接為未來規劃。

> 本版整合 v1（初版邊界細化）、v2（傳輸協議/字幕/DRM 全景盤點）與後續審查發現的所有缺口（傳輸韌性、供應商協議完整規格、播放體驗細節、工程基建），是唯一權威版本。後續修訂請直接改此文件，不再產生 v4 之前先完整核對第 14 章「版本差異與缺口收斂記錄」。

---

## 1. 設計原則

1. **核心與殼層物理分離**：業務邏輯 100% 純 Rust，零平台依賴，透過 UniFFI 對外曝露介面。
2. **通用相容是第一階段的硬指標**：第 2 章列出的每一種傳輸協議、封裝格式、編碼、DRM、字幕系統，都必須在架構設計時有對應模組佔位；實作時程由第 12 章排序，但架構不能因為格式排在後面而沒有介面位置。
3. **硬解優先，軟解兜底**：所有平台影音解碼對接系統硬體解碼 API；AV1 等硬解覆蓋率不足的格式準備軟解（dav1d）兜底路徑。
4. **UI 一律原生**：不採用網頁容器或需額外執行環境的跨平台繪製框架作為主要 UI。
5. **介面定義先行**：核心對外的所有能力先定義完整跨語言呼叫介面，介面設計必須同時支援「無保護」與「有保護」兩種呼叫模式，避免後續修改呼叫簽名。
6. **業務層可延後，擴充口現在留好**：會員系統、私有伺服器對接是「新增實作」而不是「修改核心」。
7. **協議/格式的「解析」與「傳輸」分離**：RTSP 是信令協議，媒體走 RTP；HLS/DASH 是清單格式，分片走 HTTP。兩層職責不同，必須分開建模。
8. **（新增）韌性優先**：任何涉及網路 I/O 的模組，從架構設計第一天就要有明確的錯誤分類、重試/退避、降級策略介面，不可等上線後才補。
9. **（新增）供應商協議必須展開到端點層級**：不能只寫協議名稱，必須列出實際需要呼叫的端點/操作，否則第一階段實作會漏功能。

---

## 2. 通用相容範圍全景圖

### 2.1 傳輸協議 / 串流方式

| 協議 | 說明 | IPTV 場景常見度 | Rust 生態對應 |
|---|---|---|---|
| HLS | m3u8 清單 + TS/fMP4 分片，HTTP 拉取 | 極高 | 自研解析 |
| DASH | MPD 清單 + fMP4/CMAF 分片，HTTP 拉取 | 高（歐美/CENC 供應商） | `dash-mpd` crate |
| MSS（Smooth Streaming） | 微軟系 ISM 清單 | 低但存在 | 自研 ISM 解析（架構留位） |
| RTSP + RTP | 信令協商，媒體走 RTP/RTCP | 中 | `retina` crate |
| RTMP | 部分推流源/CDN 回源 | 低但長尾存在 | FFI 包 librtmp（過渡方案） |
| UDP 組播 / RTP over UDP（MPEG-TS） | 傳統電信 IPTV 機房到機上盒 | **高（固網主流）** | `mpeg2ts-reader` + IGMP 自行處理 |
| SRT | 專業直播貢獻鏈路 | 中 | `srt-tokio` |
| HTTP 漸進式下載（Progressive MP4） | 兜底格式 | 低但需支援 | 標準 HTTP range request |

### 2.2 封裝容器 / Demux

| 容器 | 用途 | Rust 對應 |
|---|---|---|
| MPEG-TS | HLS 傳統分片、UDP 組播、RTMP | `mpeg2ts-reader` |
| fMP4 / CMAF | HLS（fMP4 模式）、DASH 主流分片 | 自研 box 解析 |
| ADTS（裸 AAC） | 部分音訊分軌 | 自研 |

### 2.3 影音編碼與色彩管線（含 HDR，本次補齊）

| 類型 | 內容 | 備註 |
|---|---|---|
| 視訊編碼 | H.264/AVC、H.265/HEVC、AV1 | AV1 中低階裝置硬解覆蓋不足，dav1d 軟解兜底 |
| 音訊編碼 | AAC-LC/HE-AAC、AC-3、E-AC-3、MP3、Opus | AC-3/E-AC-3 歐美供應商必備，非可選 |
| **色彩空間/HDR（新增）** | SDR (BT.709)、HDR10 (BT.2020 + SMPTE ST 2084 PQ)、HLG | 4K 頻道常帶 HDR 中繼資料；`decoder_trait` 介面必須從第一天就傳遞色彩空間描述，否則後續插入色彩管理會破壞已鎖定的呼叫簽名 |
| **編碼能力探測（新增）** | Profile/Level 協商 | `transport`/`manifest` 層需具備裝置解碼能力查詢，選擇對應的碼率/解析度版本，避免下載裝置無法解碼的變體 |

### 2.4 字幕與隱藏式字幕

| 格式 | 場景 | 處理位置 |
|---|---|---|
| WebVTT | HLS 字幕軌標準格式 | core 純文字解析 |
| TTML / EBU-TT-D | DASH 字幕軌標準格式 | core 純文字解析（XML） |
| CEA-608 / CEA-708 | 內嵌於視訊流 SEI/使用者資料（美規常見） | demux 與 subtitle 唯一耦合例外，需程式碼註解標注 |
| SRT 字幕檔 | 外掛字幕 | core 純文字解析 |
| **字幕樣式使用者偏好（新增）** | 字型大小/顏色/背景不透明度可調 | 為符合美規無障礙顯示慣例（FCC CC 規範精神），偏好需持久化並套用到所有字幕格式的渲染層 |

### 2.5 DRM / 內容保護

| 方案 | 適用格式 | 金鑰交換 | 處理層級 |
|---|---|---|---|
| Widevine（L1/L3） | DASH/HLS+CENC | Provisioning + License 兩步驟 | 系統安全區域（TEE） |
| FairPlay Streaming | HLS（蘋果） | SPC/CKC 雙向包裹 | 系統安全區域 |
| PlayReady | DASH/HLS+CENC（Windows/部分 Android） | License Acquisition | 受保護媒體路徑 |
| ClearKey（DASH/CENC） | DASH | POST JSON `{kids}` → `{keys}`，走 `laurl` | 系統 CDM |
| HLS AES-128 | HLS | GET 明文金鑰，`EXT-X-KEY` 的 `URI` | core 層直接解密 |
| SAMPLE-AES | HLS（亞洲供應商常見） | 類似 AES-128 但取樣加密 | core 層解密後交解碼器 |
| 無保護 | 全部 | 無 | 直接解碼 |

**Widevine 裝置佈建（新增，原方案缺失）**：非 Google 認證的自製 Android 機上盒常遇到 L1 降級為 L3 或憑證吊銷問題。`content_protection` 模組需要在啟動時做裝置安全等級探測（呼叫 `MediaDrm.getPropertyString("securityLevel")`），並在 UI 層明確告知使用者當前裝置的保護等級與可能受限的頻道，而非播放失敗後才無訊息提示。

---

## 3. 專案分層架構

```
iptv-client/
├── core/
│   ├── source_provider/          # 頻道/VOD 來源：協議完整展開見第 4 章
│   │   ├── m3u.rs
│   │   ├── xtream_codes.rs        # 含直播/VOD/劇集/回看端點，見 4.1
│   │   └── stalker_portal.rs      # 含 token 生命週期管理，見 4.1
│   │
│   ├── manifest/                  # 串流清單格式解析
│   │   ├── hls.rs
│   │   ├── dash.rs
│   │   ├── smooth_streaming.rs
│   │   └── mod.rs                 # StreamManifest 統一抽象
│   │
│   ├── transport/                 # 實際媒體連線建立與資料拉取
│   │   ├── http_segment.rs
│   │   ├── rtsp_session.rs
│   │   ├── udp_multicast.rs
│   │   ├── srt_session.rs
│   │   ├── rtmp_session.rs
│   │   ├── failover.rs            # 【新增】多源備援與線路切換，見 5.1
│   │   ├── resilience.rs          # 【新增】重連/退避/逾時分類，見 5.2
│   │   ├── jitter_buffer.rs       # 【新增】UDP/RTP 封包重排序與抗抖動，見 5.3
│   │   ├── capability_probe.rs    # 【新增】網路類型感知與能力探測，見 5.4
│   │   ├── tls_trust.rs           # 【新增】自簽憑證信任鏈處理，見 5.5
│   │   └── mod.rs                 # MediaTransport trait 統一抽象
│   │
│   ├── demux/
│   │   ├── mpeg_ts.rs
│   │   ├── fmp4.rs
│   │   └── mod.rs
│   │
│   ├── subtitle/
│   │   ├── webvtt.rs
│   │   ├── ttml.rs
│   │   ├── cea608_708.rs
│   │   ├── style_pref.rs          # 【新增】字幕樣式偏好持久化
│   │   └── mod.rs
│   │
│   ├── epg/
│   │   ├── xmltv.rs
│   │   ├── provider_endpoint.rs
│   │   └── timeshift_catalog.rs   # 【新增】回看/時移節目索引，見 6.1
│   │
│   ├── vod/                       # 【新增章節】點播/系列劇集/時移，見 6 章
│   │   ├── catalog.rs
│   │   ├── series.rs
│   │   ├── resume_position.rs
│   │   └── trick_play.rs
│   │
│   ├── abr/
│   ├── cache/
│   ├── playback_fsm/
│   ├── decoder_trait/              # HardwareDecoder trait，含色彩空間參數
│   ├── content_protection/         # DRM 方案判斷 + 裝置安全等級探測
│   ├── license_exchange/
│   ├── intent/
│   ├── session/
│   ├── cast/                       # 【新增】投放協議抽象，見 7 章
│   ├── parental_control/           # 【新增】本機 PIN 鎖，見 8 章
│   ├── diagnostics/                # 【新增】日誌/crash 回報，見 9.2
│   └── update_check/               # 【新增】更新檢查掛鉤，見 9.3
│
├── platform-android/               # MediaCodec + Widevine + license_exchange 平台實作
├── platform-ios/
├── platform-windows/
├── platform-linux/
├── uniffi-bindings/
└── ci/                              # 見 9.1
```

**核心鐵律**：`core` 的 `Cargo.toml` 禁止出現平台專屬 crate；允許純協議/格式實作 crate（`dash-mpd`、`mpeg2ts-reader`、`retina`、`srt-tokio`），因其平台無關。

---

## 4. 供應商來源協議完整規格（本次補齊，原方案僅列協議名稱）

### 4.1 Xtream Codes API 端點展開

| 端點類別 | 操作 | 資料模型 |
|---|---|---|
| 直播頻道 | `get_live_categories` / `get_live_streams` | `Channel { id, name, category, logo, stream_url, epg_channel_id }` |
| VOD 片庫 | `get_vod_categories` / `get_vod_streams` / `get_vod_info` | `VodItem { id, title, poster, plot, container_ext }` |
| 劇集 | `get_series_categories` / `get_series` / `get_series_info` | `Series { seasons: Vec<Season>, episodes: Vec<Episode> }` |
| **回看/時移（原方案完全缺失）** | `get_simple_data_table`（取得指定頻道某時段回看片段列表） | `TimeshiftSegment { start, duration, url }`，需與 EPG 節目時間對齊 |
| 認證 | `player_api.php` 帳密驗證 | Session 需處理逾期重新驗證 |

### 4.2 Stalker Portal（Ministra）Token 生命週期

- Handshake 取得 `token`，`token` 有效期有限，過期後所有請求回 403，需要在 `source_provider` 層封裝**自動偵測 403 並重新 handshake**的邏輯，而非讓上層業務邏輯感知 token 存在。
- itv/vod 頻道列表分頁端點需處理分頁游標，原方案完全沒提分頁機制，供應商頻道數量可能上千，一次性拉取不現實。

### 4.3 私有伺服器對接（架構銜接，現在需預留）

- 等同新增一個 `PrivateBackendProvider` 實作，符合統一 `SourceProvider` trait。
- **自簽憑證信任處理（新增）**：使用者自架伺服器（例如結合 Xray/自建反代）常用自簽 CA，`transport::tls_trust` 需提供「使用者手動信任特定憑證指紋」的介面，且此信任決定要在 UI 層有明確警示，不能默默略過憑證驗證。

---

## 5. 傳輸韌性子系統（全新章節，原方案最大缺口）

### 5.1 多源備援（Failover）

```rust
pub struct ChannelSource {
    pub primary_url: String,
    pub backup_urls: Vec<String>,   // 供應商常態提供多條線路
}

pub trait FailoverStrategy: Send {
    fn next_candidate(&mut self, failed: &str) -> Option<String>;
    fn record_success(&mut self, url: &str);
}
```

`Channel` 結構從單一 `stream_url` 改為 `ChannelSource`，`transport` 層在連續失敗 N 次後自動切換到下一條備援線路，並向 `playback_fsm` 回報切換事件供 UI 顯示「正在切換線路」。

### 5.2 重連與退避策略

| 錯誤類型 | 分類 | 處理策略 |
|---|---|---|
| HTTP 逾時/5xx | 暫時性 | 指數退避重試（上限次數），逾期後觸發 failover |
| RTSP keep-alive 逾時 | 暫時性 | 重新協商 session |
| UDP 組播 IGMP 逾期 | 暫時性 | 定期主動 re-join，不等失敗才處理 |
| DNS 解析失敗 | 可能永久 | 立即嘗試備援線路，不做退避重試 |
| DRM 授權拒絕 | 永久 | 直接回報使用者，不重試 |

`TransportError` 從單一枚舉擴充為帶分類欄位的結構，`resilience.rs` 統一管理重試計數與退避時間表，任何 transport 實作（HTTP/RTSP/UDP/SRT/RTMP）共用同一套策略介面，不各自實作重試邏輯。

### 5.3 UDP/RTP 抗抖動與封包重排序

組播環境下封包可能亂序或丟失，`jitter_buffer.rs` 在 `demux` 之前加入緩衝視窗，依 RTP sequence number 重排序，逾時未到達的封包視為丟失並記錄供 QoS 統計，避免直接把亂序資料交給 demux 造成解析錯誤。

### 5.4 網路類型感知與能力探測

- App 啟動與網路切換時偵測連線類型（WiFi/行動網路/有線）。
- 組播頻道在偵測到行動網路時，UI 提前顯示「此線路需固網環境」提示並建議切換線路，而非直接嘗試連線失敗。
- 裝置解碼能力探測結果與此模組共享，用於 manifest 層選擇對應碼率版本（見 2.3 編碼能力探測）。

### 5.5 憑證信任鏈

見 4.3，統一放在 `transport::tls_trust`，供 HTTP/RTSP 等使用 TLS 的傳輸方式共用。

---

## 6. VOD / 時移 / 播放體驗細節（全新章節）

### 6.1 時移（Catch-up/Timeshift）

- EPG 節目資料需要標記 `catchup_available: bool` 與 `catchup_days: u8`，與 4.1 的 Xtream Codes 回看端點對接。
- `playback_fsm` 新增狀態轉移：「從直播模式切換到回看模式」需要保留當前直播 session 以便使用者可以快速返回直播。

### 6.2 VOD 特有能力

- **Trick play（快進快退縮圖預覽）**：需要在 `vod::trick_play` 模組定義縮圖產生策略（伺服器提供縮圖圖集優先，否則客戶端解碼關鍵幀產生）。
- **斷點續播**：`resume_position.rs` 記錄每個 VOD/劇集 episode 的播放進度，本機持久化，未來若接入會員系統可同步到雲端（介面預留，見第 10 章業務層擴充）。
- 劇集資料模型需支援分季分集導覽，原方案的 `source_provider` 只提到「劇集」字面，未展開結構，見 4.1 的 `Series` 定義。

---

## 7. 投放協議（新增章節，原方案完全未提）

若產品定位比照 TiviMate/IPTV Smarters，投放能力是常見期待功能，即使第一階段不實作也需在此明確表態：

| 協議 | 平台 | 第一階段決策 |
|---|---|---|
| Chromecast | 全平台 | 架構留位（`cast` trait），不在第一階段實作 |
| AirPlay | 蘋果生態 | 同上，第二階段（蘋果生態擴展）評估 |
| DLNA/UPnP | 區域網裝置 | 明確列為不支援，非長尾需求，不留架構位置以免過度設計 |

```rust
pub trait CastReceiver: Send {
    fn discover(&self) -> Vec<CastDevice>;
    fn cast_stream(&self, device: &CastDevice, manifest: &StreamManifest) -> Result<(), CastError>;
}
```

---

## 8. 家長鎖 / 存取控管（新增章節）

區分兩種層次，原方案的「頻道存取權限標記」只涵蓋後端驅動的會員分級，缺少裝置本機層級的家長鎖：

| 類型 | 驅動方 | 說明 |
|---|---|---|
| 會員分級權限 | 後端 | 見第 10 章業務層擴充，`Channel.access_level` |
| **本機 PIN 鎖（新增）** | 裝置本機 | 使用者自行設定 PIN，鎖定特定頻道/分類，不需要後端介入，`parental_control` 模組管理本機加密儲存的鎖定清單與 PIN 驗證邏輯 |

---

## 9. 工程基建（新增章節，原方案完全空白）

### 9.1 CI/測試矩陣

- 五個目標平台 × 多種 DRM 方案（Widevine L1/L3、FairPlay、PlayReady、ClearKey）組合測試無法完全自動化，需建立**分層測試策略**：core 模組（manifest/demux/subtitle 解析）用純 Rust 單元測試全自動化跑在 CI；平台解碼與 DRM 落地需要實機測試矩陣（至少各平台各一台低階與一台高階裝置），排入每次發布前的手動驗證清單。
- `ci/` 目錄需包含交叉編譯驗證（第 3 章的五個平台 target）與 core 模組的 fuzz 測試（尤其 manifest 解析器需要對抗畸形 m3u8/MPD 輸入）。

### 9.2 診斷與 Crash 回報

- `diagnostics` 模組統一收集播放失敗事件（transport 錯誤分類、DRM 授權失敗、解碼器初始化失敗），本機持久化為結構化日誌，使用者可選擇匯出或（未來）上傳協助除錯，不預設自動上傳以避免隱私爭議。
- 崩潰回報建議第一階段先用平台原生工具（Android 的 tombstone/ANR log、其他平台對應機制），不自研崩潰回報系統，避免分散第一階段工時。

### 9.3 更新機制

- 機上盒普遍不走 Google Play（sideload 安裝），`update_check` 模組需要提供「檢查新版本」的掛鉤點，第一階段可以只做「顯示有新版本，導引使用者手動下載」，不做靜默自動更新，避免機上盒環境下自動更新造成的相容性風險。

---

## 10. 業務層擴充規劃（未來階段，介面現在預留）

**自營會員系統**：帳號註冊、登入驗證、訂閱權限管理、多裝置登入限制。啟動流程預留「檢查登入/授權狀態」掛鉤點（現在固定回傳「已授權」）；所有後端請求統一經過同一層封裝，未來加身份驗證資訊只需修改這一層。

**私有後端伺服器對接**：等同新增一種 `SourceProvider` 實作，見第 4.3 章。

**頻道存取權限控管**：`Channel` 結構預留可選權限標記欄位，目前留空或預設全開放。

**播放進度雲端同步（新增，與 6.2 呼應）**：`resume_position` 本機記錄的播放進度，介面設計上要能無痛切換成「本機優先、雲端同步」模式，避免會員系統上線後重新設計進度記錄資料結構。

---

## 11. 統一媒體資料流（含韌性與 VOD 路徑）

```
[Source Provider]  →  ChannelSource { primary_url, backup_urls } / VodItem / Series
        │
        ▼
[Manifest 層]  判斷格式，含裝置能力探測後選擇對應碼率版本
        │  StreamManifest { transport_type, tracks, protection_hint, subtitle_tracks, color_space }
        ▼
[Transport 層]  建立連線；失敗時走 resilience（重試/退避）→ failover（切備援線路）
        │  HTTP 分片 / RTSP+RTP / UDP 組播（jitter_buffer）/ SRT / RTMP
        ▼
[Demux 層]  解封裝，拆出視訊/音訊/字幕/內嵌 CC
        │
        ├─→ [License Exchange]（含裝置安全等級探測）取得 CryptoSession
        │
        ▼
[Decoder 層]  HardwareDecoder::decode_frame(packet, crypto_session, color_space)
        │
        ├─→ [Subtitle 層]（含樣式偏好）
        ├─→ [Cast 層]（可選，投放到外部裝置）
        │
        ▼
[渲染管線]  Surface / Metal / D3D11 / Vulkan
```

---

## 12. 分階段實施時程（整合韌性與工程基建後重新排序）

| 階段 | 重點工作 | 涵蓋內容 |
|---|---|---|
| 第一步 | 建立 core 骨架（含 transport 韌性子系統佔位），落實模組邊界 | 架構佔位 |
| 第二步 | HLS 完整支援（AES-128/SAMPLE-AES）+ 多源備援 + 重連退避 | HLS 全家桶 + 5.1/5.2 |
| 第三步 | DASH 完整支援（CENC/ClearKey/Widevine）+ 裝置安全等級探測 | DASH + DRM |
| 第四步 | UDP 組播 MPEG-TS + jitter buffer + IGMP 定期 re-join | 5.3/5.4 |
| 第五步 | Xtream Codes 完整端點（含 VOD/劇集/回看）+ Stalker Portal token 管理 | 第 4 章 |
| 第六步 | Android 手機版 UI 跑通完整鏈路，含家長鎖本機 PIN | 第 8 章 |
| 第七步 | Android TV 版複用 core | — |
| 第八步 | CI 測試矩陣、診斷日誌、更新檢查機制落地 | 第 9 章 |
| 第九步 | RTSP/RTP、SRT 支援 | 長尾協議 |
| 第十步 | 字幕/CC 完整支援 + 樣式偏好持久化 | 2.4 |
| 第十一步 | VOD trick play + 斷點續播 | 第 6 章 |
| 第十二步 | 擴展 iOS/tvOS：VideoToolbox + FairPlay，AirPlay 評估 | — |
| 第十三步 | macOS 版 | — |
| 第十四步 | Windows 版：Media Foundation + PlayReady | — |
| 第十五步 | Linux 版：GStreamer/VA-API | — |
| 第十六步 | RTMP 支援（FFI 過渡） | 長尾格式 |
| 第十七步 | 投放協議（Chromecast）視需求評估 | 第 7 章 |
| 第十八步 | 會員系統與私有伺服器對接落地（含雲端進度同步） | 第 10 章 |

---

## 13. 關鍵技術棧一覽

| 用途 | 技術/工具 |
|---|---|
| 核心邏輯語言 | Rust |
| DASH 解析 | `dash-mpd` |
| MPEG-TS 解封裝 | `mpeg2ts-reader` |
| RTSP/RTP client | `retina` |
| SRT | `srt-tokio` |
| RTMP | FFI 包裝 librtmp（過渡） |
| 跨語言綁定 | UniFFI |
| Android UI | Kotlin + Jetpack Compose / Compose for TV |
| 蘋果生態 UI | Swift + SwiftUI |
| Windows UI | windows crate |
| Linux UI | gtk4-rs |
| 跨平台渲染 | wgpu |
| DRM | Widevine / FairPlay / PlayReady / ClearKey / HLS AES-128 / SAMPLE-AES |
| 播放清單協議 | M3U/M3U8、Xtream Codes API（含 VOD/回看）、Stalker Portal |
| 傳輸協議 | HTTP、RTSP/RTP、UDP 組播、SRT、RTMP |
| 字幕格式 | WebVTT、TTML/EBU-TT-D、CEA-608/708、SRT 字幕 |
| 音訊編碼 | AAC-LC/HE-AAC、AC-3、E-AC-3、MP3、Opus |
| 視訊編碼與色彩 | H.264、H.265、AV1（dav1d 軟解兜底）、HDR10/HLG |
| EPG 格式 | XMLTV、供應商專屬端點、回看索引 |
| 診斷 | 本機結構化日誌 + 平台原生崩潰工具 |
| CI | Rust 單元測試 + fuzz（manifest 解析）+ 交叉編譯驗證 |

---

## 14. 風險與備選方案

- **RTMP 生態成熟度**：Rust 原生 crate 有限，FFI 包 librtmp 過渡，不自研協議棧。
- **UDP 組播網路依賴**：需 IGMP 支援，行動網路幾乎不可用，架構已納入能力探測降級提示（5.4）。
- **MSS 投入報酬率**：市佔率下降，時程尾端，可能降級為「不保證支援」。
- **AV1 硬解覆蓋率**：中低階裝置需 dav1d 軟解，注意功耗發熱。
- **Widevine L1/L3 裝置碎片化**：非認證機上盒可能降級或吊銷，需裝置安全等級探測與使用者告知（見第 2.5 章末）。
- **自簽憑證信任的安全風險**：私有伺服器對接允許使用者手動信任憑證，必須有明確 UI 警示，避免使用者誤信任惡意憑證。
- **Slint/tvOS 模擬器工具鏈、Linux DRM 支援有限**：均沿用既有判斷，非本次新增風險。

---

## 15. 版本差異與缺口收斂記錄

| 版本 | 主要變更 |
|---|---|
| v1 | 初版架構，僅針對 HLS/DASH 做邊界細化 |
| v2 | 補齊傳輸協議全景（RTSP/RTMP/UDP組播/SRT）、音訊編碼、字幕/CC、DRM 七變體、五層模組拆分 |
| **v3（本版）** | 補齊傳輸韌性（多源備援/重連退避/jitter buffer/網路感知/憑證信任）、供應商協議端點級規格（Xtream VOD/回看、Stalker token）、HDR/色彩管線、VOD/時移完整功能、投放協議表態、本機家長鎖、工程基建（CI/診斷/更新機制）、Widevine 裝置佈建風險 |

本版審查範圍涵蓋原始兩份文件（架構方案 v2 完整重寫版、開發方案 v2.0）全文，逐段核對後補齊上述缺口，目前架構層面已無已知遺漏；後續若在實作階段發現新的供應商協議怪癖或平台 API 限制，應以「新增章節」方式擴充本文件，不應繞過核心架構另行處理。
