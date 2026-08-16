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

        wbCtl := g.Add("ActiveX", "w450 h720", "Shell.Explorer")
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
        g.Show("w450 h720 Center")
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
        prov := cfg.Has("provider") ? cfg["provider"] : "custom"
        bUrl := cfg.Has("base_url") ? cfg["base_url"] : "https://tokenrhythm.studio/v1"
        mdl := cfg.Has("model") ? cfg["model"] : "deepseek-v4-flash"
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
                padding: 14px 18px;
                color: #18181B;
                overflow: hidden;
                height: 100%;
            }
            .header {
                display: flex;
                align-items: center;
                justify-content: space-between;
                margin-bottom: 10px;
            }
            .header-left {
                display: flex;
                align-items: center;
                gap: 10px;
            }
            /* 1:1 矢量 Logo 图标 */
            .logo-img {
                width: 36px;
                height: 36px;
                display: block;
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
                font-size: 10.5px;
                font-weight: 800;
                color: #6366F1;
                letter-spacing: 0.5px;
                margin-bottom: 2px;
            }
            .main-title {
                font-size: 16.5px;
                font-weight: 900;
                color: #0F172A;
                margin-bottom: 2px;
            }
            .main-desc {
                font-size: 10.5px;
                color: #64748B;
                margin-bottom: 12px;
            }

            /* 卡片容器 */
            .card {
                background: #FFFFFF;
                border: 1.5px solid #E2E8F0;
                border-radius: 12px;
                padding: 12px 14px;
                margin-bottom: 10px;
            }
            .card-label {
                font-size: 10.5px;
                font-weight: 800;
                color: #64748B;
                letter-spacing: 0.5px;
                margin-bottom: 8px;
            }
            .field-row {
                display: flex;
                align-items: center;
                justify-content: space-between;
                margin-bottom: 8px;
            }
            .field-row:last-child {
                margin-bottom: 0;
            }
            .field-label {
                font-size: 11.5px;
                font-weight: 800;
                color: #334155;
            }

            /* 下拉框独立容器架构，确保翠绿箭头绝对可见 */
            .select-wrap {
                position: relative;
                width: 270px;
            }
            .select-wrap select {
                width: 100%;
                height: 32px;
                border: 2px solid #84CC16;
                border-radius: 8px;
                padding: 0 28px 0 10px;
                font-size: 11.5px;
                font-weight: 700;
                color: #18181B;
                background-color: #FFFFFF;
                outline: none;
                cursor: pointer;
                -webkit-appearance: none;
                -moz-appearance: none;
                appearance: none;
            }
            .select-wrap select::-ms-expand {
                display: none;
            }
            .select-arrow {
                position: absolute;
                right: 10px;
                top: 50%;
                margin-top: -3px;
                width: 8px;
                height: 8px;
                border-right: 2.2px solid #84CC16;
                border-bottom: 2.2px solid #84CC16;
                transform: rotate(45deg);
                pointer-events: none;
            }

            /* 输入框 */
            input {
                width: 270px;
                height: 32px;
                border: 2px solid #84CC16;
                border-radius: 8px;
                padding: 0 10px;
                font-size: 11.5px;
                font-weight: 700;
                color: #18181B;
                background-color: #FFFFFF;
                outline: none;
            }
            input:focus, select:focus {
                border-color: #65A30D;
            }

            /* 状态卡片 */
            .status-card {
                background: #D8FA63;
                border-radius: 10px;
                padding: 9px 12px;
                margin-bottom: 10px;
            }
            .status-title {
                font-size: 10.5px;
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
                margin-top: 12px;
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
                    <!-- 精准矢量 Logo -->
                    <img class='logo-img' src='data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0OCA0OCIgd2lkdGg9IjQ4IiBoZWlnaHQ9IjQ4Ij48cmVjdCB3aWR0aD0iNDgiIGhlaWdodD0iNDgiIHJ4PSIxMiIgZmlsbD0iIzZFRTdCNyIvPjxyZWN0IHg9IjYiIHk9IjgiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNCIgcng9IjQiIGZpbGw9IiNGRkZGRkYiLz48dGV4dCB4PSIxNCIgeT0iMTkiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtZmFtaWx5PSJBcmlhbCwgc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjkwMCIgZmlsbD0iIzA2NUY0NiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+QTwvdGV4dD48cmVjdCB4PSIyNCIgeT0iOCIgd2lkdGg9IjE4IiBoZWlnaHQ9IjE0IiByeD0iNCIgZmlsbD0iI0ZGRkZGRiIvPjx0ZXh0IHg9IjMzIiB5PSIxOSIgZm9udC1zaXplPSIxMSIgZm9udC1mYW1pbHk9Ik1pY3Jvc29mdCBZYUhlaSwgc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjkwMCIgZmlsbD0iIzA2NUY0NiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+5paHPC90ZXh0PjxyZWN0IHg9IjgiIHk9IjI3IiB3aWR0aD0iMzIiIGhlaWdodD0iMTMiIHJ4PSIzIiBmaWxsPSIjMDY1RjQ2IiBmaWxsLW9wYWNpdHk9IjAuMTUiLz48cmVjdCB4PSIxMSIgeT0iMjkiIHdpZHRoPSI0IiBoZWlnaHQ9IjMiIHJ4PSIxIiBmaWxsPSIjMDY1RjQ2Ii8+PHJlY3QgeD0iMTciIHk9IjI5IiB3aWR0aD0iNCIgaGVpZ2h0PSIzIiByeD0iMSIgZmlsbD0iIzA2NUY0NiIvPjxyZWN0IHg9IjIzIiB5PSIyOSIgd2lkdGg9IjQiIGhlaWdodD0iMyIgcng9IjEiIGZpbGw9IiMwNjVGNDYiLz48cmVjdCB4PSIyOSIgeT0iMjkiIHdpZHRoPSI0IiBoZWlnaHQ9IjMiIHJ4PSIxIiBmaWxsPSIjMDY1RjQ2Ii8+PHJlY3QgeD0iMTMiIHk9IjM0IiB3aWR0aD0iMjIiIGhlaWdodD0iMyIgcng9IjEiIGZpbGw9IiMwNjVGNDYiLz48L3N2Zz4=' />
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
                    <div class='select-wrap'>
                        <select id='sourceLang'>
                            <option value='auto' {{OPT_S_AUTO}}>自动识别 (中英双向智能互译)</option>
                            <option value='zh' {{OPT_S_ZH}}>Chinese (中文)</option>
                            <option value='en' {{OPT_S_EN}}>English (英语)</option>
                        </select>
                        <div class='select-arrow'></div>
                    </div>
                </div>
                <div class='field-row'>
                    <span class='field-label'>目标语言</span>
                    <div class='select-wrap'>
                        <select id='targetLang'>
                            <option value='en' {{OPT_T_EN}}>English (英语)</option>
                            <option value='zh' {{OPT_T_ZH}}>Chinese (中文)</option>
                            <option value='pl' {{OPT_T_PL}}>Polish (波兰语)</option>
                            <option value='ja' {{OPT_T_JA}}>Japanese (日语)</option>
                            <option value='ko' {{OPT_T_KO}}>Korean (韩语)</option>
                        </select>
                        <div class='select-arrow'></div>
                    </div>
                </div>
            </div>

            <div class='card'>
                <div class='card-label'>AI ENGINE & ENDPOINT · 大模型配置</div>
                <div class='field-row'>
                    <span class='field-label'>AI 平台</span>
                    <div class='select-wrap'>
                        <select id='provider'>
                            <option value='custom' {{OPT_PROV_CUSTOM}}>自定义API(OpenAI 协议兼容)</option>
                            <option value='nvidia' {{OPT_PROV_NVIDIA}}>NVIDIA·免费满血模型 (需魔法)</option>
                        </select>
                        <div class='select-arrow'></div>
                    </div>
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
                <div class='status-desc'>已切换至「Custom」，专属配置已自动载入。</div>
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
            "provider", RegExMatch(jsonStr, '"provider"\s*:\s*"([^"]+)"', &m3) ? m3[1] : "custom",
            "base_url", RegExMatch(jsonStr, '"base_url"\s*:\s*"([^"]+)"', &m4) ? m4[1] : "https://tokenrhythm.studio/v1",
            "model", RegExMatch(jsonStr, '"model"\s*:\s*"([^"]+)"', &m5) ? m5[1] : "deepseek-v4-flash",
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