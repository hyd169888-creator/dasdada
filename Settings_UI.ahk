#Requires AutoHotkey v2.0

class SettingsUI {
    static configFile := A_ScriptDir . "\config.json"
    static gui := 0
    static wv := 0
    static onHotkeysUpdatedCallback := 0

    ; 默认配置
    static defaultConfig := Map(
        "source_lang", "auto",
        "target_lang", "en",
        "provider", "custom",
        "base_url", "https://tokenrhythm.studio/v1",
        "model", "deepseek-v4-flash",
        "api_key", "",
        "hotkeys", Map(
            "show_bar", "!y",
            "settings", "!s"
        )
    )

    ; 读取配置
    static LoadConfig() {
        if !FileExist(this.configFile) {
            this.SaveConfig(this.defaultConfig)
            return this.defaultConfig
        }

        try {
            content := FileRead(this.configFile, "UTF-8")
            if (Trim(content) == "")
                return this.defaultConfig
            
            parsed := this._ParseJsonToMap(content)
            return parsed
        } catch {
            return this.defaultConfig
        }
    }

    ; 保存配置
    static SaveConfig(cfgMap) {
        jsonStr := this._MapToJson(cfgMap)
        try {
            if FileExist(this.configFile)
                FileDelete(this.configFile)
            FileAppend(jsonStr, this.configFile, "UTF-8")
            return true
        } catch {
            return false
        }
    }

    ; 显示设置中心
    static Show() {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.gui.Show()
            WinActivate("ahk_id " . this.gui.Hwnd)
            return
        }

        g := Gui("-MaximizeBox -MinimizeBox", "AI 智能打字翻译 - 设置中心")
        g.BackColor := "0xF8FAF5"
        g.MarginX := 0
        g.MarginY := 0
        this.gui := g

        wbCtl := g.Add("ActiveX", "w460 h735", "Shell.Explorer")
        this.wv := wbCtl.Value
        this.wv.silent := true
        this.wv.Navigate("about:blank")
        while (this.wv.ReadyState != 4)
            Sleep(10)

        cfg := this.LoadConfig()
        localVer := FileExist(A_ScriptDir . "\version.txt") ? Trim(FileRead(A_ScriptDir . "\version.txt", "UTF-8")) : "1.0.1"

        html := this._BuildHtml(cfg, localVer)
        doc := this.wv.Document
        doc.open()
        doc.write(html)
        doc.close()

        ; 注册 Web 交互桥接
        bridge := {
            SaveSettings: (sourceLang, targetLang, provider, baseUrl, model, apiKey) => SettingsUI._OnSaveSettings(sourceLang, targetLang, provider, baseUrl, model, apiKey),
            TestApi: (provider, baseUrl, model, apiKey) => SettingsUI._OnTestApi(provider, baseUrl, model, apiKey)
        }
        doc.parentWindow.ahkBridge := bridge

        g.OnEvent("Close", (*) => g.Hide())
        g.Show("w460 h735 Center")
    }

    static _OnSaveSettings(sourceLang, targetLang, provider, baseUrl, model, apiKey) {
        cfg := this.LoadConfig()
        cfg["source_lang"] := sourceLang
        cfg["target_lang"] := targetLang
        cfg["provider"] := provider
        cfg["base_url"] := baseUrl
        cfg["model"] := model
        cfg["api_key"] := apiKey

        if this.SaveConfig(cfg) {
            MsgBox("设置已成功保存并立即生效！", "保存成功", "Iconi")
        } else {
            MsgBox("配置文件写入失败，请检查文件写入权限。", "保存失败", "Iconx")
        }
    }

    static _OnTestApi(provider, baseUrl, model, apiKey) {
        if (apiKey == "") {
            MsgBox("请先输入 API Key 再进行测试！", "提示", "Icon!")
            return
        }

        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(5000, 5000, 10000, 10000)
            req.Open("POST", baseUrl . "/chat/completions", false)
            req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
            req.SetRequestHeader("Authorization", "Bearer " . apiKey)
            
            body := '{"model":"' . model . '","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}'
            req.Send(body)

            if (req.Status == 200) {
                MsgBox("🎉 API 探测成功！模型响应正常，网络通道通畅。", "连接成功", "Iconi")
            } else {
                MsgBox("❌ 连接失败！HTTP 状态码: " . req.Status . "`n返回内容: " . req.ResponseText, "连接失败", "Iconx")
            }
        } catch as e {
            MsgBox("❌ 无法连接到指定服务端点，请检查网络/魔法或 Base URL 是否正确。`n错误详情: " . e.Message, "连接异常", "Iconx")
        }
    }

    static _BuildHtml(cfg, ver) {
        sLang := cfg.Has("source_lang") ? cfg["source_lang"] : "auto"
        tLang := cfg.Has("target_lang") ? cfg["target_lang"] : "en"
        prov := cfg.Has("provider") ? cfg["provider"] : "nvidia"
        bUrl := cfg.Has("base_url") ? cfg["base_url"] : "https://integrate.api.nvidia.com/v1"
        mdl := cfg.Has("model") ? cfg["model"] : "meta/llama-3.1-8b-instruct"
        key := cfg.Has("api_key") ? cfg["api_key"] : ""

        optSLangAuto := (sLang == "auto") ? "selected" : ""
        optSLangZh := (sLang == "zh") ? "selected" : ""
        optSLangEn := (sLang == "en") ? "selected" : ""

        optTLangEn := (tLang == "en") ? "selected" : ""
        optTLangZh := (tLang == "zh") ? "selected" : ""
        optTLangPl := (tLang == "pl") ? "selected" : ""
        optTLangJa := (tLang == "ja") ? "selected" : ""
        optTLangKo := (tLang == "ko") ? "selected" : ""

        optProvNvidia := (prov == "nvidia") ? "selected" : ""
        optProvCustom := (prov == "custom") ? "selected" : ""

        htmlTemplate := "
        (
        <!DOCTYPE html>
        <html>
        <head>
        <meta http-equiv='X-UA-Compatible' content='IE=edge'>
        <meta charset='utf-8'>
        <style>
            * {
                box-sizing: border-box;
                margin: 0;
                padding: 0;
                user-select: none;
                -webkit-user-select: none;
                font-family: -apple-system, 'Microsoft YaHei UI', 'Segoe UI', sans-serif;
            }
            html, body {
                background: #F8FAF5;
                padding: 16px 20px;
                color: #18181B;
                overflow: hidden;
                height: 100%;
            }
            .header {
                display: flex;
                align-items: center;
                justify-content: space-between;
                margin-bottom: 12px;
            }
            .header-left {
                display: flex;
                align-items: center;
                gap: 8px;
            }
            /* 图标徽章 */
            .logo-wrap {
                width: 36px;
                height: 32px;
                background: #A7F3D0;
                border-radius: 8px;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                box-shadow: 0 1px 4px rgba(167, 243, 208, 0.6);
            }
            .logo-badges {
                display: flex;
                gap: 2px;
            }
            .bubble-icon {
                background: #FFFFFF;
                color: #059669;
                font-size: 8px;
                font-weight: 900;
                padding: 1px 2px;
                border-radius: 3px;
                line-height: 1;
            }
            .keyboard-dots {
                display: flex;
                gap: 1px;
                margin-top: 2px;
            }
            .kbd-dot {
                width: 3px;
                height: 2px;
                background: #059669;
                border-radius: 1px;
            }

            .logo-text-box {
                display: flex;
                flex-direction: column;
            }
            .logo-title {
                font-size: 15px;
                font-weight: 900;
                color: #0F172A;
                line-height: 1.1;
                letter-spacing: 0.3px;
            }
            .logo-subtitle {
                font-size: 10px;
                font-weight: 500;
                color: #64748B;
            }
            .badge-bar {
                display: flex;
                align-items: center;
                gap: 10px;
            }
            .badge-btn {
                background: #18181B;
                color: #FFFFFF;
                padding: 4px 14px;
                border-radius: 20px;
                font-size: 11px;
                font-weight: 800;
            }
            .badge-text-link {
                color: #64748B;
                font-size: 11px;
                font-weight: 700;
            }
            
            .tagline {
                font-size: 11px;
                font-weight: 800;
                color: #6366F1;
                letter-spacing: 0.5px;
                margin-bottom: 2px;
            }
            .main-title {
                font-size: 17px;
                font-weight: 900;
                color: #0F172A;
                margin-bottom: 2px;
            }
            .main-desc {
                font-size: 11px;
                color: #64748B;
                margin-bottom: 14px;
            }

            /* 卡片容器 */
            .card {
                background: #FFFFFF;
                border: 1.5px solid #E2E8F0;
                border-radius: 12px;
                padding: 14px 16px;
                margin-bottom: 12px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.02);
            }
            .card-label {
                font-size: 11px;
                font-weight: 800;
                color: #64748B;
                letter-spacing: 0.5px;
                margin-bottom: 10px;
            }
            .field-row {
                display: flex;
                align-items: center;
                justify-content: space-between;
                margin-bottom: 10px;
            }
            .field-row:last-child {
                margin-bottom: 0;
            }
            .field-label {
                font-size: 12px;
                font-weight: 800;
                color: #334155;
            }

            /* 彻底消除 IE 默认灰块箭头的 CSS 规则 */
            select::-ms-expand {
                display: none;
            }

            /* 1:1 还原图 2 的绿边圆润输入框与下拉框 */
            select, input {
                width: 285px;
                height: 34px;
                border: 2px solid #84CC16;
                border-radius: 8px;
                padding: 0 10px;
                font-size: 12px;
                font-weight: 700;
                color: #18181B;
                background-color: #FFFFFF;
                outline: none;
            }
            select {
                appearance: none;
                -webkit-appearance: none;
                -moz-appearance: none;
                background-image: url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"%2384CC16\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"6 9 12 15 18 9\"></polyline></svg>');
                background-repeat: no-repeat;
                background-position: right 10px center;
                padding-right: 28px;
                cursor: pointer;
            }
            input:focus, select:focus {
                border-color: #65A30D;
            }

            /* 状态卡片 */
            .status-card {
                background: #D8FA63;
                border-radius: 10px;
                padding: 10px 14px;
                margin-bottom: 12px;
            }
            .status-title {
                font-size: 11px;
                font-weight: 800;
                color: #18181B;
            }
            .status-desc {
                font-size: 11px;
                font-weight: 700;
                color: #18181B;
                margin-top: 2px;
            }

            /* 按钮组 */
            .btn-group {
                display: flex;
                gap: 10px;
            }
            .btn-test {
                flex: 1;
                height: 38px;
                background: #18181B;
                color: #FFFFFF;
                border: none;
                border-radius: 10px;
                font-size: 12px;
                font-weight: 800;
                cursor: pointer;
                outline: none;
            }
            .btn-test:hover {
                background: #27272A;
            }
            .btn-save {
                flex: 1;
                height: 38px;
                background: #D8FA63;
                color: #18181B;
                border: 1px solid #C4E840;
                border-radius: 10px;
                font-size: 12px;
                font-weight: 800;
                cursor: pointer;
                box-shadow: 0 3px 10px rgba(216, 250, 99, 0.35);
                outline: none;
            }
            .btn-save:hover {
                background: #CBF048;
            }

            /* 底部版本徽章 */
            .ver-bottom {
                display: flex;
                justify-content: center;
                margin-top: 14px;
            }
            .ver-badge {
                background: #D8FA63;
                color: #18181B;
                padding: 3px 14px;
                border-radius: 6px;
                font-size: 11px;
                font-weight: 800;
            }
        </style>
        </head>
        <body>
            <div class='header'>
                <div class='header-left'>
                    <div class='logo-wrap'>
                        <div class='logo-badges'>
                            <span class='bubble-icon'>A</span>
                            <span class='bubble-icon'>文</span>
                        </div>
                        <div class='keyboard-dots'>
                            <div class='kbd-dot'></div>
                            <div class='kbd-dot'></div>
                            <div class='kbd-dot'></div>
                            <div class='kbd-dot'></div>
                        </div>
                    </div>
                    <div class='logo-text-box'>
                        <div class='logo-title'>AI TRANSLATOR</div>
                        <div class='logo-subtitle'>with Live Brain</div>
                    </div>
                </div>
                <div class='badge-bar'>
                    <div class='badge-btn'>实时引擎</div>
                    <div class='badge-text-link'>快捷键</div>
                </div>
            </div>

            <div class='tagline'>LIVE INTELLIGENT TRANSLATION</div>
            <div class='main-title'>打字翻译，在每一次思考后生成</div>
            <div class='main-desc'>连接大模型大脑，自动识别中外文并地道转化输出。</div>

            <div class='card'>
                <div class='card-label'>LANGUAGE PREFERENCE · 语言设定</div>
                <div class='field-row'>
                    <span class='field-label'>源语言</span>
                    <select id='sourceLang'>
                        <option value='auto' {{OPT_S_AUTO}}>自动识别 (中英双向智能互译)</option>
                        <option value='zh' {{OPT_S_ZH}}>Chinese (中文)</option>
                        <option value='en' {{OPT_S_EN}}>English (英语)</option>
                    </select>
                </div>
                <div class='field-row'>
                    <span class='field-label'>目标语言</span>
                    <select id='targetLang'>
                        <option value='en' {{OPT_T_EN}}>English (英语)</option>
                        <option value='zh' {{OPT_T_ZH}}>Chinese (中文)</option>
                        <option value='pl' {{OPT_T_PL}}>Polish (波兰语)</option>
                        <option value='ja' {{OPT_T_JA}}>Japanese (日语)</option>
                        <option value='ko' {{OPT_T_KO}}>Korean (韩语)</option>
                    </select>
                </div>
            </div>

            <div class='card'>
                <div class='card-label'>AI ENGINE & ENDPOINT · 大模型配置</div>
                <div class='field-row'>
                    <span class='field-label'>AI 平台</span>
                    <select id='provider'>
                        <option value='nvidia' {{OPT_PROV_NVIDIA}}>NVIDIA·免费满血模型 (需魔法)</option>
                        <option value='custom' {{OPT_PROV_CUSTOM}}>自定义API(OpenAI 协议兼容)</option>
                    </select>
                </div>
                <div class='field-row'>
                    <span class='field-label'>Base URL</span>
                    <input type='text' id='baseUrl' value='{{BASE_URL}}'>
                </div>
                <div class='field-row'>
                    <span class='field-label'>Model Name</span>
                    <input type='text' id='model' value='{{MODEL_NAME}}'>
                </div>
                <div class='field-row'>
                    <span class='field-label'>API Key</span>
                    <input type='password' id='apiKey' value='{{API_KEY}}'>
                </div>
            </div>

            <div class='status-card'>
                <div class='status-title'>SYSTEM STATUS · 状态反馈</div>
                <div class='status-desc'>💡 准备就绪，可点击下方按钮发起连通性探针测试。</div>
            </div>

            <div class='btn-group'>
                <button class='btn-test' onclick='testApi()'>🚀 检测 API 有效性</button>
                <button class='btn-save' onclick='saveSettings()'>💾 保存并生效</button>
            </div>

            <div class='ver-bottom'>
                <div class='ver-badge'>当前版本: v{{VER}}</div>
            </div>

            <script>
                function saveSettings() {
                    var sLang = document.getElementById('sourceLang').value;
                    var tLang = document.getElementById('targetLang').value;
                    var prov = document.getElementById('provider').value;
                    var bUrl = document.getElementById('baseUrl').value;
                    var mdl = document.getElementById('model').value;
                    var key = document.getElementById('apiKey').value;
                    window.ahkBridge.SaveSettings(sLang, tLang, prov, bUrl, mdl, key);
                }
                function testApi() {
                    var prov = document.getElementById('provider').value;
                    var bUrl = document.getElementById('baseUrl').value;
                    var mdl = document.getElementById('model').value;
                    var key = document.getElementById('apiKey').value;
                    window.ahkBridge.TestApi(prov, bUrl, mdl, key);
                }
            </script>
        </body>
        </html>
        )"

        html := StrReplace(htmlTemplate, "{{BASE_URL}}", bUrl)
        html := StrReplace(html, "{{MODEL_NAME}}", mdl)
        html := StrReplace(html, "{{API_KEY}}", key)
        html := StrReplace(html, "{{VER}}", ver)
        html := StrReplace(html, "{{OPT_S_AUTO}}", optSLangAuto)
        html := StrReplace(html, "{{OPT_S_ZH}}", optSLangZh)
        html := StrReplace(html, "{{OPT_S_EN}}", optSLangEn)
        html := StrReplace(html, "{{OPT_T_EN}}", optTLangEn)
        html := StrReplace(html, "{{OPT_T_ZH}}", optTLangZh)
        html := StrReplace(html, "{{OPT_T_PL}}", optTLangPl)
        html := StrReplace(html, "{{OPT_T_JA}}", optTLangJa)
        html := StrReplace(html, "{{OPT_T_KO}}", optTLangKo)
        html := StrReplace(html, "{{OPT_PROV_NVIDIA}}", optProvNvidia)
        html := StrReplace(html, "{{OPT_PROV_CUSTOM}}", optProvCustom)
        return html
    }

    ; JSON 解析转 Map
    static _ParseJsonToMap(jsonStr) {
        cfg := Map(
            "source_lang", RegExMatch(jsonStr, '"source_lang"\s*:\s*"([^"]+)"', &m1) ? m1[1] : "auto",
            "target_lang", RegExMatch(jsonStr, '"target_lang"\s*:\s*"([^"]+)"', &m2) ? m2[1] : "en",
            "provider", RegExMatch(jsonStr, '"provider"\s*:\s*"([^"]+)"', &m3) ? m3[1] : "nvidia",
            "base_url", RegExMatch(jsonStr, '"base_url"\s*:\s*"([^"]+)"', &m4) ? m4[1] : "https://integrate.api.nvidia.com/v1",
            "model", RegExMatch(jsonStr, '"model"\s*:\s*"([^"]+)"', &m5) ? m5[1] : "meta/llama-3.1-8b-instruct",
            "api_key", RegExMatch(jsonStr, '"api_key"\s*:\s*"([^"]*)"', &m6) ? m6[1] : "",
            "hotkeys", Map(
                "show_bar", RegExMatch(jsonStr, '"show_bar"\s*:\s*"([^"]+)"', &h1) ? h1[1] : "!y",
                "settings", RegExMatch(jsonStr, '"settings"\s*:\s*"([^"]+)"', &h2) ? h2[1] : "!s"
            )
        )
        return cfg
    }

    ; Map 转 JSON
    static _MapToJson(cfg) {
        hk := cfg.Has("hotkeys") ? cfg["hotkeys"] : Map("show_bar", "!y", "settings", "!s")
        hBar := hk.Has("show_bar") ? hk["show_bar"] : "!y"
        hSet := hk.Has("settings") ? hk["settings"] : "!s"

        return '{`n'
            . '  "source_lang": "' . cfg["source_lang"] . '",`n'
            . '  "target_lang": "' . cfg["target_lang"] . '",`n'
            . '  "provider": "' . cfg["provider"] . '",`n'
            . '  "base_url": "' . cfg["base_url"] . '",`n'
            . '  "model": "' . cfg["model"] . '",`n'
            . '  "api_key": "' . cfg["api_key"] . '",`n'
            . '  "hotkeys": {`n'
            . '    "show_bar": "' . hBar . '",`n'
            . '    "settings": "' . hSet . '"`n'
            . '  }`n'
            . '}'
    }
}